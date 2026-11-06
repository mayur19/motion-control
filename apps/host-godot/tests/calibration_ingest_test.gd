extends SceneTree

const Codec = preload("res://protocol/protocol_v1.gd")
const Ingest = preload("res://network/motion_ingest.gd")
const LoggerScript = preload("res://logging/session_logger.gd")
const ConnectionManagerScript = preload("res://network/connection_manager.gd")


class FakeSessions:
	extends RefCounted
	var current_session := {"session_id": 1}

var _calibration_events := 0
var _sample: Dictionary = {}
var _normalized_samples: Array[Dictionary] = []
var _calibration_states: Array[String] = []


func _initialize() -> void:
	var ingest := Ingest.new()
	root.add_child(ingest)
	var sessions := FakeSessions.new()
	ingest.set_session_manager(sessions)
	var connections := ConnectionManagerScript.new()
	root.add_child(connections)
	connections.set_process(false)
	connections._on_pairing_event({
		"state": 1, "controller_id": 7, "player": 1,
		"endpoint": "192.0.2.1:7000", "source_ip": "192.0.2.1",
	})
	connections._set_state(7, "Connected", "test", true)
	ingest.set_connection_manager(connections)
	ingest.calibration_received.connect(func(_id: int, _value: Dictionary): _calibration_events += 1)
	ingest.sample_received.connect(func(value: Dictionary): _sample = value)
	ingest.normalized_sample_received.connect(func(value: Dictionary): _normalized_samples.append(value))
	ingest.calibration_state_changed.connect(
		func(_id: int, state: String, _reason: String): _calibration_states.append(state)
	)
	var log_path := _output_path()
	var logger := LoggerScript.new()
	logger.flush_interval_ms = 25
	logger.log_normalized_samples = true
	root.add_child(logger)
	if logger.start("calibration-session", {"test": "TMB-027"}, log_path) != OK:
		_fail("Logger start failed")
		return
	logger.attach(ingest)

	var early := _packet(Codec.TYPE_MOTION, 0, _motion_payload(900_000_000))
	ingest._process_packet(early.data, "192.0.2.1:7000", 1_900_000_000)
	if _sample.is_empty() or _sample.has("normalized") or not _normalized_samples.is_empty():
		_fail("Uncalibrated motion must stay raw and never reach the detector stream")
		return
	if str(_sample.get("calibration_state", "")) != "uncalibrated":
		_fail("Uncalibrated sample state missing: %s" % str(_sample))
		return

	var spoofed := _packet(Codec.TYPE_CALIBRATION, 9, _calibration_payload())
	ingest._process_packet(spoofed.data, "198.51.100.9:7000", 1_950_000_000)
	if _calibration_events != 0 or not _calibration_states.is_empty():
		_fail("CALIBRATION from an unpaired endpoint must be ignored")
		return

	var calibration := _packet(Codec.TYPE_CALIBRATION, 1, {
		"message_type": Codec.TYPE_CALIBRATION,
		"sensor_monotonic_ns": 1_000_000_000,
		"neutral_orientation": [0.0, 0.0, 0.0, 1.0],
		"acceleration_bias": [0.1, 0.2, 0.3],
		"gyroscope_bias": [0.01, 0.02, 0.03],
		"quality": 0.9,
		"result": 1,
		"handedness": 2,
	})
	if not calibration.ok:
		_fail("Could not encode calibration: %s" % calibration.error)
		return
	ingest._process_packet(calibration.data, "192.0.2.1:7000", 2_000_000_000)
	if _calibration_events != 1:
		_fail("Calibration was not retained and emitted")
		return

	if _calibration_states != ["calibrated"]:
		_fail("Calibration state change missing: %s" % str(_calibration_states))
		return

	var motion := _packet(Codec.TYPE_MOTION, 2, _motion_payload(1_100_000_000))
	if not motion.ok:
		_fail("Could not encode motion: %s" % motion.error)
		return
	ingest._process_packet(motion.data, "192.0.2.1:7000", 2_100_000_000)
	if _normalized_samples.size() != 1 or _normalized_samples[0] != _sample:
		_fail("Calibrated motion must reach the detector stream exactly once")
		return
	if str(_sample.get("calibration_state", "")) != "normalized":
		_fail("Normalized sample state missing: %s" % str(_sample))
		return
	if not _near(_sample.acceleration, [-1.9, 3.2, -3.7]) or not _near(_sample.angular_velocity, [-0.99, 2.02, -2.97]):
		_fail("Raw axes must stay unchanged: %s" % str(_sample))
		return
	if not _near(_sample.normalized.acceleration, [2.0, 3.0, 4.0]):
		_fail("Left-hand acceleration normalization differed: %s" % str(_sample.normalized))
		return
	if not _near(_sample.normalized.angular_velocity, [1.0, 2.0, 3.0]):
		_fail("Left-hand angular velocity normalization differed: %s" % str(_sample.normalized))
		return

	logger.close()
	var logged := _calibration_event(log_path)
	if logged.is_empty():
		_fail("Session log has no calibration event")
		return
	if (
		int(logged.get("controller_id", 0)) != 7
		or str(logged.get("handedness", "")) != "left"
		or not _near(logged.get("neutral_orientation", []), [0.0, 0.0, 0.0, 1.0])
		or not _near(logged.get("acceleration_bias", []), [0.1, 0.2, 0.3])
		or not _near(logged.get("gyroscope_bias", []), [0.01, 0.02, 0.03])
		or absf(float(logged.get("quality", 0.0)) - 0.9) > 0.0001
	):
		_fail("Calibration event fields differed: %s" % str(logged))
		return

	var records := _records(log_path)
	var states := records.filter(func(r: Dictionary) -> bool: return r.get("event", "") == "calibration_state")
	if states.size() != 1 or str(states[0].get("state", "")) != "calibrated" or int(states[0].get("controller_id", 0)) != 7:
		_fail("calibration_state event missing: %s" % str(states))
		return
	var normalized_records := records.filter(
		func(r: Dictionary) -> bool: return r.get("record_type", "") == "normalized_sample"
	)
	if normalized_records.size() != 1:
		_fail("Expected one normalized_sample record, got %d" % normalized_records.size())
		return
	var record: Dictionary = normalized_records[0]
	if not _near(record.get("raw_acceleration", []), [-1.9, 3.2, -3.7]) \
			or not _near(record.get("normalized_acceleration", []), [2.0, 3.0, 4.0]) \
			or not _near(record.get("normalized_angular_velocity", []), [1.0, 2.0, 3.0]) \
			or int(record.get("sequence", -1)) != 2:
		_fail("normalized_sample fields differ: %s" % str(record))
		return
	for packet_record in records.filter(func(r: Dictionary) -> bool: return r.get("record_type", "") == "packet"):
		if packet_record.has("normalized") or packet_record.has("normalized_acceleration"):
			_fail("Packet records must stay raw-only: %s" % str(packet_record))
			return

	sessions.current_session = {"session_id": 2}
	_sample = {}
	var after_rotation := _packet(Codec.TYPE_MOTION, 3, _motion_payload(1_200_000_000))
	ingest._process_packet(after_rotation.data, "192.0.2.1:7000", 2_200_000_000)
	if _normalized_samples.size() != 1 or str(_sample.get("calibration_state", "")) != "uncalibrated":
		_fail("Old-session motion must not be normalized after session rotation: %s" % str(_sample))
		return

	print("TMB-028_NORMALIZED_LOG_OK packet_records_unchanged=true")
	print("TMB-027_CALIBRATION_INGEST_OK handedness=left common_frame=true logged=true raw_separate=true")
	quit(0)


