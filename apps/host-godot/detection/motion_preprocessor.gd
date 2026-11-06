class_name MotionPreprocessor
extends RefCounted

## TMB-031 motion preprocessing (docs/motion-preprocessing.md). Input is a
## normalized sample (TMB-028 bias removal + common racket frame). Output adds
## `preprocessed`: causal one-pole low-pass angular velocity and acceleration,
## filtered angular speed and its rate of change. The filter is rate-aware
## (uses the real sensor interval), drops duplicate/out-of-order and
## non-finite samples, and reseeds after a gap instead of bridging it, so gaps
## cannot create false spikes. Deterministic for identical input.

const NAME := "one_pole_lowpass"
const VERSION := 1
const DEFAULTS := {"cutoff_hz": 25.0, "max_gap_ms": 50}

var _config: Dictionary = DEFAULTS.duplicate(true)
## controller_id -> {last_ns, omega: Vector3, accel: Vector3, speed: float}
var _state: Dictionary = {}


func configure(config: Dictionary) -> Dictionary:
	var merged := DEFAULTS.duplicate(true)
	merged.merge(config, true)
	var cutoff := float(merged.cutoff_hz)
	var max_gap := int(merged.max_gap_ms)
	if not is_finite(cutoff) or cutoff <= 0.0 or max_gap <= 0:
		return {"ok": false, "error": "cutoff_hz must be > 0 and max_gap_ms > 0"}
	_config = {"cutoff_hz": cutoff, "max_gap_ms": max_gap}
	_state = {}
	return {"ok": true}


func describe() -> Dictionary:
	return {"name": NAME, "version": VERSION, "config": _config.duplicate(true)}


func reset() -> void:
	_state = {}


## Returns {ok: true, ...sample identity, preprocessed} or {ok: false, dropped}.
func process(sample: Dictionary) -> Dictionary:
	var normalized: Dictionary = sample.get("normalized", {})
	var omega_raw: Variant = _vector(normalized.get("angular_velocity", []))
	var accel_raw: Variant = _vector(normalized.get("acceleration", []))
	if omega_raw == null or accel_raw == null:
		return {"ok": false, "dropped": "not_normalized" if normalized.is_empty() else "non_finite"}
	var controller_id := int(sample.get("controller_id", 0))
	var sensor_ns := int(sample.get("sensor_monotonic_ns", 0))
	var state: Dictionary = _state.get(controller_id, {})
	var gap_reset := state.is_empty()
	var dt_s := 0.0
	if not gap_reset:
		var delta_ns := sensor_ns - int(state.last_ns)
		if delta_ns <= 0:
			return {"ok": false, "dropped": "non_monotonic"}
		dt_s = delta_ns / 1e9
		gap_reset = delta_ns > int(_config.max_gap_ms) * 1_000_000

	var omega: Vector3 = omega_raw
	var accel: Vector3 = accel_raw
	var angular_accel := 0.0
	if not gap_reset:
		var alpha := 1.0 - exp(-TAU * float(_config.cutoff_hz) * dt_s)
		omega = state.omega + (omega_raw - state.omega) * alpha
		accel = state.accel + (accel_raw - state.accel) * alpha
	var speed := omega.length()
	if not gap_reset:
		angular_accel = (speed - float(state.speed)) / dt_s
	_state[controller_id] = {"last_ns": sensor_ns, "omega": omega, "accel": accel, "speed": speed}
	return {
		"ok": true,
		"controller_id": controller_id,
		"sequence": int(sample.get("sequence", 0)),
		"sensor_monotonic_ns": sensor_ns,
		"arrival_monotonic_ns": int(sample.get("arrival_monotonic_ns", 0)),
		"preprocessed": {
			"angular_velocity": [omega.x, omega.y, omega.z],
			"acceleration": [accel.x, accel.y, accel.z],
			"angular_speed": speed,
			"angular_accel": angular_accel,
			"dt_ms": dt_s * 1000.0,
			"gap_reset": gap_reset,
		},
	}


## Vector3, or null when missing or non-finite.
static func _vector(values: Variant) -> Variant:
	if typeof(values) != TYPE_ARRAY or values.size() != 3:
		return null
	var vector := Vector3(float(values[0]), float(values[1]), float(values[2]))
	return vector if vector.is_finite() else null
