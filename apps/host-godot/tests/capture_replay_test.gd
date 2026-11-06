extends SceneTree

const Codec = preload("res://protocol/protocol_v1.gd")
const Capture = preload("res://capture/motion_capture.gd")
const Replayer = preload("res://replay/capture_replayer.gd")
const Ingest = preload("res://network/motion_ingest.gd")
const Pipeline = preload("res://detection/detector_pipeline.gd")

const ENDPOINT := "192.0.2.7:6000"
## Real session ids are random u64s; both exceed 2^53 (JSON float precision)
## and the second has the top bit set (negative as a GDScript int).
const SESSION_A := 0x18A61FF985F6AFD4
const SESSION_B := -0x2E5B1C0A7F3D9E11


class FakeSessions:
	extends RefCounted
	var current_session := {"session_id": SESSION_A}


const CONFIG := {"detector": "early_rise", "onset_speed_rad_s": 3.0, "min_rise_rad_s2": 20.0}


func _initialize() -> void:
	var packets := _packets()

	# Live: capture what the ingest accepts while the live pipeline runs.
	var ingest := Ingest.new()
	root.add_child(ingest)
	var live := Pipeline.new()
	live.configure(CONFIG)
	live.bind_ingest(ingest)
	var live_events: Array[Dictionary] = []
	live.event_detected.connect(func(event: Dictionary): live_events.append(event))
	var capture := Capture.new()
	if capture.start(_root_dir(), {"purpose": "replay test"}) != OK:
		return _fail("capture start failed")
	ingest.datagram_accepted.connect(capture.record_datagram)
	var arrival := 1_000_000_000
	capture.begin_take({"player": 1, "phone": "iPhone", "handedness": "right",
		"intended_shot": "smash", "valid": true}, arrival + 50_000_000)
	for packet in packets:
		ingest.ingest_datagram(packet, ENDPOINT, arrival)
		arrival += 10_000_000
	var stopped := capture.stop(arrival)
	if live_events.is_empty():
		return _fail("Fixture swing produced no live events")

	var replayer := Replayer.new()
	var series_path: String = str(stopped.directory).get_base_dir().path_join("series.jsonl")
	var with_series := replayer.replay(stopped.directory, CONFIG, series_path)
	var series_lines := FileAccess.get_file_as_string(series_path).split("\n", false)
	if not bool(with_series.ok) or series_lines.size() != int(with_series.totals.normalized_samples):
		return _fail("Series export must hold one line per normalized sample: %d" % series_lines.size())
	var row: Dictionary = JSON.parse_string(series_lines[10])
	if not row.has("normalized_angular_speed") or not row.has("preprocessed_angular_speed") \
			or not row.has("normalized_acceleration") or not row.has("preprocessed_acceleration") \
			or not row.has("arrival_monotonic_ns"):
		return _fail("Series row incomplete: %s" % str(row))
	var default_run := replayer.replay(stopped.directory, Pipeline.DEFAULTS)
	if not bool(default_run.ok) or str(default_run.detector.detector) != "early_rise" \
			or not default_run.takes[0].has("take_id") or int(default_run.takes[0].event_count) != default_run.events.size():
		return _fail("Replay with the default detector must summarize takes: %s" % str(default_run.takes))
	var first := replayer.replay(stopped.directory, CONFIG)
	var second := replayer.replay(stopped.directory, CONFIG)
	if not bool(first.ok):
		return _fail("Replay failed: %s" % str(first))
	if JSON.stringify(first) != JSON.stringify(second):
		return _fail("Replay is not repeatable")
	if JSON.stringify(first.events) != JSON.stringify(live_events):
		return _fail("Replay events differ from live: %s vs %s" % [str(first.events), str(live_events)])
	if str(first.raw_sha256) != str(stopped.raw_sha256) or not bool(first.raw_verified):
		return _fail("Replay must verify the raw checksum")
	if str(first.detector.detector) != "early_rise" or float(first.detector.config.onset_speed_rad_s) != 3.0:
		return _fail("Replay result must embed detector config: %s" % str(first.detector))
	var take: Dictionary = first.takes[0]
	if str(take.labels.intended_shot) != "smash" or int(take.event_count) != live_events.size() \
			or int(take.normalized_samples) <= 0 or float(take.peak_angular_speed_rad_s) < 3.0:
		return _fail("Take summary wrong: %s" % str(take))
	if int(first.totals.datagrams) != packets.size() or int(first.totals.events) != live_events.size():
		return _fail("Totals wrong: %s" % str(first.totals))

	# Label correction: append revision 2; raw stays byte-identical.
	var labels := FileAccess.open(stopped.directory.path_join("labels.jsonl"), FileAccess.READ_WRITE)
	labels.seek_end()
	var corrected: Dictionary = take.labels.duplicate(true)
	corrected.merge({"record": "take", "take_id": int(take.take_id), "revision": 2,
		"intended_shot": "clear", "start_arrival_ns": int(take.start_arrival_ns),
		"end_arrival_ns": int(take.end_arrival_ns)}, true)
	labels.store_line(JSON.stringify(corrected))
	labels.close()
	var relabeled := replayer.replay(stopped.directory, CONFIG)
	if str(relabeled.takes[0].labels.intended_shot) != "clear" or int(relabeled.takes[0].label_revision) != 2:
		return _fail("Latest label revision not used: %s" % str(relabeled.takes[0]))
	if str(relabeled.raw_sha256) != str(stopped.raw_sha256):
		return _fail("Relabeling changed raw data")

	# Tampering with raw motion must be refused.
	var raw := FileAccess.open(stopped.directory.path_join("raw.jsonl"), FileAccess.READ_WRITE)
	raw.seek_end()
	raw.store_line("{\"record\":\"datagram\"}")
	raw.close()
	var tampered := replayer.replay(stopped.directory, CONFIG)
	if bool(tampered.ok) or not str(tampered.error).contains("checksum"):
		return _fail("Tampered capture was not refused: %s" % str(tampered))

	var late := await _capture_started_after_calibration(packets)
	if not late.is_empty():
		return _fail(late)

	print("TMB-029_REPLAY_OK events=%d live_equal=true repeatable=true relabel=true tamper_refused=true" % live_events.size())
	quit(0)


