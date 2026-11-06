class_name EarlySwingDetector
extends RefCounted

## TMB-032 early-swing detector (docs/swing-detection.md). Consumes
## MotionPreprocessor output and triggers on the early rise of angular speed:
## speed above `onset_speed_rad_s` while it has risen by at least
## `min_rise_rad_s2` (measured over `rise_window_ms` of real sensor time, so
## the test is sample-rate independent). After a trigger the controller is
## disarmed until speed falls below `rearm_speed_rad_s` (hysteresis) and the
## `refractory_ms` window has passed, giving at most one trigger per swing.
## Thresholds are provisional until tuned on TMB-030 data (TMB-033).

const NAME := "early_rise"
const VERSION := 1
const DEFAULTS := {
	"onset_speed_rad_s": 3.0,
	"min_rise_rad_s2": 20.0,
	"rise_window_ms": 40,
	"rearm_speed_rad_s": 1.5,
	"refractory_ms": 350,
	## Optional directional gate; 1.0 disables it. Real swings ranged from 14%
	## to 96% shaft rotation in the TMB-029 capture, so it is off by default.
	"max_shaft_fraction": 1.0,
}

var _config: Dictionary = DEFAULTS.duplicate(true)
## controller_id -> {armed, last_trigger_ns, history: Array[[ns, speed]]}
var _state: Dictionary = {}


func configure(config: Dictionary) -> Dictionary:
	var merged := DEFAULTS.duplicate(true)
	merged.merge(config, true)
	var onset := float(merged.onset_speed_rad_s)
	var rise := float(merged.min_rise_rad_s2)
	var window := int(merged.rise_window_ms)
	var rearm := float(merged.rearm_speed_rad_s)
	var refractory := int(merged.refractory_ms)
	var shaft := float(merged.max_shaft_fraction)
	if onset <= 0.0 or rise <= 0.0 or window <= 0 or refractory < 0:
		return {"ok": false, "error": "onset, rise and window must be > 0; refractory >= 0"}
	if rearm < 0.0 or rearm >= onset:
		return {"ok": false, "error": "rearm_speed_rad_s must be >= 0 and below onset_speed_rad_s"}
	if shaft <= 0.0 or shaft > 1.0:
		return {"ok": false, "error": "max_shaft_fraction must be in (0, 1]"}
	_config = {
		"onset_speed_rad_s": onset, "min_rise_rad_s2": rise, "rise_window_ms": window,
		"rearm_speed_rad_s": rearm, "refractory_ms": refractory, "max_shaft_fraction": shaft,
	}
	_state = {}
	return {"ok": true}


func describe() -> Dictionary:
	return {"detector": NAME, "version": VERSION, "config": _config.duplicate(true)}


func reset() -> void:
	_state = {}


## `prepared` is a MotionPreprocessor result (ok == true). Returns 0 or 1 events.
func process(prepared: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var data: Dictionary = prepared.preprocessed
	var controller_id := int(prepared.controller_id)
	var ns := int(prepared.sensor_monotonic_ns)
	var speed := float(data.angular_speed)
	var state: Dictionary = _state.get(controller_id, {"armed": true, "last_trigger_ns": -1, "history": []})
	if bool(data.gap_reset):
		state.history = []  # never measure a rise across a gap
		if int(state.last_trigger_ns) > ns:
			# Stream restarted on a lower clock: earlier refractory/arm state is
			# from another stream and must not suppress this one.
			state.armed = true
			state.last_trigger_ns = -1
	var history: Array = state.history
	history.append([ns, speed])
	var window_ns := int(_config.rise_window_ms) * 1_000_000
	while history.size() > 2 and ns - int(history[1][0]) >= window_ns:
		history.pop_front()

	if not bool(state.armed) and speed < float(_config.rearm_speed_rad_s):
		state.armed = true
	var elapsed_ns := ns - int(history[0][0])
	var rise_rate := (speed - float(history[0][1])) / (elapsed_ns / 1e9) if elapsed_ns > 0 else 0.0
	var outside_refractory := (
		int(state.last_trigger_ns) < 0
		or ns - int(state.last_trigger_ns) >= int(_config.refractory_ms) * 1_000_000
	)
	var omega: Array = data.angular_velocity
	var shaft_fraction := absf(float(omega[1])) / speed if speed > 0.0 else 0.0
	if (
		bool(state.armed)
		and outside_refractory
		and speed >= float(_config.onset_speed_rad_s)
		and elapsed_ns * 2 >= window_ns
		and rise_rate >= float(_config.min_rise_rad_s2)
		and shaft_fraction <= float(_config.max_shaft_fraction)
	):
		events.append({
			"detector": NAME,
			"version": VERSION,
			"controller_id": controller_id,
			"sequence": int(prepared.sequence),
			"sensor_monotonic_ns": ns,
			"arrival_monotonic_ns": int(prepared.arrival_monotonic_ns),
			"detector_time_ns": int(prepared.arrival_monotonic_ns),
			"confidence": _confidence(speed, rise_rate),
			"angular_speed_rad_s": speed,
			"rise_rate_rad_s2": rise_rate,
			"shaft_fraction": shaft_fraction,
		})
		state.armed = false
		state.last_trigger_ns = ns
	state.history = history
	_state[controller_id] = state
	return events


## Heuristic margin score in (0, 1], not a calibrated probability.
func _confidence(speed: float, rise_rate: float) -> float:
	var onset := float(_config.onset_speed_rad_s)
	var rise := float(_config.min_rise_rad_s2)
	var speed_margin := clampf((speed - onset) / onset, 0.0, 1.0)
	var rise_margin := clampf((rise_rate - rise) / rise, 0.0, 1.0)
	return clampf(0.2 + 0.4 * speed_margin + 0.4 * rise_margin, 0.05, 1.0)
