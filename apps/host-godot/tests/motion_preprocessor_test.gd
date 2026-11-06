extends SceneTree

const Preprocessor = preload("res://detection/motion_preprocessor.gd")


func _initialize() -> void:
	var pre := Preprocessor.new()
	if bool(pre.configure({"cutoff_hz": 0.0}).ok) or bool(pre.configure({"max_gap_ms": -1}).ok):
		return _fail("Invalid configuration accepted")
	if not bool(pre.configure({"cutoff_hz": 25.0, "max_gap_ms": 50}).ok):
		return _fail("Valid configuration rejected")
	var described := pre.describe()
	if str(described.name) != "one_pole_lowpass" or float(described.config.cutoff_hz) != 25.0:
		return _fail("describe() incomplete: %s" % str(described))

	# Uncalibrated samples never enter preprocessing.
	if bool(pre.process({"controller_id": 1, "sensor_monotonic_ns": 1}).ok):
		return _fail("Sample without normalized values was accepted")

	# Gaps, duplicates and non-finite inputs.
	pre.reset()
	var first := pre.process(_sample(1, 0, 0.0))
	if not bool(first.ok) or not bool(first.preprocessed.gap_reset):
		return _fail("First sample must seed the filter with gap_reset: %s" % str(first))
	var duplicate := pre.process(_sample(1, 0, 5.0))
	if bool(duplicate.ok) or str(duplicate.dropped) != "non_monotonic":
		return _fail("Duplicate sensor time must be dropped: %s" % str(duplicate))
	var nan := pre.process(_sample(1, 10_000_000, NAN))
	if bool(nan.ok) or str(nan.dropped) != "non_finite":
		return _fail("Non-finite sample must be dropped: %s" % str(nan))
	var after_gap := pre.process(_sample(1, 200_000_000, 6.0))
	if not bool(after_gap.ok) or not bool(after_gap.preprocessed.gap_reset):
		return _fail("190 ms gap must reset the filter: %s" % str(after_gap))
	if absf(float(after_gap.preprocessed.angular_speed) - 6.0) > 0.0001 \
			or float(after_gap.preprocessed.angular_accel) != 0.0:
		return _fail("Gap reset must reseed without a derivative spike: %s" % str(after_gap))
	var irregular_ok := true
	var t := 200_000_000
	for step in [3, 11, 4, 9, 13, 2, 8]:
		t += step * 1_000_000
		var result := pre.process(_sample(1, t, 6.0 + sin(t / 1e8)))
		irregular_ok = irregular_ok and bool(result.ok) and not bool(result.preprocessed.gap_reset) \
			and is_finite(float(result.preprocessed.angular_accel)) \
			and absf(float(result.preprocessed.angular_accel)) < 200.0
	if not irregular_ok:
		return _fail("Irregular intervals produced resets, non-finite values or spikes")

	# Determinism: identical input -> identical output.
	var a := _run_swing(Preprocessor.new(), 100.0)
	var b := _run_swing(Preprocessor.new(), 100.0)
	if JSON.stringify(a) != JSON.stringify(b):
		return _fail("Preprocessing is not deterministic")

	# Delay measurements (documented in docs/motion-preprocessing.md).
	var delays := {}
	for rate in [100.0, 250.0]:
		delays["trigger_%d" % rate] = _trigger_delay_ms(rate, 3.5)
		delays["ramp_%d" % rate] = _ramp_lag_ms(rate)
	var tau_ms := 1000.0 / (TAU * 25.0)
	for key in delays:
		if float(delays[key]) < 0.0 or float(delays[key]) > 2.0 * tau_ms + 10.0:
			return _fail("Delay %s out of range: %s ms" % [key, delays[key]])
	print("TMB-031_PREPROCESSOR_OK deterministic=true gaps=true irregular=true " +
		"trigger_ms=%.1f/%.1f ramp_lag_ms=%.1f/%.1f (100/250 Hz) tau_ms=%.1f" % [
		delays.trigger_100, delays.trigger_250,
		delays.ramp_100, delays.ramp_250, tau_ms])
	quit(0)


func _sample(controller_id: int, sensor_ns: int, speed: float) -> Dictionary:
	return {
		"controller_id": controller_id,
		"sequence": sensor_ns / 1_000_000,
		"sensor_monotonic_ns": sensor_ns,
		"arrival_monotonic_ns": sensor_ns + 5_000_000,
		"normalized": {
			"angular_velocity": [speed, 0.0, 0.0],
			"acceleration": [0.0, speed, 0.0],
			"orientation": [0.0, 0.0, 0.0, 1.0],
		},
	}


## Raw swing-shaped speed profile: rest, then a 300 ms rise to 8 rad/s.
func _swing_speed(t_s: float) -> float:
	if t_s < 0.1:
		return 0.0
	return 8.0 * sin(clampf((t_s - 0.1) / 0.3, 0.0, 1.0) * PI / 2.0)


func _run_swing(pre, rate_hz: float) -> Array:
	var out := []
	for index in int(rate_hz * 0.6):
		var ns := int(index * 1e9 / rate_hz)
		out.append(pre.process(_sample(1, ns, _swing_speed(ns / 1e9))))
	return out


## Extra (interpolated) time for the filtered swing to cross the threshold.
func _trigger_delay_ms(rate_hz: float, threshold: float) -> float:
	return _crossing_delay_ms(rate_hz, threshold, _swing_speed)


## Steady-state lag on a constant-slope ramp: filtered(t) == raw(t - lag).
func _ramp_lag_ms(rate_hz: float) -> float:
	var pre := Preprocessor.new()
	var slope := 20.0  # rad/s per second
	var last := {}
	for index in int(rate_hz * 1.0):
		var ns := int(index * 1e9 / rate_hz)
		last = pre.process(_sample(1, ns, slope * ns / 1e9))
	var t_s := int(last.sensor_monotonic_ns) / 1e9
	return (t_s - float(last.preprocessed.angular_speed) / slope) * 1000.0


func _crossing_delay_ms(rate_hz: float, level: float, profile: Callable) -> float:
	var pre := Preprocessor.new()
	var raw_cross := -1.0
	var filtered_cross := -1.0
	var previous_t := 0.0
	var previous_raw := 0.0
	var previous_filtered := 0.0
	for index in int(rate_hz * 0.6):
		var ns := int(index * 1e9 / rate_hz)
		var t_s := ns / 1e9
		var raw: float = profile.call(t_s)
		var filtered := float(pre.process(_sample(1, ns, raw)).preprocessed.angular_speed)
		if index > 0:
			if raw_cross < 0.0 and raw >= level:
				raw_cross = _interpolate(previous_t, previous_raw, t_s, raw, level)
			if filtered_cross < 0.0 and filtered >= level:
				filtered_cross = _interpolate(previous_t, previous_filtered, t_s, filtered, level)
		previous_t = t_s
		previous_raw = raw
		previous_filtered = filtered
	return (filtered_cross - raw_cross) * 1000.0 if raw_cross >= 0.0 and filtered_cross >= 0.0 else -1.0


func _interpolate(t0: float, v0: float, t1: float, v1: float, level: float) -> float:
	return t1 if is_equal_approx(v1, v0) else t0 + (level - v0) / (v1 - v0) * (t1 - t0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
