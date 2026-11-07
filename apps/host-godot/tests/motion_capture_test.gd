extends SceneTree

const Capture = preload("res://capture/motion_capture.gd")


func _initialize() -> void:
	var root_dir := _output_root()
	var capture := Capture.new()
	var started := capture.start(root_dir, {"operator_note": "fixture"})
	if started != OK or capture.capture_id().is_empty():
		return _fail("Capture did not start: %s" % error_string(started))
	if not capture.capture_id().begins_with("cap_") or not capture.capture_id().is_valid_filename():
		return _fail("Unexpected capture id: %s" % capture.capture_id())

	var bad := capture.begin_take({"player": 3, "phone": "iPhone", "handedness": "right",
		"intended_shot": "smash", "valid": true}, 1_000)
	if bool(bad.ok):
		return _fail("Invalid player label was accepted")

	var bad_count := capture.begin_take({"player": 1, "phone": "iPhone", "handedness": "right",
		"intended_shot": "smash", "valid": true, "speed": "warp", "swing_count": 7}, 1_000)
	if bool(bad_count.ok):
		return _fail("Invalid speed label was accepted")
	var take := capture.begin_take({"player": 1, "phone": "iPhone", "handedness": "right",
		"intended_shot": "smash", "valid": true, "speed": "normal", "swing_count": 7}, 1_000)
	if not bool(take.ok):
		return _fail("Valid take rejected: %s" % str(take))
	for index in 3:
		capture.record_datagram(PackedByteArray([1, 2, 3, index]), "192.0.2.1:5000", 2_000 + index)
	var ended := capture.end_take(5_000, {"player": 1, "phone": "iPhone", "handedness": "right",
		"intended_shot": "smash", "valid": true, "speed": "fast", "swing_count": 8})
	if not bool(ended.ok) or int(ended.take_id) != int(take.take_id):
		return _fail("Take did not end: %s" % str(ended))
	capture.begin_take({"player": 2, "phone": "Galaxy", "handedness": "left",
		"intended_shot": "idle", "valid": false}, 6_000)
	var stopped := capture.stop(7_000)
	if not bool(stopped.ok):
		return _fail("Capture did not stop: %s" % str(stopped))

	var directory: String = stopped.directory
	var raw_lines := FileAccess.get_file_as_string(directory.path_join("raw.jsonl")).split("\n", false)
	var header: Dictionary = JSON.parse_string(raw_lines[0])
	if str(header.record) != "capture_header" or int(header.capture_format) != Capture.FORMAT_VERSION:
		return _fail("Bad raw header: %s" % str(header))
	if raw_lines.size() != 4:
		return _fail("Expected header + 3 datagrams, got %d lines" % raw_lines.size())
	var datagram: Dictionary = JSON.parse_string(raw_lines[3])
	if Marshalls.base64_to_raw(str(datagram.bytes_b64)) != PackedByteArray([1, 2, 3, 2]) \
			or int(datagram.arrival_monotonic_ns) != 2_002:
		return _fail("Datagram not stored byte-exact: %s" % str(datagram))
	if raw_lines[0].contains("label") or FileAccess.get_file_as_string(directory.path_join("raw.jsonl")).contains("smash"):
		return _fail("Labels leaked into the raw motion file")

	var checksum := FileAccess.get_file_as_string(directory.path_join("raw.sha256")).strip_edges()
	var expected := FileAccess.get_sha256(directory.path_join("raw.jsonl"))
	if checksum != "%s  raw.jsonl" % expected or str(stopped.raw_sha256) != expected:
		return _fail("Checksum sidecar mismatch: %s vs %s" % [checksum, expected])

	var labels := FileAccess.get_file_as_string(directory.path_join("labels.jsonl")).split("\n", false)
	if labels.size() != 3:
		return _fail("Expected labels header + 2 takes, got %d" % labels.size())
	var first: Dictionary = JSON.parse_string(labels[1])
	var second: Dictionary = JSON.parse_string(labels[2])
	if str(first.speed) != "fast" or int(first.swing_count) != 8 or str(second.speed) != "none" \
			or int(second.swing_count) != 0:
		return _fail("End-time speed/swing_count labels wrong: %s / %s" % [str(first), str(second)])
	if str(first.record) != "take" or int(first.revision) != 1 or str(first.intended_shot) != "smash" \
			or int(first.start_arrival_ns) != 1_000 or int(first.end_arrival_ns) != 5_000:
		return _fail("First take label wrong: %s" % str(first))
	if bool(second.valid) or int(second.end_arrival_ns) != 7_000 or str(second.handedness) != "left":
		return _fail("Open take must close at stop: %s" % str(second))

	capture.record_datagram(PackedByteArray([9]), "192.0.2.1:5000", 8_000)
	if FileAccess.get_sha256(directory.path_join("raw.jsonl")) != expected:
		return _fail("Raw file changed after stop")

	print("TMB-029_CAPTURE_OK datagrams=3 takes=2 checksum=true labels_separate=true")
	quit(0)


func _output_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=").get_base_dir().path_join("captures-test")
	return OS.get_user_data_dir().path_join("captures-test")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
