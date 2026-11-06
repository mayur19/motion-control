class_name MotionIngest
extends Node

signal metrics_updated(controller_id: int, metrics: Dictionary)
signal packet_rejected(reason: String)
signal packet_observed(record: Dictionary)
signal sample_received(sample: Dictionary)
signal message_received(message: Dictionary, source_ip: String, source_port: int, arrival_ns: int)

const Codec = preload("res://protocol/protocol_v1.gd")
const MAX_PACKETS_PER_FRAME := 512
const MAX_POLL_MICROSECONDS := 2000
const RECENT_SEQUENCE_CAPACITY := 512

@export var queue_capacity := 4096

var _udp := PacketPeerUDP.new()
var _bound_port := 0
var _sample_queue: Array[Dictionary] = []
var _controller_metrics: Dictionary = {}
var _rejections: Dictionary = {}
var _queue_drops := 0
var _packets_processed := 0
var _max_poll_microseconds := 0
var _clock_service: HostClockService
var _connection_manager: ControllerConnectionManager
var _paused_motion_packets := 0


func start(port: int, bind_address := "0.0.0.0") -> Error:
	if _bound_port != 0:
		stop()
	var result := _udp.bind(port, bind_address)
	if result == OK:
		_bound_port = port
		set_process(true)
	return result


func stop() -> void:
	set_process(false)
	_udp.close()
	_bound_port = 0


func is_running() -> bool:
	return _bound_port != 0


func set_clock_service(clock_service: HostClockService) -> void:
	_clock_service = clock_service


func set_connection_manager(connection_manager: ControllerConnectionManager) -> void:
	_connection_manager = connection_manager


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	poll_packets()


func poll_packets() -> int:
	if not is_running():
		return 0
	var started := Time.get_ticks_usec()
	var processed := 0
	while (
		_udp.get_available_packet_count() > 0
		and processed < MAX_PACKETS_PER_FRAME
		and Time.get_ticks_usec() - started < MAX_POLL_MICROSECONDS
	):
		var packet := _udp.get_packet()
		var source_ip := _udp.get_packet_ip()
		var source_port := _udp.get_packet_port()
		var endpoint := "%s:%d" % [source_ip, source_port]
		_process_packet(packet, endpoint, Time.get_ticks_usec() * 1000, source_ip, source_port)
		processed += 1
	var elapsed := Time.get_ticks_usec() - started
	_max_poll_microseconds = maxi(_max_poll_microseconds, elapsed)
	_packets_processed += processed
	return processed


func pop_samples(max_count := 256) -> Array[Dictionary]:
	var count := mini(maxi(max_count, 0), _sample_queue.size())
	var result: Array[Dictionary] = []
	for index in count:
		result.append(_sample_queue[index])
	if count > 0:
		_sample_queue = _sample_queue.slice(count)
	return result


func snapshot() -> Dictionary:
	var controllers := {}
	var now_ms := Time.get_ticks_usec() / 1000.0
	for controller_id in _controller_metrics:
		var internal: Dictionary = _controller_metrics[controller_id]
		controllers[controller_id] = {
			"endpoint": internal.endpoint,
			"received": internal.received,
			"packet_hz": _recent_rate(internal.arrival_times_ms, now_ms),
			"loss": int(internal.prior_loss) + internal.missing.size(),
			"duplicates": internal.duplicates,
			"reordered": internal.reordered,
			"jitter_ms": internal.jitter_ms,
			"last_packet_age_ms": (
				(Time.get_ticks_usec() * 1000 - internal.last_arrival_ns) / 1_000_000.0
			),
			"latest_sequence": internal.newest_sequence,
		}
	return {
		"port": _bound_port,
		"controllers": controllers,
		"rejections": _rejections.duplicate(true),
		"queue_size": _sample_queue.size(),
		"queue_capacity": queue_capacity,
		"queue_drops": _queue_drops,
		"packets_processed": _packets_processed,
		"max_poll_microseconds": _max_poll_microseconds,
		"paused_motion_packets": _paused_motion_packets,
	}


