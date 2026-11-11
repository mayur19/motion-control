extends SceneTree

## `--latency-test` must not hide the pairing QR: the stimulus starts disarmed
## and arms itself on the first motion sample (which only arrives after pairing).

const Ingest = preload("res://network/motion_ingest.gd")
const Stimulus = preload("res://latency/raw_latency_stimulus.gd")

var records: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ingest := Ingest.new()
	root.add_child(ingest)

	var stimulus := _stimulus(ingest)
	stimulus.apply_cmdline(PackedStringArray(["--latency-test"]))
	if stimulus.armed or stimulus.visible:
		_fail("--latency-test armed the overlay before any phone paired")
		return
	if not stimulus.arm_on_first_sample:
		_fail("--latency-test did not request auto-arm")
		return

	ingest.sample_received.emit(_sample(1, Vector3(0.0, 8.0, 0.0)))
	await process_frame
	await process_frame
	if not stimulus.armed or not stimulus.visible:
		_fail("First motion sample did not arm the stimulus")
		return
	if not records.is_empty():
		_fail("The arming sample itself produced a stimulus")
		return

	ingest.sample_received.emit(_sample(2, Vector3(0.0, 8.0, 0.0)))
	await _wait_for_records(1)
	if records.size() != 1:
		_fail("Armed stimulus did not trigger")
		return

	var manual := _stimulus(ingest)
	manual.apply_cmdline(PackedStringArray(["--latency-test"]))
	manual.toggle_armed()
	manual.toggle_armed()
	if manual.armed or manual.arm_on_first_sample:
		_fail("Manual F4 toggling did not cancel auto-arm")
		return
	ingest.sample_received.emit(_sample(3, Vector3(0.0, 8.0, 0.0)))
	await process_frame
	if manual.armed:
		_fail("Sample re-armed a stimulus the operator disarmed")
		return

	var plain := _stimulus(ingest)
	plain.apply_cmdline(PackedStringArray([]))
	ingest.sample_received.emit(_sample(4, Vector3(0.0, 8.0, 0.0)))
	await process_frame
	if plain.armed or plain.arm_on_first_sample:
		_fail("Stimulus armed without --latency-test")
		return

	print("TMB-023_LATENCY_AUTO_ARM_OK qr_visible_until_sample=true manual_override=true")
	quit(0)


func _stimulus(ingest: Node) -> Node:
	var stimulus := Stimulus.new()
	root.add_child(stimulus)
	stimulus.bind(ingest)
	stimulus.cooldown_ms = 0
	stimulus.set_threshold(4.0)
	stimulus.stimulus_triggered.connect(func(record: Dictionary) -> void:
		records.append(record)
	)
	return stimulus


func _sample(sequence: int, gyro: Vector3) -> Dictionary:
	var now := Time.get_ticks_usec() * 1000
	return {
		"controller_id": 1,
		"sequence": sequence,
		"sensor_monotonic_ns": now - 2_000_000,
		"adjusted_host_monotonic_ns": now - 2_000_000,
		"arrival_monotonic_ns": now - 1_000_000,
		"angular_velocity": [gyro.x, gyro.y, gyro.z],
	}


func _wait_for_records(count: int) -> void:
	var deadline := Time.get_ticks_msec() + 1000
	while records.size() < count and Time.get_ticks_msec() < deadline:
		await process_frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
