extends SceneTree

const Detector = preload("res://detection/early_swing_detector.gd")
const Preprocessor = preload("res://detection/motion_preprocessor.gd")


func _initialize() -> void:
	var detector := Detector.new()
	if bool(detector.configure({"onset_speed_rad_s": 0.0}).ok) \
			or bool(detector.configure({"rearm_speed_rad_s": 5.0, "onset_speed_rad_s": 3.0}).ok):
		return _fail("Invalid configuration accepted")
	if not bool(detector.configure({}).ok):
		return _fail("Defaults rejected")

	for rate in [100.0, 250.0]:
		var swing := _run(_profile_swing(8.0, 0.3), rate)
		if swing.events.size() != 1:
			return _fail("One swing at %d Hz gave %d triggers" % [rate, swing.events.size()])
		var event: Dictionary = swing.events[0]
		var lead_ms: float = (int(swing.peak_ns) - int(event.sensor_monotonic_ns)) / 1e6
		if lead_ms <= 0.0:
			return _fail("Trigger at %d Hz was not before the peak (lead %.1f ms)" % [rate, lead_ms])
		for key in ["detector", "version", "controller_id", "sequence", "sensor_monotonic_ns",
				"detector_time_ns", "confidence", "angular_speed_rad_s", "rise_rate_rad_s2"]:
			if not event.has(key):
				return _fail("Event missing %s: %s" % [key, str(event)])
		if float(event.confidence) <= 0.0 or float(event.confidence) > 1.0:
			return _fail("Confidence out of range: %s" % event.confidence)
		if int(event.detector_time_ns) != int(event.sensor_monotonic_ns) + 5_000_000:
			return _fail("detector_time_ns must be the trigger sample's host arrival time")
		print("lead_ms_%d=%.1f" % [rate, lead_ms])

	if _run(_profile_swing(2.5, 0.4), 100.0).events.size() != 0:
		return _fail("Slow handling rotation (2.5 rad/s) must not trigger")
	if _run(_profile_double_hump(), 100.0).events.size() != 1:
		return _fail("A swing whose speed dips but stays above re-arm must trigger once")
	if _run(_profile_two_swings(), 100.0).events.size() != 2:
		return _fail("Two separated swings must trigger twice")
	if _run(_profile_jitter(), 250.0).events.size() != 0:
		return _fail("Small fast jitter around a low speed must not trigger")
	if _run(_profile_swing(8.0, 0.3), 100.0, {"max_shaft_fraction": 0.5}, Vector3(0, 1, 0)).events.size() != 0:
		return _fail("Optional shaft gate must reject pure shaft rotation when enabled")
	if _run(_profile_swing(8.0, 0.3), 100.0, {}, Vector3(0, 1, 0)).events.size() != 1:
		return _fail("Shaft gate must be off by default")
	# Gap 180-280 ms during the rise: the jump across the gap must not count as a
	# rise; a later trigger from genuine post-gap rise samples is allowed.
	var gapped := _run(_profile_swing(8.0, 0.3), 100.0, {}, Vector3(1, 0, 0), 0.18)
	if gapped.events.size() > 1 or (gapped.events.size() == 1 \
			and int(gapped.events[0].sensor_monotonic_ns) <= 280_000_000):
		return _fail("Gap produced a trigger from the jump across it: %s" % str(gapped.events))

	# A new phone/stream reuses the controller id with a lower sensor clock.
	var swap_pre := Preprocessor.new()
	var swap_detector := Detector.new()
	swap_detector.configure({})
	var swap_events: Array[Dictionary] = []
	for base_ns in [50_000_000_000, 2_000_000_000]:
		var swing := _profile_swing(8.0, 0.3)
		for index in 150:
			var ns: int = base_ns + index * 10_000_000
			var speed: float = swing.call(index * 0.01)
			var prepared := swap_pre.process({"controller_id": 3, "sequence": index, "sensor_monotonic_ns": ns,
				"arrival_monotonic_ns": ns, "normalized": {"angular_velocity": [speed, 0.0, 0.0], "acceleration": [0.0, 0.0, 0.0]}})
			if bool(prepared.ok):
				swap_events.append_array(swap_detector.process(prepared))
	if swap_events.size() != 2:
		return _fail("A swapped stream with a lower clock must still detect its swing: %d events" % swap_events.size())

	var a := _run(_profile_two_swings(), 250.0)
	var b := _run(_profile_two_swings(), 250.0)
	if JSON.stringify(a.events) != JSON.stringify(b.events):
		return _fail("Detector is not deterministic")

	var cost_us := _cost_per_sample_us()
	if cost_us > 50.0:
		return _fail("Per-sample cost %.1f us is too high for the frame loop" % cost_us)
	print("TMB-032_DETECTOR_OK one_trigger_per_swing=true before_peak=true deterministic=true cost_us_per_sample=%.2f" % cost_us)
	quit(0)


