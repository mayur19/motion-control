extends SceneTree

const Ingest = preload("res://network/motion_ingest.gd")
const Stimulus = preload("res://latency/raw_latency_stimulus.gd")

var records: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ingest := Ingest.new()
	root.add_child(ingest)
	var stimulus := Stimulus.new()
	root.add_child(stimulus)
	stimulus.bind(ingest)
	stimulus.stimulus_triggered.connect(func(record: Dictionary) -> void:
		records.append(record)
	)
	stimulus.armed = true
	stimulus.set_threshold(4.0)

	ingest.sample_received.emit(_sample(1, Vector3(0.0, 5.0, 0.0)))
	ingest.sample_received.emit(_sample(2, Vector3(0.0, 8.0, 0.0)))
	await _wait_for_records(1)
	if records.size() != 1:
		_fail("Burst produced more than one stimulus")
		return
	var first := records[0]
	for field in [
		"sensor_monotonic_ns", "arrival_monotonic_ns", "threshold_monotonic_ns",
		"simulation_marker_monotonic_ns", "render_marker_monotonic_ns"
	]:
		if int(first.get(field, 0)) <= 0:
			_fail("Missing timestamp field: %s" % field)
			return
	if int(first.render_marker_monotonic_ns) < int(first.threshold_monotonic_ns):
		_fail("Render marker preceded threshold")
		return

	stimulus.set_threshold(10.0)
	stimulus.cooldown_ms = 0
	ingest.sample_received.emit(_sample(3, Vector3(0.0, 9.0, 0.0)))
	await process_frame
	if records.size() != 1:
		_fail("Below-threshold sample produced a stimulus")
		return
	ingest.sample_received.emit(_sample(4, Vector3(0.0, 11.0, 0.0)))
	await _wait_for_records(2)
	if records.size() != 2 or float(records[1].threshold_rad_s) != 10.0:
		_fail("Runtime threshold adjustment was not applied")
		return
	print(
		"TMB-023_RAW_LATENCY_OK burst_count=1 adjustable=true timestamps=5 render_after_threshold=true"
	)
	quit(0)


func _sample(sequence: int, gyro: Vector3) -> Dictionary:
	var now := Time.get_ticks_usec() * 1000
	return {
		"controller_id": 1,
		"sequence": sequence,
		"sensor_monotonic_ns": now - 2_000_000,
		"adjusted_host_monotonic_ns": now - 2_000_000,
		"arrival_monotonic_ns": now - 1_000_000,
		"angular_velocity": gyro,
	}


func _wait_for_records(count: int) -> void:
	var deadline := Time.get_ticks_msec() + 1000
	while records.size() < count and Time.get_ticks_msec() < deadline:
		await process_frame
	if records.size() < count:
		_fail("Timed out waiting for rendered stimulus")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
