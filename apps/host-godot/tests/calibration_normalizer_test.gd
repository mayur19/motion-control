extends SceneTree

const Normalizer = preload("res://motion/calibration_normalizer.gd")
const Racket = preload("res://motion/racket_frame.gd")

const SESSION := 11
const OTHER_SESSION := 12
const CONTROLLER := 7


func _initialize() -> void:
	var normalizer := Normalizer.new()
	normalizer.set_active_session(SESSION)

	var uncalibrated := normalizer.normalize(_sample(SESSION, [0.0, 0.0, 0.0, 1.0]))
	if str(uncalibrated.status) != Normalizer.UNCALIBRATED or uncalibrated.has("normalized"):
		return _fail("Uncalibrated sample must not be normalized: %s" % str(uncalibrated))

	var accepted := normalizer.accept_calibration(CONTROLLER, SESSION, _calibration("left"))
	if str(accepted.state) != Normalizer.CALIBRATED or not bool(accepted.changed):
		return _fail("Calibration was not accepted: %s" % str(accepted))

	var sample := _sample(SESSION, [0.0, 0.0, 0.0, 1.0])
	var normalized := normalizer.normalize(sample)
	var expected := Racket.transform_sample(sample, _calibration("left"))
	if str(normalized.status) != Normalizer.NORMALIZED:
		return _fail("Calibrated sample was not normalized: %s" % str(normalized))
	if not _near(normalized.normalized.acceleration, expected.acceleration) \
			or not _near(normalized.normalized.angular_velocity, expected.angular_velocity) \
			or not _near(normalized.normalized.orientation, expected.orientation):
		return _fail("Normalized values differ from RacketFrame: %s" % str(normalized))
	if not _near(sample.acceleration, [-1.9, 3.2, -3.7]):
		return _fail("Raw sample was mutated: %s" % str(sample.acceleration))

	var other_session := normalizer.normalize(_sample(OTHER_SESSION, [0.0, 0.0, 0.0, 1.0]))
	if str(other_session.status) != Normalizer.UNCALIBRATED:
		return _fail("Calibration leaked into another session: %s" % str(other_session))

	var invalid := normalizer.normalize(_sample(SESSION, [0.0, 0.0, 0.0, 0.0]))
	if str(invalid.status) != Normalizer.PAUSED or str(invalid.reason) != "INVALID_QUATERNION":
		return _fail("Invalid transform did not pause the controller: %s" % str(invalid))
	if not bool(invalid.changed) or invalid.has("normalized"):
		return _fail("Pause must be reported once and carry no values: %s" % str(invalid))
	if str(normalizer.state_for(CONTROLLER).state) != Normalizer.PAUSED:
		return _fail("Controller state was not paused")

	var still_paused := normalizer.normalize(_sample(SESSION, [0.0, 0.0, 0.0, 1.0]))
	if str(still_paused.status) != Normalizer.PAUSED or bool(still_paused.changed):
		return _fail("Valid sample must stay paused until recalibration: %s" % str(still_paused))

	var recalibrated := normalizer.accept_calibration(CONTROLLER, SESSION, _calibration("right"))
	if str(recalibrated.state) != Normalizer.CALIBRATED or not bool(recalibrated.changed):
		return _fail("Recalibration did not clear the pause: %s" % str(recalibrated))
	if str(normalizer.normalize(_sample(SESSION, [0.0, 0.0, 0.0, 1.0])).status) != Normalizer.NORMALIZED:
		return _fail("Recalibrated controller was not normalized")

	var bad_calibration := normalizer.accept_calibration(CONTROLLER, SESSION, _calibration("sideways"))
	if str(bad_calibration.state) != Normalizer.PAUSED or str(bad_calibration.reason) != "INVALID_HANDEDNESS":
		return _fail("Invalid calibration must pause, not calibrate: %s" % str(bad_calibration))

	var inactive := normalizer.accept_calibration(CONTROLLER + 1, OTHER_SESSION, _calibration("right"))
	if str(inactive.state) != Normalizer.UNCALIBRATED or str(normalizer.state_for(CONTROLLER + 1).state) != Normalizer.UNCALIBRATED:
		return _fail("Calibration for an inactive session must be rejected: %s" % str(inactive))

	normalizer.accept_calibration(CONTROLLER, SESSION, _calibration("right"))
	normalizer.set_active_session(OTHER_SESSION)
	if str(normalizer.state_for(CONTROLLER).state) != Normalizer.UNCALIBRATED:
		return _fail("Session rotation must drop calibrations from the old session")
	if str(normalizer.normalize(_sample(SESSION, [0.0, 0.0, 0.0, 1.0])).status) != Normalizer.UNCALIBRATED:
		return _fail("Old-session sample normalized after rotation")

	normalizer.set_active_session(SESSION)
	normalizer.accept_calibration(CONTROLLER, SESSION, _calibration("right"))
	normalizer.forget(CONTROLLER)
	if str(normalizer.state_for(CONTROLLER).state) != Normalizer.UNCALIBRATED:
		return _fail("forget() did not clear the controller")

	print("TMB-028_NORMALIZER_OK session_scoped=true active_session_only=true pause_on_invalid=true raw_unchanged=true")
	quit(0)


func _sample(session_id: int, orientation: Array) -> Dictionary:
	return {
		"controller_id": CONTROLLER,
		"session_id": session_id,
		"acceleration": [-1.9, 3.2, -3.7],
		"angular_velocity": [-0.99, 2.02, -2.97],
		"orientation": orientation,
		"sensor_flags": 7,
	}


func _calibration(handedness: String) -> Dictionary:
	return {
		"handedness": handedness,
		"neutral_orientation": [0.0, 0.0, 0.0, 1.0],
		"acceleration_bias": [0.1, 0.2, 0.3],
		"gyroscope_bias": [0.01, 0.02, 0.03],
		"quality": 0.9,
	}


func _near(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) != TYPE_ARRAY or typeof(expected) != TYPE_ARRAY or actual.size() != expected.size():
		return false
	for index in expected.size():
		if absf(float(actual[index]) - float(expected[index])) > 0.0001:
			return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