func send_to(packet: PackedByteArray, destination_ip: String, destination_port: int) -> Error:
	if not is_running():
		return ERR_UNCONFIGURED
	var destination_error := _udp.set_dest_address(destination_ip, destination_port)
	if destination_error != OK:
		return destination_error
	return _udp.put_packet(packet)


func _process_packet(
	packet: PackedByteArray,
	endpoint: String,
	arrival_ns: int,
	source_ip := "",
	source_port := 0
) -> void:
	var decoded := Codec.decode(packet)
	if not decoded.ok:
		var reason: String = decoded.error
		_rejections[reason] = int(_rejections.get(reason, 0)) + 1
		packet_observed.emit({
			"endpoint": endpoint,
			"arrival_monotonic_ns": arrival_ns,
			"packet_size": packet.size(),
			"validation": reason,
		})
		packet_rejected.emit(reason)
		return
	packet_observed.emit({
		"endpoint": endpoint,
		"arrival_monotonic_ns": arrival_ns,
		"packet_size": packet.size(),
		"validation": "OK",
		"message_type": decoded.header.message_type,
		"session_id": decoded.header.session_id,
		"controller_id": decoded.header.controller_id,
		"sequence": decoded.header.sequence,
		"sensor_monotonic_ns": decoded.payload.get("sensor_monotonic_ns", 0),
	})
	message_received.emit(decoded, source_ip, source_port, arrival_ns)
	if decoded.header.message_type != Codec.TYPE_MOTION:
		return

	var controller_id: int = decoded.header.controller_id
	if (
		_connection_manager != null
		and not _connection_manager.should_accept_motion(controller_id, endpoint)
	):
		_paused_motion_packets += 1
		return
	var metrics := _metrics_for(controller_id, endpoint)
	if int(metrics.received) > 0 and str(metrics.endpoint) != endpoint:
		_begin_new_stream(metrics)
	_update_sequence(metrics, int(decoded.header.sequence))
	_update_timing(metrics, arrival_ns)
	metrics.received += 1
	metrics.endpoint = endpoint

	if _sample_queue.size() >= queue_capacity:
		_sample_queue.pop_front()
		_queue_drops += 1
	var sample: Dictionary = {
		"controller_id": controller_id,
		"sequence": decoded.header.sequence,
		"session_id": decoded.header.session_id,
		"endpoint": endpoint,
		"arrival_monotonic_ns": arrival_ns,
		"sensor_monotonic_ns": decoded.payload.sensor_monotonic_ns,
		"acceleration": decoded.payload.acceleration,
		"angular_velocity": decoded.payload.angular_velocity,
		"orientation": decoded.payload.orientation,
		"accuracy": decoded.payload.accuracy,
		"sensor_flags": decoded.payload.sensor_flags,
		"packet_size": packet.size(),
	}
	if _clock_service != null:
		var adjusted := _clock_service.controller_to_host(controller_id, int(decoded.payload.sensor_monotonic_ns))
		sample["clock_synchronized"] = bool(adjusted.initialized)
		sample["adjusted_host_monotonic_ns"] = int(adjusted.host_ns)
		sample["adjusted_sample_age_ms"] = (
			maxf(0.0, (arrival_ns - int(adjusted.host_ns)) / 1_000_000.0)
			if adjusted.initialized
			else -1.0
		)
	_sample_queue.append(sample)
	sample_received.emit(sample)
	metrics_updated.emit(controller_id, _public_metrics(metrics))


