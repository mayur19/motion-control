class_name CalibrationNormalizer
extends RefCounted

## TMB-028 host calibration gate. Holds each controller's calibration for the
## session it arrived in, converts raw samples to the common racket frame and
## pauses a controller whose calibration produces an invalid transform. Only
## `NORMALIZED` results may reach swing detection.

const RacketFrameTransform = preload("res://motion/racket_frame.gd")

const UNCALIBRATED := "uncalibrated"
const CALIBRATED := "calibrated"
const NORMALIZED := "normalized"
const PAUSED := "paused"
const CONTROLLER_APPLIED_FLAG := 0x10

## controller_id -> {state, reason, session_id, calibration}
var _controllers: Dictionary = {}
var _has_active_session := false
var _active_session_id := 0


## Binds the gate to the host's active pairing session. Calibrations from any
## other session are dropped, so rotating the session clears them.
func set_active_session(session_id: int) -> void:
	if _has_active_session and _active_session_id == session_id:
		return
	_has_active_session = true
	_active_session_id = session_id
	for controller_id in _controllers.keys():
		if int(_controllers[controller_id].session_id) != session_id:
			_controllers.erase(controller_id)


## Stores a decoded calibration for `session_id`. A calibration that cannot be
## applied (checked against an identity sample) pauses the controller instead.
func accept_calibration(controller_id: int, session_id: int, calibration: Dictionary) -> Dictionary:
	if not _is_active(session_id):
		return {"state": UNCALIBRATED, "reason": "inactive session", "changed": false}
	var probe := RacketFrameTransform.transform_sample(
		{
			"acceleration": [0.0, 0.0, 0.0],
			"angular_velocity": [0.0, 0.0, 0.0],
			"orientation": calibration.get("neutral_orientation", []),
		},
		calibration,
	)
	if not probe.ok:
		return _set_state(controller_id, PAUSED, str(probe.error), session_id, {})
	return _set_state(controller_id, CALIBRATED, "calibration accepted", session_id, calibration.duplicate(true))


## Returns {status, reason, changed[, normalized]} without modifying `sample`.
## `normalized` holds acceleration, angular_velocity and orientation in the
## common racket frame and is present only when status is NORMALIZED.
func normalize(sample: Dictionary) -> Dictionary:
	var controller_id := int(sample.get("controller_id", 0))
	var entry: Dictionary = _controllers.get(controller_id, {})
	var session_id := int(sample.get("session_id", -1))
	if entry.is_empty() or int(entry.session_id) != session_id or not _is_active(session_id):
		return {"status": UNCALIBRATED, "reason": "no calibration for this session", "changed": false}
	if str(entry.state) == PAUSED:
		return {"status": PAUSED, "reason": str(entry.reason), "changed": false}

	if (int(sample.get("sensor_flags", 0)) & CONTROLLER_APPLIED_FLAG) != 0:
		return _paused(controller_id, "CONTROLLER_APPLIED_CALIBRATION_UNSUPPORTED")
	var transformed := RacketFrameTransform.transform_sample(sample, entry.calibration)
	if not transformed.ok:
		return _paused(controller_id, str(transformed.error))
	return {
		"status": NORMALIZED,
		"reason": "",
		"changed": false,
		"normalized": {
			"acceleration": transformed.acceleration,
			"angular_velocity": transformed.angular_velocity,
			"orientation": transformed.orientation,
		},
	}


func state_for(controller_id: int) -> Dictionary:
	var entry: Dictionary = _controllers.get(controller_id, {})
	if entry.is_empty():
		return {"state": UNCALIBRATED, "reason": "no calibration"}
	return {"state": str(entry.state), "reason": str(entry.reason), "session_id": int(entry.session_id)}


func _is_active(session_id: int) -> bool:
	return not _has_active_session or session_id == _active_session_id


func forget(controller_id: int) -> void:
	_controllers.erase(controller_id)


func _paused(controller_id: int, reason: String) -> Dictionary:
	var entry: Dictionary = _controllers[controller_id]
	var result := _set_state(controller_id, PAUSED, reason, int(entry.session_id), {})
	return {"status": PAUSED, "reason": reason, "changed": bool(result.changed)}


func _set_state(
	controller_id: int, state: String, reason: String, session_id: int, calibration: Dictionary
) -> Dictionary:
	var previous: Dictionary = _controllers.get(controller_id, {})
	var changed := (
		previous.is_empty()
		or str(previous.state) != state
		or str(previous.reason) != reason
		or int(previous.session_id) != session_id
		or state == CALIBRATED
	)
	_controllers[controller_id] = {
		"state": state,
		"reason": reason,
		"session_id": session_id,
		"calibration": calibration,
	}
	return {"state": state, "reason": reason, "changed": changed}
