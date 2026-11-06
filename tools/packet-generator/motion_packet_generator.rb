#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "socket"

class MotionPacket
  MAGIC = 0x4D42
  VERSION = 1
  TYPE = 5
  HEADER_SIZE = 28
  PAYLOAD_SIZE = 52

  def self.encode(session_id:, controller_id:, sequence:, sensor_ns:, sample_index:, rate:)
    time_s = sample_index.to_f / rate
    phase = time_s * Math::PI * 2.0
    accel = [
      Math.sin(phase) * 6.0,
      Math.cos(phase * 0.5) * 3.0,
      -9.80665 + Math.sin(phase * 0.25) * 1.5
    ]
    gyro = [
      Math.sin(phase * 1.5) * 5.0,
      Math.cos(phase) * 3.0,
      Math.sin(phase * 0.75) * 2.0
    ]
    half_angle = Math.sin(phase * 0.2) * 0.25
    orientation = [0.0, 0.0, Math.sin(half_angle), Math.cos(half_angle)]
    payload = [sensor_ns].pack("Q>") +
      (accel + gyro + orientation).pack("g*") +
      [3, 0x0F, 0].pack("CCn")
    header = [
      MAGIC, VERSION, TYPE, 0, HEADER_SIZE, PAYLOAD_SIZE, 0,
      session_id, controller_id, sequence
    ].pack("nCCnnnnQ>NN")
    header + payload
  end

  def self.validate(bytes)
    return "TOO_SHORT" if bytes.bytesize < HEADER_SIZE
    magic, version, type, flags, header_size, payload_size, reserved,
      session_id, controller_id, = bytes.unpack("nCCnnnnQ>NN")
    return "BAD_MAGIC" unless magic == MAGIC
    return "UNSUPPORTED_VERSION" unless version == VERSION
    return "UNKNOWN_MESSAGE_TYPE" unless type == TYPE
    return "INVALID_FLAGS" unless flags.zero?
    return "INVALID_HEADER_LENGTH" unless header_size == HEADER_SIZE
    return "INVALID_PAYLOAD_LENGTH" unless payload_size == PAYLOAD_SIZE && bytes.bytesize == 80
    return "NONZERO_RESERVED" unless reserved.zero?
    return "INVALID_SESSION_ID" if session_id.zero?
    return "INVALID_CONTROLLER_ID" if controller_id.zero?

    payload = bytes.byteslice(HEADER_SIZE, PAYLOAD_SIZE)
    sensor_ns = payload.unpack1("Q>")
    floats = payload.byteslice(8, 40).unpack("g*")
    accuracy, sensor_flags, payload_reserved = payload.byteslice(48, 4).unpack("CCn")
    return "NONZERO_RESERVED" unless payload_reserved.zero?
    return "INVALID_ENUM" unless [0, 1, 2, 3, 255].include?(accuracy)
    return "INVALID_ENUM" unless (sensor_flags & 0xE0).zero? && (sensor_flags & 0x07) == 0x07
    return "NON_FINITE_FLOAT" unless floats.all?(&:finite?)
    quaternion = floats.last(4)
    magnitude = Math.sqrt(quaternion.sum { |value| value * value })
    return "INVALID_QUATERNION" unless magnitude.between?(0.98, 1.02)
    return "INVALID_VALUE" if sensor_ns.zero?
    return "INVALID_VALUE" unless floats[0, 3].all? { |value| value.abs <= 200.0 }
    return "INVALID_VALUE" unless floats[3, 3].all? { |value| value.abs <= 100.0 }

    nil
  end
end

