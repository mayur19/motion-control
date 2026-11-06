class_name RacketFrame
extends RefCounted

const RIGHT := "right"
const LEFT := "left"
const QUATERNION_MIN_NORM := 0.98
const QUATERNION_MAX_NORM := 1.02
const CANONICAL_EPSILON := 0.000001


static func transform_sample(sample: Dictionary, calibration: Dictionary) -> Dictionary:
	var handedness := str(calibration.get("handedness", ""))
	if not [RIGHT, LEFT].has(handedness):
		return _failure("INVALID_HANDEDNESS")

	var acceleration_result := _read_vector3(sample.get("acceleration", []))
	var angular_velocity_result := _read_vector3(sample.get("angular_velocity", []))
	var acceleration_bias_result := _read_vector3(
		calibration.get("acceleration_bias", [])
	)
	var gyroscope_bias_result := _read_vector3(calibration.get("gyroscope_bias", []))
	for result in [
		acceleration_result,
		angular_velocity_result,
		acceleration_bias_result,
		gyroscope_bias_result,
	]:
		if not result.ok:
			return _failure("INVALID_VECTOR")

	var orientation_result := _read_quaternion(sample.get("orientation", []))
	var neutral_result := _read_quaternion(
		calibration.get("neutral_orientation", [])
	)
	if not orientation_result.ok or not neutral_result.ok:
		return _failure("INVALID_QUATERNION")

	var relative: Quaternion = (
		neutral_result.value.inverse() * orientation_result.value
	).normalized()
	var hand := (
		Quaternion.IDENTITY
		if handedness == RIGHT
		else Quaternion(0.0, 1.0, 0.0, 0.0)
	)
	var acceleration: Vector3 = hand * (
		relative * (acceleration_result.value - acceleration_bias_result.value)
	)
	var angular_velocity: Vector3 = hand * (
		relative * (angular_velocity_result.value - gyroscope_bias_result.value)
	)
	var orientation := (hand * relative * hand.inverse()).normalized()
	orientation = _canonicalize(orientation)

	return {
		"ok": true,
		"acceleration": _vector_array(acceleration),
		"angular_velocity": _vector_array(angular_velocity),
		"orientation": _quaternion_array(orientation),
	}


static func _read_vector3(value) -> Dictionary:
	if not value is Array or value.size() != 3:
		return {"ok": false}
	var vector := Vector3(float(value[0]), float(value[1]), float(value[2]))
	if not vector.is_finite():
		return {"ok": false}
	return {"ok": true, "value": vector}


static func _read_quaternion(value) -> Dictionary:
	if not value is Array or value.size() != 4:
		return {"ok": false}
	var quaternion := Quaternion(
		float(value[0]), float(value[1]), float(value[2]), float(value[3])
	)
	if not quaternion.is_finite():
		return {"ok": false}
	var magnitude := quaternion.length()
	if magnitude < QUATERNION_MIN_NORM or magnitude > QUATERNION_MAX_NORM:
		return {"ok": false}
	return {"ok": true, "value": quaternion.normalized()}


static func _canonicalize(value: Quaternion) -> Quaternion:
	var negate := value.w < -CANONICAL_EPSILON
	if absf(value.w) <= CANONICAL_EPSILON:
		for component in [value.x, value.y, value.z]:
			if absf(component) > CANONICAL_EPSILON:
				negate = component < 0.0
				break
	return Quaternion(-value.x, -value.y, -value.z, -value.w) if negate else value


static func _vector_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _quaternion_array(value: Quaternion) -> Array:
	return [value.x, value.y, value.z, value.w]


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}

