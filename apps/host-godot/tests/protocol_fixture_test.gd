extends SceneTree

const Codec = preload("res://protocol/protocol_v1.gd")


func _initialize() -> void:
	var fixture_root := ProjectSettings.globalize_path("res://../../protocol/golden-vectors")
	var manifest_path := fixture_root.path_join("manifest.json")
	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var manifest = JSON.parse_string(manifest_text)
	if typeof(manifest) != TYPE_DICTIONARY:
		_fail("Could not parse fixture manifest")
		return

	var decoded_types := {}
	for fixture in manifest.positives:
		var relative_path: String = fixture.file
		var bytes := FileAccess.get_file_as_bytes(fixture_root.path_join(relative_path))
		var decoded := Codec.decode(bytes)
		if not decoded.ok:
			_fail("%s rejected with %s" % [relative_path, decoded.error])
			return
		if decoded.header.message_type != int(fixture.message_type):
			_fail("%s decoded wrong message type" % relative_path)
			return
		var encoded := Codec.encode(decoded)
		if not encoded.ok or encoded.data != bytes:
			_fail("%s did not re-encode byte-for-byte" % relative_path)
			return
		decoded_types[decoded.header.message_type] = true
	if decoded_types.size() != 8:
		_fail("Expected all eight positive message types")
		return

	for fixture in manifest.negatives:
		var relative_path: String = fixture.file
		var bytes := FileAccess.get_file_as_bytes(fixture_root.path_join(relative_path))
		var decoded := Codec.decode(bytes)
		if decoded.ok or decoded.error != fixture.expected_rejection:
			_fail("%s expected %s, got %s" % [
				relative_path,
				fixture.expected_rejection,
				"accepted" if decoded.ok else decoded.error,
			])
			return

	var motion_bytes := FileAccess.get_file_as_bytes(
		fixture_root.path_join("positive/motion.bin")
	)
	var motion := Codec.decode(motion_bytes)
	var tolerance := float(manifest.float_tolerance)
	if (
		motion.payload.sensor_monotonic_ns != 123456789
		or abs(motion.payload.acceleration[0] - 1.0) > tolerance
		or abs(motion.payload.acceleration[2] - -9.80665) > tolerance
		or abs(motion.payload.angular_velocity[1] - -0.2) > tolerance
		or motion.payload.orientation != [0.0, 0.0, 0.0, 1.0]
		or motion.payload.accuracy != 3
		or motion.payload.sensor_flags != 7
	):
		_fail("Worked MOTION values differ from manifest")
		return

	print("TMB-009_GDSCRIPT_CODEC_OK positives=%d negatives=%d" % [
		manifest.positives.size(), manifest.negatives.size()
	])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
