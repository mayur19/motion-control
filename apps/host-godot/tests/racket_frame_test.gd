extends SceneTree

const Racket = preload("res://motion/racket_frame.gd")


func _initialize() -> void:
	var fixture_path := ProjectSettings.globalize_path(
		"res://../../protocol/racket-coordinate-fixtures.json"
	)
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if typeof(fixture) != TYPE_DICTIONARY:
		_fail("Could not parse racket coordinate fixtures")
		return
	var tolerance := float(fixture.get("tolerance", 0.00001))
	var completed := 0
	for test_case in fixture.get("cases", []):
		var result := Racket.transform_sample(
			{
				"acceleration": test_case.acceleration_m_s2,
				"angular_velocity": test_case.angular_velocity_rad_s,
				"orientation": test_case.orientation_xyzw,
			},
			{
				"handedness": test_case.handedness,
				"neutral_orientation": test_case.neutral_orientation_xyzw,
				"acceleration_bias": test_case.acceleration_bias_m_s2,
				"gyroscope_bias": test_case.gyroscope_bias_rad_s,
			},
		)
		if not result.ok:
			_fail("%s rejected with %s" % [test_case.name, result.get("error", "unknown")])
			return
		if not _close(result.acceleration, test_case.expected_acceleration_r, tolerance):
			_fail("%s acceleration mismatch: %s" % [test_case.name, result.acceleration])
			return
		if not _close(
			result.angular_velocity,
			test_case.expected_angular_velocity_r,
			tolerance,
		):
			_fail("%s angular velocity mismatch: %s" % [
				test_case.name, result.angular_velocity
			])
			return
		if not _close(result.orientation, test_case.expected_orientation_r_xyzw, tolerance):
			_fail("%s orientation mismatch: %s" % [test_case.name, result.orientation])
			return
		completed += 1

	var invalid_hand := Racket.transform_sample(
		{"acceleration": [0, 0, 0], "angular_velocity": [0, 0, 0], "orientation": [0, 0, 0, 1]},
		{"handedness": "unknown", "neutral_orientation": [0, 0, 0, 1], "acceleration_bias": [0, 0, 0], "gyroscope_bias": [0, 0, 0]},
	)
	if invalid_hand.ok or invalid_hand.error != "INVALID_HANDEDNESS":
		_fail("Invalid handedness was accepted")
		return
	var invalid_quaternion := Racket.transform_sample(
		{"acceleration": [0, 0, 0], "angular_velocity": [0, 0, 0], "orientation": [0, 0, 0, 0]},
		{"handedness": "right", "neutral_orientation": [0, 0, 0, 1], "acceleration_bias": [0, 0, 0], "gyroscope_bias": [0, 0, 0]},
	)
	if invalid_quaternion.ok or invalid_quaternion.error != "INVALID_QUATERNION":
		_fail("Invalid quaternion was accepted")
		return

	print("TMB-026_RACKET_FRAME_OK cases=%d invalid_checks=2" % completed)
	quit(0)


func _close(actual: Array, expected: Array, tolerance: float) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		if absf(float(actual[index]) - float(expected[index])) > tolerance:
			return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

