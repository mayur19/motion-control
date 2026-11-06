extends SceneTree

const Synchronizer = preload("res://network/clock_synchronizer.gd")


func _initialize() -> void:
	var known := Synchronizer.new()
	# 50 ms controller lead, 5 ms symmetric one-way delay, 1 ms processing.
	if not known.record_exchange(1_000_000_000, 1_055_000_000, 1_056_000_000, 1_011_000_000):
		_fail("Known-offset exchange was rejected")
		return
	_assert_near(known.snapshot().offset_ms, 50.0, 0.001, "known offset")
	_assert_near(known.snapshot().rtt_ms, 10.0, 0.001, "known RTT")

	var jitter := Synchronizer.new()
	for one_way_ms in [18, 4, 12, 5, 25, 6, 7, 20]:
		var t1: int = 2_000_000_000 + int(jitter.snapshot().samples) * 100_000_000
		var delay := int(one_way_ms) * 1_000_000
		var offset := 30_000_000
		jitter.record_exchange(t1, t1 + delay + offset, t1 + delay + offset + 500_000, t1 + delay * 2 + 500_000)
	_assert_near(jitter.snapshot().offset_ms, 30.0, 0.05, "low-RTT jitter selection")
	if float(jitter.snapshot().rtt_ms) > 12.1:
		_fail("Estimator did not prefer low-RTT samples: %s" % str(jitter.snapshot()))
		return
	if absf(float(jitter.snapshot().drift_ppm)) > 0.001:
		_fail("Sub-second sample selection produced a false drift spike")
		return

	var asymmetric := Synchronizer.new()
	# 4 ms outbound / 8 ms inbound biases NTP offset by -2 ms; the documented
	# tolerance is half the path asymmetry because it is not separately observable.
	asymmetric.record_exchange(3_000_000_000, 3_044_000_000, 3_045_000_000, 3_013_000_000)
	_assert_near(asymmetric.snapshot().offset_ms, 38.0, 0.001, "asymmetric offset")

	var drift := Synchronizer.new()
	for index in 11:
		var elapsed: int = index * 30_000_000_000
		var changing_offset: int = 20_000_000 + int(elapsed * 100.0 / 1_000_000.0)
		var t1: int = 4_000_000_000 + elapsed
		drift.record_exchange(
			t1,
			t1 + 3_000_000 + changing_offset,
			t1 + 3_500_000 + changing_offset,
			t1 + 6_500_000
		)
	_assert_near(drift.snapshot().drift_ppm, 100.0, 0.1, "five-minute drift")

	var first_converted := drift.controller_to_host(100_000_000_000)
	var second_converted := drift.controller_to_host(99_000_000_000)
	if second_converted != first_converted + 1 or drift.snapshot().backward_corrections != 1:
		_fail("Backward adjusted time was not clamped and counted")
		return

	print(
		"TMB-020_CLOCK_TEST_OK known_offset_ms=%.3f jitter_offset_ms=%.3f asymmetry_error_ms=2.000 drift_ppm=%.1f backward_corrections=1" % [
			known.snapshot().offset_ms, jitter.snapshot().offset_ms, drift.snapshot().drift_ppm,
		]
	)
	quit(0)


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		_fail("%s expected %.6f +/- %.6f, got %.6f" % [label, expected, tolerance, actual])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