options = {
  host: "127.0.0.1",
  port: 7000,
  rate: 200,
  duration: 10.0,
  controllers: 1,
  seed: 1,
  loss: 0.0,
  duplicate: 0.0,
  reorder: 0.0,
  delay_ms: 0.0,
  invalid_every: 0,
  dry_run: false,
  pace: true,
  session_id: 0x0102_0304_0506_0708
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: motion_packet_generator.rb [options]"
  opts.on("--host HOST", "Destination host (default 127.0.0.1)") { |value| options[:host] = value }
  opts.on("--port PORT", Integer, "Destination UDP port") { |value| options[:port] = value }
  opts.on("--rate HZ", Integer, "Packets/second/controller") { |value| options[:rate] = value }
  opts.on("--duration SECONDS", Float, "Run duration") { |value| options[:duration] = value }
  opts.on("--controllers COUNT", Integer, "One or two controllers") { |value| options[:controllers] = value }
  opts.on("--seed SEED", Integer, "Deterministic impairment seed") { |value| options[:seed] = value }
  opts.on("--loss PROBABILITY", Float, "Drop probability 0..1") { |value| options[:loss] = value }
  opts.on("--duplicate PROBABILITY", Float, "Duplicate probability 0..1") { |value| options[:duplicate] = value }
  opts.on("--reorder PROBABILITY", Float, "One-sample reorder probability 0..1") { |value| options[:reorder] = value }
  opts.on("--delay-ms MILLISECONDS", Float, "Fixed delivery delay") { |value| options[:delay_ms] = value }
  opts.on("--invalid-every COUNT", Integer, "Corrupt every Nth emitted original") { |value| options[:invalid_every] = value }
  opts.on("--session-id HEX", "Nonzero 64-bit hexadecimal session ID") { |value| options[:session_id] = Integer(value, 16) }
  opts.on("--dry-run", "Generate and validate without UDP") { options[:dry_run] = true }
  opts.on("--no-pace", "Run logical time as fast as possible (requires --dry-run)") { options[:pace] = false }
  opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
end
parser.parse!

abort("rate must be 1..1000") unless options[:rate].between?(1, 1000)
abort("duration must be positive") unless options[:duration].positive?
abort("controllers must be 1 or 2") unless options[:controllers].between?(1, 2)
abort("port must be 1..65535") unless options[:port].between?(1, 65_535)
abort("session ID must be nonzero") if options[:session_id].zero?
%i[loss duplicate reorder].each do |key|
  abort("#{key} must be 0..1") unless options[key].between?(0.0, 1.0)
end
abort("delay must be nonnegative") if options[:delay_ms].negative?
abort("invalid-every must be nonnegative") if options[:invalid_every].negative?
abort("--no-pace requires --dry-run") if !options[:pace] && !options[:dry_run]

rng = Random.new(options[:seed])
socket = UDPSocket.new unless options[:dry_run]
destination = Socket.sockaddr_in(options[:port], options[:host]) unless options[:dry_run]
interval_ns = (1_000_000_000.0 / options[:rate]).round
sample_count = (options[:duration] * options[:rate]).round
controller_ids = Array.new(options[:controllers]) { |index| 0x0A0B_0C0D + index }
sequences = controller_ids.to_h { |id| [id, 0] }
pending = controller_ids.to_h { |id| [id, nil] }
summary = {
  seed: options[:seed],
  configured_rate_hz: options[:rate],
  controllers: options[:controllers],
  logical_duration_s: options[:duration],
  samples_generated: 0,
  codec_validated: 0,
  codec_rejections: 0,
  datagrams_emitted: 0,
  lost: 0,
  duplicates: 0,
  valid_duplicates_emitted: 0,
  reorder_events: 0,
  reordered_valid_datagrams: 0,
  expected_detectable_loss: 0,
  invalid: 0,
  delayed_ms: options[:delay_ms],
  dry_run: options[:dry_run]
}

stopped = false
Signal.trap("INT") { stopped = true }
wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sensor_start_ns = (wall_start * 1_000_000_000).to_i
emitted_originals = 0
valid_sequences = controller_ids.to_h { |id| [id, {}] }
latest_valid_arrival = controller_ids.to_h { |id| [id, nil] }

emit_packet = lambda do |packet, controller_id, sequence|
  if rng.rand < options[:loss]
    summary[:lost] += 1
    next
  end
  emitted_originals += 1
  output = packet
  if options[:invalid_every].positive? && (emitted_originals % options[:invalid_every]).zero?
    output = packet.dup
    output.setbyte(2, 2)
    summary[:invalid] += 1
  end
  socket.send(output, 0, destination) unless options[:dry_run]
  summary[:datagrams_emitted] += 1
  valid = output.getbyte(2) == MotionPacket::VERSION
  if valid
    if latest_valid_arrival[controller_id] && sequence < latest_valid_arrival[controller_id]
      summary[:reordered_valid_datagrams] += 1
    end
    latest_valid_arrival[controller_id] = sequence if !latest_valid_arrival[controller_id] || sequence > latest_valid_arrival[controller_id]
    valid_sequences[controller_id][sequence] = true
  end
  if rng.rand < options[:duplicate]
    socket.send(output, 0, destination) unless options[:dry_run]
    summary[:datagrams_emitted] += 1
    summary[:duplicates] += 1
    summary[:valid_duplicates_emitted] += 1 if valid
  end
end

sample_count.times do |sample_index|
  break if stopped
  if options[:pace]
    target = wall_start + options[:delay_ms] / 1000.0 + sample_index.to_f / options[:rate]
    remaining = target - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sleep(remaining) if remaining.positive?
  end

  controller_ids.each do |controller_id|
    sequence = sequences.fetch(controller_id)
    sensor_ns = sensor_start_ns + sample_index * interval_ns
    packet = MotionPacket.encode(
      session_id: options[:session_id],
      controller_id: controller_id,
      sequence: sequence,
      sensor_ns: sensor_ns,
      sample_index: sample_index,
      rate: options[:rate]
    )
    sequences[controller_id] = (sequence + 1) & 0xFFFF_FFFF
    summary[:samples_generated] += 1
    rejection = MotionPacket.validate(packet)
    if rejection
      summary[:codec_rejections] += 1
      warn("internal packet rejected: #{rejection}")
      next
    end
    summary[:codec_validated] += 1

    if pending[controller_id]
      emit_packet.call(packet, controller_id, sequence)
      delayed = pending[controller_id]
      emit_packet.call(delayed.fetch(:packet), controller_id, delayed.fetch(:sequence))
      pending[controller_id] = nil
    elsif rng.rand < options[:reorder]
      pending[controller_id] = { packet: packet, sequence: sequence }
      summary[:reorder_events] += 1
    else
      emit_packet.call(packet, controller_id, sequence)
    end
  end
end

pending.each do |controller_id, delayed|
  emit_packet.call(delayed.fetch(:packet), controller_id, delayed.fetch(:sequence)) if delayed
end
socket.close if socket
valid_sequences.each_value do |sequences_for_controller|
  next if sequences_for_controller.empty?

  summary[:expected_detectable_loss] += sequences_for_controller.keys.max + 1 - sequences_for_controller.size
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_start
summary[:wall_elapsed_s] = elapsed.round(6)
summary[:generated_rate_hz_per_controller] =
  (summary[:samples_generated] / options[:controllers].to_f / elapsed).round(3)

puts "TMB_GENERATOR_SUMMARY #{JSON.generate(summary)}"
exit(summary[:codec_rejections].zero? ? 0 : 1)
