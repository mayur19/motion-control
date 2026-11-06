#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

ROOT = File.expand_path(__dir__)
SESSION_ID = 0x0102_0304_0506_0708
CONTROLLER_ID = 0x0A0B_0C0D
HEADER_SIZE = 28

MESSAGE_TYPES = {
  hello: 1,
  welcome: 2,
  ping: 3,
  pong: 4,
  motion: 5,
  calibration: 6,
  status: 7,
  goodbye: 8
}.freeze

def header(type:, payload_size:, sequence:, controller_id: CONTROLLER_ID, flags: 0)
  [
    0x4D42,
    1,
    MESSAGE_TYPES.fetch(type),
    flags,
    HEADER_SIZE,
    payload_size,
    0,
    SESSION_ID,
    controller_id,
    sequence
  ].pack("nCCnnnnQ>NN")
end

def packet(type:, payload:, sequence:, controller_id: CONTROLLER_ID, flags: 0)
  header(
    type: type,
    payload_size: payload.bytesize,
    sequence: sequence,
    controller_id: controller_id,
    flags: flags
  ) + payload
end

def floats(*values)
  values.map { |value| value.zero? ? 0.0 : value }.pack("g*")
end

pairing_secret = ["00112233445566778899aabbccddeeff"].pack("H*")
device_model = "iPhone 17e"
app_version = "0.1.0"
os_version = "iOS 26.4"
hello_payload = [
  pairing_secret,
  1,
  0,
  0x000F,
  200,
  device_model.bytesize,
  app_version.bytesize,
  os_version.bytesize
].pack("a16CCnnCCC") + "\x00\x00\x00" + device_model + app_version + os_version

welcome_payload = [1, 1, 500, 2000, 8, 9_876_543_210, 1_800_000_000].pack("CCnnnQ>Q>")
ping_payload = [7, 0, 1_000_000_000].pack("NNQ>")
pong_payload = [7, 0, 1_000_000_000, 2_000_000_000, 2_001_000_000].pack("NNQ>Q>Q>")
motion_payload = [123_456_789].pack("Q>") +
  floats(1.0, 0.0, -9.80665, 0.1, -0.2, 3.5, 0.0, 0.0, 0.0, 1.0) +
  [3, 7, 0].pack("CCn")
calibration_payload = [123_500_000].pack("Q>") +
  floats(0.0, 0.0, 0.0, 1.0, 0.1, -0.1, 0.05, 0.01, -0.02, 0.03, 0.95) +
  [1, 1].pack("CC") + "\x00\x00"
status_payload = [999_000_000, 85, 2, 0, 0, 200, 0, 42].pack("Q>CCCCnnN")
goodbye_payload = [1].pack("C") + "\x00\x00\x00" + [99, 123_999_999].pack("NQ>")

positive = {
  "hello.bin" => {
    bytes: packet(type: :hello, payload: hello_payload, sequence: 1, controller_id: 0, flags: 1),
    type: :hello,
    sequence: 1,
    controller_id: 0,
    flags: 1,
    payload: {
      pairing_secret_hex: pairing_secret.unpack1("H*"),
      platform: 1,
      capabilities: 15,
      max_sample_hz: 200,
      device_model: device_model,
      app_version: app_version,
      os_version: os_version
    }
  },
  "welcome.bin" => {
    bytes: packet(type: :welcome, payload: welcome_payload, sequence: 2),
    type: :welcome,
    sequence: 2,
    controller_id: CONTROLLER_ID,
    flags: 0,
    payload: {
      player: 1,
      session_state: 1,
      heartbeat_interval_ms: 500,
      disconnect_timeout_ms: 2000,
      reorder_window_packets: 8,
      host_monotonic_ns: "9876543210",
      session_expires_unix_s: "1800000000"
    }
  },
  "ping.bin" => {
    bytes: packet(type: :ping, payload: ping_payload, sequence: 3, flags: 1),
    type: :ping,
    sequence: 3,
    controller_id: CONTROLLER_ID,
    flags: 1,
    payload: { ping_id: 7, sender_monotonic_ns: "1000000000" }
  },
  "pong.bin" => {
    bytes: packet(type: :pong, payload: pong_payload, sequence: 4),
    type: :pong,
    sequence: 4,
    controller_id: CONTROLLER_ID,
    flags: 0,
    payload: {
      ping_id: 7,
      echo_sender_monotonic_ns: "1000000000",
      receiver_receive_monotonic_ns: "2000000000",
      receiver_send_monotonic_ns: "2001000000"
    }
  },
  "motion.bin" => {
    bytes: packet(type: :motion, payload: motion_payload, sequence: 42),
    type: :motion,
    sequence: 42,
    controller_id: CONTROLLER_ID,
    flags: 0,
    payload: {
      sensor_monotonic_ns: "123456789",
      acceleration_m_s2: [1.0, 0.0, -9.80665],
      angular_velocity_rad_s: [0.1, -0.2, 3.5],
      orientation_xyzw: [0.0, 0.0, 0.0, 1.0],
      accuracy: 3,
      sensor_flags: 7
    }
  },
  "calibration.bin" => {
    bytes: packet(type: :calibration, payload: calibration_payload, sequence: 43),
    type: :calibration,
    sequence: 43,
    controller_id: CONTROLLER_ID,
    flags: 0,
    payload: {
      sensor_monotonic_ns: "123500000",
      neutral_orientation_xyzw: [0.0, 0.0, 0.0, 1.0],
      accel_bias_xyz: [0.1, -0.1, 0.05],
      gyro_bias_xyz: [0.01, -0.02, 0.03],
      quality: 0.95,
      result: 1,
      handedness: 1
    }
  },
  "status.bin" => {
    bytes: packet(type: :status, payload: status_payload, sequence: 44),
    type: :status,
    sequence: 44,
    controller_id: CONTROLLER_ID,
    flags: 0,
    payload: {
      sender_monotonic_ns: "999000000",
      battery_percent: 85,
      sensor_state: 2,
      app_state: 0,
      pause_reason: 0,
      actual_sample_hz: 200,
      last_motion_sequence: 42
    }
  },
  "goodbye.bin" => {
    bytes: packet(type: :goodbye, payload: goodbye_payload, sequence: 45),
    type: :goodbye,
    sequence: 45,
    controller_id: CONTROLLER_ID,
    flags: 0,
    payload: {
      reason: 1,
      last_sequence: 99,
      sender_monotonic_ns: "123999999"
    }
  }
}.freeze

