class_name CaptureReplayer
extends RefCounted

## TMB-029 offline replay: verifies a capture's raw checksum, then feeds every
## recorded datagram through a fresh MotionIngest (same codec and calibration
## normalizer as live) into a DetectorPipeline with the given configuration.
## No phone or network is needed. The result is deterministic for identical
## capture + configuration.

const Capture = preload("res://capture/motion_capture.gd")
const Ingest = preload("res://network/motion_ingest.gd")
const Pipeline = preload("res://detection/detector_pipeline.gd")
const RESULT_FORMAT := 1


## `series_path` (optional) receives one JSON line per preprocessed sample with
## normalized and preprocessed values side by side (TMB-031 before/after).
func replay(directory: String, detector_config: Dictionary, series_path := "") -> Dictionary:
	var verified := _verify_checksum(directory)
	if not bool(verified.ok):
		return verified
	var raw := _read_raw(directory)
	if not bool(raw.ok):
		return raw
	var pipeline := Pipeline.new()
	var configured := pipeline.configure(detector_config)
	if not bool(configured.ok):
		return {"ok": false, "error": "detector config: %s" % str(configured.error)}

	var events: Array[Dictionary] = []
	var speeds: Array[Dictionary] = []
	var series: FileAccess = null
	if not series_path.is_empty():
		series = FileAccess.open(series_path, FileAccess.WRITE)
		if series == null:
			return {"ok": false, "error": "cannot write series %s" % series_path}
		pipeline.sample_preprocessed.connect(func(sample: Dictionary, prepared: Dictionary):
			series.store_line(JSON.stringify(_series_row(sample, prepared)))
		)
	var ingest := Ingest.new()
	pipeline.event_detected.connect(func(event: Dictionary): events.append(event))
	pipeline.bind_ingest(ingest)
	ingest.normalized_sample_received.connect(func(sample: Dictionary):
		var omega: Array = sample.normalized.angular_velocity
		speeds.append({
			"arrival_ns": int(sample.arrival_monotonic_ns),
			"speed": Vector3(float(omega[0]), float(omega[1]), float(omega[2])).length(),
		})
	)
	for datagram in raw.datagrams:
		ingest.ingest_datagram(
			datagram.bytes, str(datagram.endpoint), int(datagram.arrival_ns), int(datagram.active_session_id)
		)
	var rejections: Dictionary = ingest.snapshot().rejections
	ingest.free()
	if series != null:
		series.close()

	var takes: Array[Dictionary] = []
	for take in effective_takes(directory):
		takes.append(_summarize_take(take, speeds, events))
	return {
		"ok": true,
		"result_format": RESULT_FORMAT,
		"capture_id": str(raw.header.get("capture_id", "")),
		"capture_format": int(raw.header.get("capture_format", 0)),
		"raw_sha256": str(verified.sha256),
		"raw_verified": true,
		"detector": pipeline.describe(),
		"totals": {
			"datagrams": raw.datagrams.size(),
			"normalized_samples": speeds.size(),
			"events": events.size(),
			"takes": takes.size(),
			"rejections": rejections,
		},
		"takes": takes,
		"events": events,
	}


static func _series_row(sample: Dictionary, prepared: Dictionary) -> Dictionary:
	var omega: Array = sample.normalized.angular_velocity
	return {
		"controller_id": int(sample.controller_id),
		"sequence": int(sample.get("sequence", 0)),
		"sensor_monotonic_ns": int(sample.sensor_monotonic_ns),
		"arrival_monotonic_ns": int(sample.arrival_monotonic_ns),
		"normalized_angular_speed": Vector3(float(omega[0]), float(omega[1]), float(omega[2])).length(),
		"preprocessed_angular_speed": float(prepared.preprocessed.angular_speed),
		"preprocessed_angular_accel": float(prepared.preprocessed.angular_accel),
		"preprocessed_angular_velocity": prepared.preprocessed.angular_velocity,
		"normalized_acceleration": sample.normalized.acceleration,
		"preprocessed_acceleration": prepared.preprocessed.acceleration,
		"gap_reset": bool(prepared.preprocessed.gap_reset),
	}


