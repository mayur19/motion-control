extends SceneTree

const Pipeline = preload("res://detection/detector_pipeline.gd")
const Ingest = preload("res://network/motion_ingest.gd")


func _initialize() -> void:
	var pipeline := Pipeline.new()
	var bad := pipeline.configure({"detector": "angular_speed_probe", "threshold_rad_s": -1.0})
	if bool(bad.ok):
		return _fail("Negative threshold accepted")
	var configured := pipeline.configure({
		"detector": "angular_speed_probe", "threshold_rad_s": 3.0, "refractory_ms": 300,
	})
	if not bool(configured.ok):
		return _fail("Valid config rejected: %s" % str(configured))
	var description := pipeline.describe()
	if str(description.detector) != "angular_speed_probe" or int(description.version) < 1 \
			or float(description.config.threshold_rad_s) != 3.0 or int(description.config.refractory_ms) != 300:
		return _fail("describe() must report detector, version and full config: %s" % str(description))

	if str(description.get("preprocessing", {}).get("name", "")) != "one_pole_lowpass":
		return _fail("describe() must include the preprocessing stage: %s" % str(description))
	var tuned := Pipeline.new()
	if not bool(tuned.configure({"detector": "angular_speed_probe", "preprocessing": {"cutoff_hz": 30.0}}).ok) \
			or float(tuned.describe().preprocessing.config.cutoff_hz) != 30.0:
		return _fail("Preprocessing config not applied: %s" % str(tuned.describe()))
	if bool(tuned.configure({"preprocessing": {"cutoff_hz": -2.0}}).ok):
		return _fail("Invalid preprocessing config accepted")

	var events := _run(pipeline)
	# Speeds cross 3 rad/s at 100 ms and again at 300 ms (inside refractory),
	# then at 600 ms (after refractory) => two events.
	if events.size() != 2:
		return _fail("Expected 2 events, got %s" % str(events))
	if int(events[0].sensor_monotonic_ns) != 100_000_000 or int(events[1].sensor_monotonic_ns) != 600_000_000:
		return _fail("Events must carry source sample time: %s" % str(events))
	if int(events[0].controller_id) != 4 or str(events[0].detector) != "angular_speed_probe":
		return _fail("Event identity missing: %s" % str(events[0]))

	var again := Pipeline.new()
	again.configure(description.config.merged({"detector": "angular_speed_probe"}))
	if _run(again) != events:
		return _fail("Same config and input must give identical events")

	var ingest := Ingest.new()
	root.add_child(ingest)
	var live := Pipeline.new()
	live.configure({"detector": "angular_speed_probe", "threshold_rad_s": 3.0, "refractory_ms": 300})
	var live_events: Array[Dictionary] = []
	live.event_detected.connect(func(event: Dictionary): live_events.append(event))
	live.bind_ingest(ingest)
	ingest.sample_received.emit({"controller_id": 4, "sensor_monotonic_ns": 1, "angular_velocity": [9.0, 0.0, 0.0]})
	if not live_events.is_empty():
		return _fail("Pipeline must ignore raw, uncalibrated samples")
	for sample in _samples():
		ingest.normalized_sample_received.emit(sample)
	if live_events != events:
		return _fail("Live binding must produce the same events as direct processing")

	print("TMB-029_DETECTOR_PIPELINE_OK events=%d deterministic=true normalized_only=true" % events.size())
	quit(0)


func _run(pipeline) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for sample in _samples():
		events.append_array(pipeline.process(sample))
	return events


func _samples() -> Array[Dictionary]:
	var speeds := [0.5, 3.5, 1.0, 3.6, 1.0, 1.0, 3.8, 0.2]
	var result: Array[Dictionary] = []
	for index in speeds.size():
		result.append({
			"controller_id": 4,
			"sequence": index,
			"sensor_monotonic_ns": index * 100_000_000,
			"arrival_monotonic_ns": index * 100_000_000 + 5_000_000,
			"angular_velocity": [0.0, 0.0, 0.0],
			"normalized": {"angular_velocity": [speeds[index], 0.0, 0.0], "acceleration": [0.0, 0.0, 0.0]},
		})
	return result


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