## Normal flow: phones calibrate, then the operator starts the capture; the
## session later rotates while a stale-session packet still arrives.
func _capture_started_after_calibration(packets: Array[PackedByteArray]) -> String:
	var ingest := Ingest.new()
	root.add_child(ingest)
	var sessions := FakeSessions.new()
	ingest.set_session_manager(sessions)
	var live := Pipeline.new()
	live.configure(CONFIG)
	live.bind_ingest(ingest)
	var live_events: Array[Dictionary] = []
	live.event_detected.connect(func(event: Dictionary): live_events.append(event))
	var live_normalized := [0]
	ingest.normalized_sample_received.connect(func(_sample: Dictionary): live_normalized[0] += 1)
	var arrival := 5_000_000_000
	ingest.ingest_datagram(packets[0], ENDPOINT, arrival)  # calibration, before capture
	var capture := Capture.new()
	if capture.start(_root_dir(), {}, ingest.calibration_seed()) != OK:
		return "late capture start failed"
	ingest.datagram_accepted.connect(capture.record_datagram)
	for index in range(1, packets.size()):
		arrival += 10_000_000
		if index == packets.size() / 2:
			sessions.current_session = {"session_id": SESSION_B}  # NEW PAIRING CODE mid-swing
		ingest.ingest_datagram(packets[index], ENDPOINT, arrival)
	var stopped := capture.stop(arrival)
	var result := Replayer.new().replay(stopped.directory, CONFIG)
	if not bool(result.ok):
		return "late replay failed: %s" % str(result)
	if int(result.totals.normalized_samples) == 0:
		return "Capture started after calibration replayed with no normalized samples"
	if int(result.totals.normalized_samples) != int(live_normalized[0]):
		return "Replay normalized %d samples, live %d (session gate differs)" % [
			int(result.totals.normalized_samples), int(live_normalized[0])]
	if JSON.stringify(result.events) != JSON.stringify(live_events):
		return "Late-start/rotation replay differs from live: %s vs %s" % [str(result.events), str(live_events)]
	return ""


func _packets() -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	result.append(_encode(Codec.TYPE_CALIBRATION, 0, {
		"message_type": Codec.TYPE_CALIBRATION, "sensor_monotonic_ns": 500_000_000,
		"neutral_orientation": [0.0, 0.0, 0.0, 1.0], "acceleration_bias": [0.0, 0.0, 0.0],
		"gyroscope_bias": [0.0, 0.0, 0.0], "quality": 0.9, "result": 1, "handedness": 1,
	}))
	for index in 60:
		var t := float(index) / 59.0
		var speed := 6.0 * sin(PI * t)
		result.append(_encode(Codec.TYPE_MOTION, index + 1, {
			"message_type": Codec.TYPE_MOTION,
			"sensor_monotonic_ns": 600_000_000 + index * 10_000_000,
			"acceleration": [0.0, speed, 0.0],
			"angular_velocity": [speed, 0.0, 0.0],
			"orientation": [0.0, 0.0, 0.0, 1.0],
			"accuracy": 3,
			"sensor_flags": 7,
		}))
	return result


func _encode(message_type: int, sequence: int, payload: Dictionary) -> PackedByteArray:
	var encoded := Codec.encode({
		"header": {"protocol_version": Codec.VERSION, "message_type": message_type, "flags": 0,
			"session_id": SESSION_A, "controller_id": 21, "sequence": sequence},
		"payload": payload,
	})
	return encoded.data


func _root_dir() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=").get_base_dir().path_join("replay-test")
	return OS.get_user_data_dir().path_join("replay-test")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
