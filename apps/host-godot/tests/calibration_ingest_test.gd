extends SceneTree

const Codec = preload("res://protocol/protocol_v1.gd")
const Ingest = preload("res://network/motion_ingest.gd")

var _calibration_events := 0
var _sample: Dictionary = {}


func _initialize() -> void:
	var ingest := Ingest.new()
	root.add_child(ingest)
	ingest.calibration_received.connect(func(_id: int, _value: Dictionary): _calibration_events += 1)
	ingest.sample_received.connect(func(value: Dictionary): _sample = value)

	var calibration := _packet(Codec.TYPE_CALIBRATION, 0, {
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

	var motion := _packet(Codec.TYPE_MOTION, 1, {
		"message_type": Codec.TYPE_MOTION,
		"sensor_monotonic_ns": 1_100_000_000,
		"acceleration": [-1.9, 3.2, -3.7],
		"angular_velocity": [-0.99, 2.02, -2.97],
		"orientation": [0.0, 0.0, 0.0, 1.0],
		"accuracy": 3,
		"sensor_flags": 7,
	})
	if not motion.ok:
		_fail("Could not encode motion: %s" % motion.error)
		return
	ingest._process_packet(motion.data, "192.0.2.1:7000", 2_100_000_000)
	if not bool(_sample.get("common_racket_frame", false)):
		_fail("Motion did not enter the common racket frame")
		return
	if not _near(_sample.acceleration, [2.0, 3.0, 4.0]):
		_fail("Left-hand acceleration normalization differed: %s" % str(_sample.acceleration))
		return
	if not _near(_sample.angular_velocity, [1.0, 2.0, 3.0]):
		_fail("Left-hand angular velocity normalization differed: %s" % str(_sample.angular_velocity))
		return

	print("TMB-027_CALIBRATION_INGEST_OK handedness=left common_frame=true")
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


func _near(actual: Array, expected: Array) -> bool:
	for index in expected.size():
		if absf(float(actual[index]) - float(expected[index])) > 0.0001:
			return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