## Runs a speed profile through preprocessing + detector at `rate_hz`.
func _run(profile: Callable, rate_hz: float, config := {}, axis := Vector3(1, 0, 0), gap_at_s := -1.0) -> Dictionary:
	var pre := Preprocessor.new()
	var detector := Detector.new()
	detector.configure(config)
	var events: Array[Dictionary] = []
	var peak_ns := 0
	var peak := -1.0
	for index in int(rate_hz * 2.5):
		var ns := int(index * 1e9 / rate_hz)
		if gap_at_s > 0.0 and ns >= int(gap_at_s * 1e9) and ns < int((gap_at_s + 0.1) * 1e9):
			continue
		var speed: float = profile.call(ns / 1e9)
		if speed > peak:
			peak = speed
			peak_ns = ns
		var omega := axis.normalized() * speed
		var prepared := pre.process({
			"controller_id": 3, "sequence": index, "sensor_monotonic_ns": ns,
			"arrival_monotonic_ns": ns + 5_000_000,
			"normalized": {"angular_velocity": [omega.x, omega.y, omega.z], "acceleration": [0.0, 0.0, 0.0]},
		})
		if bool(prepared.ok):
			events.append_array(detector.process(prepared))
	return {"events": events, "peak_ns": peak_ns}


func _profile_swing(peak: float, rise_s: float) -> Callable:
	return func(t: float) -> float:
		if t < 0.2 or t > 0.2 + 2.0 * rise_s:
			return 0.0
		return peak * sin((t - 0.2) / (2.0 * rise_s) * PI)


func _profile_double_hump() -> Callable:
	return func(t: float) -> float:
		if t < 0.2 or t > 0.9:
			return 0.0
		var u := (t - 0.2) / 0.7
		return 7.0 * sin(u * PI) * (1.0 - 0.45 * exp(-pow((u - 0.5) / 0.08, 2)))


func _profile_two_swings() -> Callable:
	var first := _profile_swing(7.0, 0.25)
	return func(t: float) -> float:
		return first.call(t) + first.call(t - 1.2)


func _profile_jitter() -> Callable:
	return func(t: float) -> float:
		return 1.0 + 0.6 * sin(t * 2.0 * PI * 40.0)


func _cost_per_sample_us() -> float:
	var pre := Preprocessor.new()
	var detector := Detector.new()
	detector.configure({})
	var prepared_samples: Array[Dictionary] = []
	for index in 20_000:
		var ns := index * 4_000_000
		var speed := 4.0 + 4.0 * sin(index / 30.0)
		prepared_samples.append(pre.process({"controller_id": 1, "sequence": index, "sensor_monotonic_ns": ns,
			"arrival_monotonic_ns": ns, "normalized": {"angular_velocity": [speed, 0.0, 0.0], "acceleration": [0.0, 0.0, 0.0]}}))
	var started := Time.get_ticks_usec()
	for prepared in prepared_samples:
		detector.process(prepared)
	return float(Time.get_ticks_usec() - started) / prepared_samples.size()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
