extends SceneTree

## TMB-028 fixture: one controlled swing, defined in the common racket frame,
## is expressed as raw protocol samples for iOS- and Android-like controllers
## (different arbitrary yaw origins, neutral tilts and sensor biases) held in
## either hand. Every variant must normalize to the same racket-frame axes.

const Normalizer = preload("res://motion/calibration_normalizer.gd")

const TOLERANCE := 0.0005
const SAMPLES := 120
const SESSION := 5
const LEFT_HAND := Quaternion(0.0, 1.0, 0.0, 0.0)

const VARIANTS := [
	{"name": "ios_right", "hand": "right", "yaw_deg": 0.0, "tilt_deg": 78.0,
		"accel_bias": [0.04, -0.01, 0.01], "gyro_bias": [0.007, 0.013, 0.002]},
	{"name": "ios_left", "hand": "left", "yaw_deg": -41.0, "tilt_deg": 72.0,
		"accel_bias": [0.06, 0.00, 0.02], "gyro_bias": [-0.013, -0.022, 0.006]},
	{"name": "android_right", "hand": "right", "yaw_deg": 117.0, "tilt_deg": 74.0,
		"accel_bias": [0.02, 0.10, 0.02], "gyro_bias": [-0.002, -0.024, 0.013]},
	{"name": "android_left", "hand": "left", "yaw_deg": 203.0, "tilt_deg": 70.0,
		"accel_bias": [0.01, 0.10, 0.03], "gyro_bias": [0.019, -0.025, -0.004]},
]


func _initialize() -> void:
	var reference := _reference_swing()
	var worst := 0.0
	for index in VARIANTS.size():
		var variant: Dictionary = VARIANTS[index]
		var controller_id := 100 + index
		var normalizer := Normalizer.new()
		var neutral := _neutral(variant)
		var accepted := normalizer.accept_calibration(controller_id, SESSION, {
			"handedness": variant.hand,
			"neutral_orientation": _quaternion_array(neutral),
			"acceleration_bias": variant.accel_bias,
			"gyroscope_bias": variant.gyro_bias,
		})
		if str(accepted.state) != Normalizer.CALIBRATED:
			return _fail("%s calibration rejected: %s" % [variant.name, str(accepted)])
		for step in reference.size():
			var expected: Dictionary = reference[step]
			var raw := _raw_sample(controller_id, variant, neutral, expected)
			var result := normalizer.normalize(raw)
			if str(result.status) != Normalizer.NORMALIZED:
				return _fail("%s step %d not normalized: %s" % [variant.name, step, str(result)])
			var normalized: Dictionary = result.normalized
			worst = maxf(worst, _distance(normalized.acceleration, _vector_array(expected.acceleration)))
			worst = maxf(worst, _distance(normalized.angular_velocity, _vector_array(expected.angular_velocity)))
			worst = maxf(worst, _quaternion_distance(normalized.orientation, expected.orientation))
			if worst > TOLERANCE:
				return _fail("%s step %d differs from reference by %f" % [variant.name, step, worst])
	print("TMB-028_NORMALIZATION_FIXTURE_OK variants=%d samples=%d max_error=%.6f" % [
		VARIANTS.size(), SAMPLES, worst,
	])
	quit(0)


## Reference swing in the common racket frame: a 90° arc about the racket
## frame's X axis with a smooth speed profile and matching acceleration.
func _reference_swing() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for step in SAMPLES:
		var t := float(step) / float(SAMPLES - 1)
		var angle := deg_to_rad(90.0) * (t - sin(TAU * t) / TAU)
		var speed := deg_to_rad(90.0) * (1.0 - cos(TAU * t)) / 0.6
		result.append({
			"orientation": Quaternion(Vector3(1, 0, 0), angle),
			"angular_velocity": Vector3(speed, 0.2 * speed, -0.1 * speed),
			"acceleration": Vector3(0.5 * speed, 3.0 * speed, -1.5 * speed),
		})
	return result


## Upright neutral grip: tilt about device X, then an arbitrary heading.
func _neutral(variant: Dictionary) -> Quaternion:
	var heading := Quaternion(Vector3(0, 0, 1), deg_to_rad(float(variant.yaw_deg)))
	var tilt := Quaternion(Vector3(1, 0, 0), deg_to_rad(float(variant.tilt_deg)))
	return (heading * tilt).normalized()


## Inverts docs/racket-coordinate-system.md §3 to produce what a controller
## would send for the reference motion.
func _raw_sample(controller_id: int, variant: Dictionary, neutral: Quaternion, expected: Dictionary) -> Dictionary:
	var hand := Quaternion.IDENTITY if variant.hand == "right" else LEFT_HAND
	var relative: Quaternion = (hand.inverse() * expected.orientation * hand).normalized()
	var acceleration: Vector3 = relative.inverse() * (hand.inverse() * expected.acceleration) \
		+ _vector(variant.accel_bias)
	var angular_velocity: Vector3 = relative.inverse() * (hand.inverse() * expected.angular_velocity) \
		+ _vector(variant.gyro_bias)
	return {
		"controller_id": controller_id,
		"session_id": SESSION,
		"acceleration": _vector_array(acceleration),
		"angular_velocity": _vector_array(angular_velocity),
		"orientation": _quaternion_array((neutral * relative).normalized()),
		"sensor_flags": 7,
	}


func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _vector_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _quaternion_array(value: Quaternion) -> Array:
	return [value.x, value.y, value.z, value.w]


func _distance(actual: Array, expected: Array) -> float:
	return _vector(actual).distance_to(_vector(expected))


func _quaternion_distance(actual: Array, expected: Quaternion) -> float:
	var q := Quaternion(float(actual[0]), float(actual[1]), float(actual[2]), float(actual[3]))
	return 1.0 - absf(q.dot(expected))


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