## Latest revision of every take in labels.jsonl (corrections append).
static func effective_takes(directory: String) -> Array[Dictionary]:
	var latest := {}
	var path := directory.path_join(Capture.LABELS_FILE)
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			var record: Variant = JSON.parse_string(line)
			if typeof(record) != TYPE_DICTIONARY or str(record.get("record", "")) != "take":
				continue
			var take_id := int(record.get("take_id", 0))
			if not latest.has(take_id) or int(record.get("revision", 0)) >= int(latest[take_id].get("revision", 0)):
				latest[take_id] = record
	var ids := latest.keys()
	ids.sort()
	var result: Array[Dictionary] = []
	for take_id in ids:
		result.append(latest[take_id])
	return result


func _summarize_take(take: Dictionary, speeds: Array[Dictionary], events: Array[Dictionary]) -> Dictionary:
	var start := int(take.get("start_arrival_ns", 0))
	var finish := int(take.get("end_arrival_ns", 0))
	var samples := 0
	var peak := 0.0
	for entry in speeds:
		if int(entry.arrival_ns) >= start and int(entry.arrival_ns) <= finish:
			samples += 1
			peak = maxf(peak, float(entry.speed))
	var take_events: Array[Dictionary] = []
	for event in events:
		var arrival := int(event.arrival_monotonic_ns)
		if arrival >= start and arrival <= finish:
			take_events.append(event)
	return {
		"take_id": int(take.get("take_id", 0)),
		"label_revision": int(take.get("revision", 0)),
		"labels": {
			"player": int(take.get("player", 0)),
			"phone": str(take.get("phone", "")),
			"handedness": str(take.get("handedness", "")),
			"intended_shot": str(take.get("intended_shot", "")),
			"valid": bool(take.get("valid", false)),
			"speed": str(take.get("speed", "none")),
			"swing_count": int(take.get("swing_count", 0)),
		},
		"start_arrival_ns": start,
		"end_arrival_ns": finish,
		"normalized_samples": samples,
		"peak_angular_speed_rad_s": peak,
		"event_count": take_events.size(),
		"first_event_after_start_ms": (
			(int(take_events[0].arrival_monotonic_ns) - start) / 1_000_000.0 if not take_events.is_empty() else -1.0
		),
	}


func _verify_checksum(directory: String) -> Dictionary:
	var raw_path := directory.path_join(Capture.RAW_FILE)
	var checksum_path := directory.path_join(Capture.CHECKSUM_FILE)
	if not FileAccess.file_exists(raw_path) or not FileAccess.file_exists(checksum_path):
		return {"ok": false, "error": "missing raw.jsonl or raw.sha256 checksum in %s" % directory}
	var expected := FileAccess.get_file_as_string(checksum_path).strip_edges().get_slice(" ", 0)
	var actual := FileAccess.get_sha256(raw_path)
	if expected != actual:
		return {"ok": false, "error": "raw checksum mismatch (raw motion was modified)"}
	return {"ok": true, "sha256": actual}


func _read_raw(directory: String) -> Dictionary:
	var lines := FileAccess.get_file_as_string(directory.path_join(Capture.RAW_FILE)).split("\n", false)
	if lines.is_empty():
		return {"ok": false, "error": "empty capture"}
	var header: Variant = JSON.parse_string(lines[0])
	if typeof(header) != TYPE_DICTIONARY or str(header.get("record", "")) != "capture_header":
		return {"ok": false, "error": "missing capture header"}
	if int(header.get("capture_format", 0)) != Capture.FORMAT_VERSION:
		return {"ok": false, "error": "unsupported capture_format %s" % str(header.get("capture_format"))}
	var datagrams: Array[Dictionary] = []
	for index in range(1, lines.size()):
		var record: Variant = JSON.parse_string(lines[index])
		if typeof(record) != TYPE_DICTIONARY or str(record.get("record", "")) != "datagram":
			return {"ok": false, "error": "invalid raw record on line %d" % (index + 1)}
		datagrams.append({
			"bytes": Marshalls.base64_to_raw(str(record.get("bytes_b64", ""))),
			"endpoint": str(record.get("endpoint", "")),
			"arrival_ns": int(record.get("arrival_monotonic_ns", 0)),
			"active_session_id": str(record.get("active_session_id", "0")).to_int(),
		})
	return {"ok": true, "header": header, "datagrams": datagrams}
