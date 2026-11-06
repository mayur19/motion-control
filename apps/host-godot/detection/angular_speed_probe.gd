class_name AngularSpeedProbe
extends RefCounted

## TMB-029 reference placeholder kept for comparison: one event per rising
## crossing of preprocessed angular speed above `threshold_rad_s`, outside the
## refractory window. Not a swing detector (see EarlySwingDetector).

const NAME := "angular_speed_probe"
const VERSION := 1
const DEFAULTS := {"threshold_rad_s": 3.5, "refractory_ms": 700}

var _config: Dictionary = {"detector": NAME, "threshold_rad_s": 3.5, "refractory_ms": 700}
var _state: Dictionary = {}


func configure(config: Dictionary) -> Dictionary:
	var merged := DEFAULTS.duplicate(true)
	merged.merge(config, true)
	var threshold := float(merged.threshold_rad_s)
	var refractory := int(merged.refractory_ms)
	if not is_finite(threshold) or threshold <= 0.0 or refractory < 0:
		return {"ok": false, "error": "threshold_rad_s must be > 0 and refractory_ms >= 0"}
	_config = {"detector": NAME, "threshold_rad_s": threshold, "refractory_ms": refractory}
	_state = {}
	return {"ok": true}


func describe() -> Dictionary:
	return {"detector": NAME, "version": VERSION, "config": _config.duplicate(true)}


func reset() -> void:
	_state = {}


func process(prepared: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var speed := float(prepared.preprocessed.angular_speed)
	var controller_id := int(prepared.controller_id)
	var sensor_ns := int(prepared.sensor_monotonic_ns)
	var state: Dictionary = _state.get(controller_id, {"above": false, "last_event_ns": -1})
	var above := speed >= float(_config.threshold_rad_s)
	var outside_refractory := (
		int(state.last_event_ns) < 0
		or sensor_ns - int(state.last_event_ns) >= int(_config.refractory_ms) * 1_000_000
	)
	if above and not bool(state.above) and outside_refractory:
		events.append({
			"detector": NAME,
			"controller_id": controller_id,
			"sequence": int(prepared.sequence),
			"sensor_monotonic_ns": sensor_ns,
			"arrival_monotonic_ns": int(prepared.arrival_monotonic_ns),
			"angular_speed_rad_s": speed,
		})
		state.last_event_ns = sensor_ns
	state.above = above
	_state[controller_id] = state
	return events