motion = positive.fetch("motion.bin").fetch(:bytes)
status = positive.fetch("status.bin").fetch(:bytes)

wrong_version = motion.dup.tap { |bytes| bytes.setbyte(2, 2) }
invalid_enum = status.dup.tap { |bytes| bytes.setbyte(HEADER_SIZE + 9, 9) }
invalid_length = motion.dup.tap do |bytes|
  bytes.setbyte(8, 0)
  bytes.setbyte(9, 51)
end
non_finite = motion.dup.tap do |bytes|
  bytes[HEADER_SIZE + 8, 4] = [0x7FC0_0000].pack("N")
end
invalid_quaternion = motion.dup.tap do |bytes|
  bytes[HEADER_SIZE + 32, 16] = "\x00" * 16
end
nonzero_reserved = motion.dup.tap { |bytes| bytes.setbyte(11, 1) }

negative = {
  "truncated-header.bin" => { bytes: motion.byteslice(0, 20), rejection: "TOO_SHORT" },
  "wrong-version.bin" => { bytes: wrong_version, rejection: "UNSUPPORTED_VERSION" },
  "invalid-enum.bin" => { bytes: invalid_enum, rejection: "INVALID_ENUM" },
  "invalid-length.bin" => { bytes: invalid_length, rejection: "INVALID_PAYLOAD_LENGTH" },
  "non-finite-float.bin" => { bytes: non_finite, rejection: "NON_FINITE_FLOAT" },
  "invalid-quaternion.bin" => { bytes: invalid_quaternion, rejection: "INVALID_QUATERNION" },
  "nonzero-reserved.bin" => { bytes: nonzero_reserved, rejection: "NONZERO_RESERVED" }
}.freeze

def sha256(bytes)
  Digest::SHA256.hexdigest(bytes)
end

manifest = {
  manifest_version: 1,
  protocol_version: 1,
  byte_order: "big-endian",
  header_size: HEADER_SIZE,
  maximum_datagram_size: 256,
  float_tolerance: 0.00001,
  session_id_hex: format("%016x", SESSION_ID),
  positives: positive.map do |filename, fixture|
    {
      file: "positive/#{filename}",
      sha256: sha256(fixture.fetch(:bytes)),
      message_type: MESSAGE_TYPES.fetch(fixture.fetch(:type)),
      message_name: fixture.fetch(:type).to_s.upcase,
      expected: {
        header: {
          protocol_version: 1,
          flags: fixture.fetch(:flags),
          session_id_hex: format("%016x", SESSION_ID),
          controller_id: fixture.fetch(:controller_id),
          sequence: fixture.fetch(:sequence)
        },
        payload: fixture.fetch(:payload)
      }
    }
  end,
  negatives: negative.map do |filename, fixture|
    {
      file: "negative/#{filename}",
      sha256: sha256(fixture.fetch(:bytes)),
      expected_rejection: fixture.fetch(:rejection)
    }
  end
}

expected_files = {}
positive.each { |filename, fixture| expected_files["positive/#{filename}"] = fixture.fetch(:bytes) }
negative.each { |filename, fixture| expected_files["negative/#{filename}"] = fixture.fetch(:bytes) }
expected_files["manifest.json"] = JSON.pretty_generate(manifest) + "\n"

if ARGV.include?("--check")
  failures = expected_files.each_with_object([]) do |(relative_path, expected), result|
    actual_path = File.join(ROOT, relative_path)
    unless File.file?(actual_path)
      result << "missing #{relative_path}"
      next
    end
    next if File.binread(actual_path) == expected

    result << "changed #{relative_path}"
  end
  abort("Fixture check failed: #{failures.join(', ')}") unless failures.empty?
  puts "TMB-008_FIXTURES_OK positives=#{positive.size} negatives=#{negative.size}"
else
  expected_files.each do |relative_path, contents|
    output_path = File.join(ROOT, relative_path)
    FileUtils.mkdir_p(File.dirname(output_path))
    File.binwrite(output_path, contents)
  end
  puts "Generated #{positive.size} positive and #{negative.size} negative fixtures"
end
