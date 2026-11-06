extends SceneTree

const Codec = preload("res://protocol/protocol_v1.gd")
const Ingest = preload("res://network/motion_ingest.gd")
const LoggerScript = preload("res://logging/session_logger.gd")
const Clocks = preload("res://network/host_clock_service.gd")
const Connections = preload("res://network/connection_manager.gd")
const Telemetry = preload("res://logging/soak_telemetry.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	if output_path.is_empty():
		_fail("--output is required")
		return
	var ingest := Ingest.new()
	root.add_child(ingest)
	var logger := LoggerScript.new()
	logger.maximum_bytes = 64 * 1024
	root.add_child(logger)
	if logger.start("soak-test", {}, output_path) != OK:
		_fail("Could not start telemetry test logger")
		return
	var clocks := Clocks.new()
	root.add_child(clocks)
	var connections := Connections.new()
	root.add_child(connections)
	var telemetry := Telemetry.new()
	root.add_child(telemetry)
	telemetry.attach(ingest, clocks, connections, logger)

	var now := Time.get_ticks_usec() * 1000
	var packet := Codec.encode({
		"header": {"protocol_version": 1, "message_type": 5, "flags": 0, "session_id": 1, "controller_id": 7, "sequence": 0},
		"payload": {"message_type": 5, "sensor_monotonic_ns": now - 2_000_000, "acceleration": [0.0, 0.0, -9.8], "angular_velocity": [0.0, 1.0, 0.0], "orientation": [0.0, 0.0, 0.0, 1.0], "accuracy": 3, "sensor_flags": 7},
	})
	ingest._process_packet(packet.data, "127.0.0.1:50000", now, "127.0.0.1", 50000)
	telemetry._process(1.0)
	logger.close()

	var found := false
	for line in FileAccess.get_file_as_string(output_path).split("\n", false):
		var record = JSON.parse_string(line)
		if typeof(record) == TYPE_DICTIONARY and record.get("event", "") == "soak_metrics":
			found = (
				int(record.controller_id) == 7
				and float(record.received_motion_hz) == 1.0
				and record.has("host_frame_ms")
				and record.has("sample_age_ms")
				and record.has("host_static_memory_bytes")
				and record.host_frame_ms.has("p99")
				and record.sample_age_ms.has("p99")
			)
	if not found:
		_fail("Complete soak_metrics event was not written")
		return
	var hundred := []
	for value in range(1, 101):
		hundred.append(value)
	var summary: Dictionary = telemetry._summary(hundred)
	if float(summary.p99) != 99.0 or float(summary.p95) != 95.0 or float(summary.maximum) != 100.0:
		_fail("Frame/age summary percentiles wrong: %s" % str(summary))
		return
	print("TMB-022_SOAK_TELEMETRY_OK interval_s=1 controller=7 received_hz=1 bounded=true p99=true")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