func _metrics_for(controller_id: int, endpoint: String) -> Dictionary:
	if not _controller_metrics.has(controller_id):
		_controller_metrics[controller_id] = {
			"endpoint": endpoint,
			"received": 0,
			"newest_sequence": -1,
			"seen": {},
			"seen_order": [],
			"missing": {},
			"prior_loss": 0,
			"duplicates": 0,
			"reordered": 0,
			"arrival_times_ms": [],
			"last_arrival_ns": 0,
			"last_interval_ms": 0.0,
			"jitter_ms": 0.0,
		}
	return _controller_metrics[controller_id]


## A reconnecting controller keeps its ID but opens a new motion socket whose
## sender-local sequence may start anywhere (protocol section 3). The
## connection manager only admits the newly pinned endpoint, so an endpoint
## change marks a new stream: restart the sequence window and timing, and fold
## the previous stream's loss into the cumulative total.
func _begin_new_stream(metrics: Dictionary) -> void:
	metrics.prior_loss = int(metrics.prior_loss) + metrics.missing.size()
	metrics.missing = {}
	metrics.seen = {}
	metrics.seen_order = []
	metrics.newest_sequence = -1
	metrics.counts_leading_gap = false
	metrics.last_arrival_ns = 0
	metrics.last_interval_ms = 0.0


func _update_sequence(metrics: Dictionary, sequence: int) -> void:
	if metrics.seen.has(sequence):
		metrics.duplicates += 1
		return
	metrics.seen[sequence] = true
	metrics.seen_order.append(sequence)
	if metrics.seen_order.size() > RECENT_SEQUENCE_CAPACITY:
		var expired = metrics.seen_order.pop_front()
		metrics.seen.erase(expired)

	if metrics.newest_sequence < 0:
		if bool(metrics.get("counts_leading_gap", true)):
			for missing_sequence in sequence:
				metrics.missing[missing_sequence] = true
		metrics.newest_sequence = sequence
		return
	if _sequence_is_newer(sequence, metrics.newest_sequence):
		var delta := (sequence - int(metrics.newest_sequence)) & 0xFFFF_FFFF
		if delta <= 4096:
			for offset in range(1, delta):
				metrics.missing[(int(metrics.newest_sequence) + offset) & 0xFFFF_FFFF] = true
		metrics.newest_sequence = sequence
	elif metrics.missing.has(sequence):
		metrics.missing.erase(sequence)
		metrics.reordered += 1
	else:
		metrics.reordered += 1


func _update_timing(metrics: Dictionary, arrival_ns: int) -> void:
	var arrival_ms := arrival_ns / 1_000_000.0
	var times: Array = metrics.arrival_times_ms
	times.append(arrival_ms)
	while not times.is_empty() and arrival_ms - float(times[0]) > 1000.0:
		times.pop_front()
	if metrics.last_arrival_ns > 0:
		var interval_ms := (arrival_ns - int(metrics.last_arrival_ns)) / 1_000_000.0
		if metrics.last_interval_ms > 0.0:
			var deviation: float = absf(interval_ms - float(metrics.last_interval_ms))
			metrics.jitter_ms += (deviation - float(metrics.jitter_ms)) / 16.0
		metrics.last_interval_ms = interval_ms
	metrics.last_arrival_ns = arrival_ns


func _public_metrics(metrics: Dictionary) -> Dictionary:
	return {
		"endpoint": metrics.endpoint,
		"received": metrics.received,
		"packet_hz": metrics.arrival_times_ms.size(),
		"loss": int(metrics.prior_loss) + metrics.missing.size(),
		"duplicates": metrics.duplicates,
		"reordered": metrics.reordered,
		"jitter_ms": metrics.jitter_ms,
	}


func _recent_rate(arrival_times_ms: Array, now_ms: float) -> int:
	var count := 0
	for index in range(arrival_times_ms.size() - 1, -1, -1):
		if now_ms - float(arrival_times_ms[index]) > 1000.0:
			break
		count += 1
	return count


func _sequence_is_newer(candidate: int, reference: int) -> bool:
	var delta := (candidate - reference) & 0xFFFF_FFFF
	return delta > 0 and delta < 0x8000_0000
