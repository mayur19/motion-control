extends SceneTree

const LoggerScript = preload("res://logging/session_logger.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	if output_path.is_empty():
		push_error("--output is required")
		quit(1)
		return

	var logger := LoggerScript.new()
	logger.maximum_bytes = 32 * 1024
	logger.flush_interval_ms = 25
	root.add_child(logger)
	var start_error := logger.start("sample-session", {"test": "TMB-012"}, output_path)
	if start_error != OK:
		push_error("Logger start failed: %s" % error_string(start_error))
		quit(1)
		return
	for sequence in 20:
		logger.log_packet({
			"endpoint": "127.0.0.1:50000",
			"arrival_monotonic_ns": 1_000_000_000 + sequence * 5_000_000,
			"packet_size": 80,
			"validation": "OK",
			"message_type": 5,
			"session_id": 72623859790382856,
			"controller_id": 168496141,
			"sequence": sequence,
			"sensor_monotonic_ns": 900_000_000 + sequence * 5_000_000,
		})
	logger.log_event("sample_complete", {"packets": 20})
	logger.flush()
	var records_written := logger.records_written()
	logger.close()

	var lines := FileAccess.get_file_as_string(output_path).split("\n", false)
	if lines.size() != records_written:
		push_error("Expected %d complete lines, got %d" % [records_written, lines.size()])
		quit(1)
		return
	for line in lines:
		if typeof(JSON.parse_string(line)) != TYPE_DICTIONARY:
			push_error("Invalid JSONL record")
			quit(1)
			return

	var bounded_path := output_path.get_basename() + "-bounded.jsonl"
	var bounded := LoggerScript.new()
	bounded.maximum_bytes = 2048
	root.add_child(bounded)
	if bounded.start("bounded-session", {}, bounded_path) != OK:
		push_error("Bounded logger could not start")
		quit(1)
		return
	for sequence in 1000:
		bounded.log_event("load", {"sequence": sequence, "padding": "x".repeat(80)})
		if bounded.reached_limit():
			break
	bounded.close()
	var bounded_size := FileAccess.get_file_as_bytes(bounded_path).size()
	if not bounded.reached_limit() or bounded_size > 2048:
		push_error("Log bound failed: size=%d" % bounded_size)
		quit(1)
		return

	var disabled_path := output_path.get_basename() + "-disabled.jsonl"
	var disabled := LoggerScript.new()
	disabled.enabled = false
	root.add_child(disabled)
	if disabled.start("disabled", {}, disabled_path) != OK or FileAccess.file_exists(disabled_path):
		push_error("Disabled logger created output")
		quit(1)
		return

	print("TMB-012_LOGGER_OK records=%d sample_bytes=%d bounded_bytes=%d" % [
		records_written,
		FileAccess.get_file_as_bytes(output_path).size(),
		bounded_size,
	])
	quit(0)