func _packet(message_type: int, sequence: int, payload: Dictionary) -> Dictionary:
	return Codec.encode({
		"header": {
			"protocol_version": Codec.VERSION,
			"message_type": message_type,
			"flags": 0,
			"session_id": 1,
			"controller_id": 7,
			"sequence": sequence,
		},
		"payload": payload,
	})


func _calibration_payload() -> Dictionary:
	return {
		"message_type": Codec.TYPE_CALIBRATION,
		"sensor_monotonic_ns": 1_000_000_000,
		"neutral_orientation": [0.0, 0.0, 0.0, 1.0],
		"acceleration_bias": [0.0, 0.0, 0.0],
		"gyroscope_bias": [0.0, 0.0, 0.0],
		"quality": 0.9,
		"result": 1,
		"handedness": 1,
	}


func _motion_payload(sensor_ns: int) -> Dictionary:
	return {
		"message_type": Codec.TYPE_MOTION,
		"sensor_monotonic_ns": sensor_ns,
		"acceleration": [-1.9, 3.2, -3.7],
		"angular_velocity": [-0.99, 2.02, -2.97],
		"orientation": [0.0, 0.0, 0.0, 1.0],
		"accuracy": 3,
		"sensor_flags": 7,
	}


func _output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return OS.get_user_data_dir().path_join("calibration_ingest_test.jsonl")


func _records(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			result.append(parsed)
	return result


func _calibration_event(path: String) -> Dictionary:
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var record: Variant = JSON.parse_string(line)
		if typeof(record) == TYPE_DICTIONARY and record.get("event", "") == "calibration":
			return record
	return {}


func _near(actual: Variant, expected: Array) -> bool:
	if typeof(actual) != TYPE_ARRAY or actual.size() != expected.size():
		return false
	for index in expected.size():
		if absf(float(actual[index]) - float(expected[index])) > 0.0001:
			return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
