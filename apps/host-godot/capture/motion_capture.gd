class_name MotionCapture
extends RefCounted

## TMB-029 labeled motion capture (format: docs/capture-format.md).
##
## `raw.jsonl` holds accepted MOTION/CALIBRATION datagrams byte-exact with
## their host arrival time and is never rewritten; `raw.sha256` is written on
## stop. Labels live in the separate append-only `labels.jsonl`, so they can
## be corrected (new revision) without touching raw sensor values.

const FORMAT_VERSION := 1
const RAW_FILE := "raw.jsonl"
const CHECKSUM_FILE := "raw.sha256"
const LABELS_FILE := "labels.jsonl"
const HANDEDNESS := ["right", "left"]
const SHOTS := ["smash", "clear", "drop", "lift", "other_swing", "idle", "handling", "walking"]
const PLAYERS := [1, 2]

var _raw: FileAccess
var _labels: FileAccess
var _directory := ""
var _capture_id := ""
var _next_take_id := 1
var _open_take: Dictionary = {}
var _datagrams := 0


func capture_id() -> String:
	return _capture_id


func is_recording() -> bool:
	return _raw != null


func datagram_count() -> int:
	return _datagrams


func open_take() -> Dictionary:
	return _open_take.duplicate(true)


func start(root_directory: String, metadata := {}) -> Error:
	if is_recording():
		return ERR_ALREADY_IN_USE
	_capture_id = "cap_%s_%08x" % [
		Time.get_datetime_string_from_system(true).replace(":", "").replace("-", ""),
		randi(),
	]
	_directory = root_directory.path_join(_capture_id)
	var made := DirAccess.make_dir_recursive_absolute(_directory)
	if made != OK:
		return made
	_raw = FileAccess.open(_directory.path_join(RAW_FILE), FileAccess.WRITE)
	_labels = FileAccess.open(_directory.path_join(LABELS_FILE), FileAccess.WRITE)
	if _raw == null or _labels == null:
		_raw = null
		_labels = null
		return FileAccess.get_open_error()
	var header := {
		"capture_format": FORMAT_VERSION,
		"capture_id": _capture_id,
		"started_utc": Time.get_datetime_string_from_system(true),
		"host_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"metadata": _sanitized(metadata),
	}
	_write(_raw, _merged({"record": "capture_header"}, header))
	_write(_labels, {"record": "labels_header", "capture_format": FORMAT_VERSION, "capture_id": _capture_id})
	_next_take_id = 1
	_open_take = {}
	_datagrams = 0
	return OK


func record_datagram(packet: PackedByteArray, endpoint: String, arrival_ns: int) -> void:
	if not is_recording():
		return
	_write(_raw, {
		"record": "datagram",
		"arrival_monotonic_ns": arrival_ns,
		"endpoint": endpoint,
		"bytes_b64": Marshalls.raw_to_base64(packet),
	})
	_datagrams += 1


## Starts a labeled take at `now_ns` (host arrival clock), closing any open one.
func begin_take(labels: Dictionary, now_ns: int) -> Dictionary:
	if not is_recording():
		return {"ok": false, "error": "not recording"}
	var error := validate_labels(labels)
	if not error.is_empty():
		return {"ok": false, "error": error}
	if not _open_take.is_empty():
		end_take(now_ns)
	_open_take = _merged(_label_fields(labels), {"take_id": _next_take_id, "start_arrival_ns": now_ns})
	_next_take_id += 1
	return {"ok": true, "take_id": int(_open_take.take_id)}


func end_take(now_ns: int) -> Dictionary:
	if _open_take.is_empty() or not is_recording():
		return {"ok": false, "error": "no open take"}
	var record := _merged({"record": "take", "revision": 1, "end_arrival_ns": now_ns}, _open_take)
	_write(_labels, record)
	_open_take = {}
	return {"ok": true, "take_id": int(record.take_id)}


func stop(now_ns: int) -> Dictionary:
	if not is_recording():
		return {"ok": false, "error": "not recording"}
	end_take(now_ns)
	_raw.close()
	_labels.close()
	_raw = null
	_labels = null
	var raw_path := _directory.path_join(RAW_FILE)
	var digest := FileAccess.get_sha256(raw_path)
	var checksum := FileAccess.open(_directory.path_join(CHECKSUM_FILE), FileAccess.WRITE)
	if checksum == null:
		return {"ok": false, "error": "could not write checksum"}
	checksum.store_line("%s  %s" % [digest, RAW_FILE])
	checksum.close()
	return {"ok": true, "directory": _directory, "raw_sha256": digest, "datagrams": _datagrams}


static func validate_labels(labels: Dictionary) -> String:
	if not PLAYERS.has(int(labels.get("player", 0))):
		return "player must be 1 or 2"
	var phone := str(labels.get("phone", ""))
	var phone_pattern := RegEx.create_from_string("^[A-Za-z0-9 _-]{1,32}$")
	if phone_pattern.search(phone) == null:
		return "phone must be a short label (letters, digits, space, _ or -)"
	if not HANDEDNESS.has(str(labels.get("handedness", ""))):
		return "handedness must be right or left"
	if not SHOTS.has(str(labels.get("intended_shot", ""))):
		return "intended_shot must be one of %s" % ", ".join(SHOTS)
	if typeof(labels.get("valid")) != TYPE_BOOL:
		return "valid must be true or false"
	return ""


static func _label_fields(labels: Dictionary) -> Dictionary:
	return {
		"player": int(labels.player),
		"phone": str(labels.phone),
		"handedness": str(labels.handedness),
		"intended_shot": str(labels.intended_shot),
		"valid": bool(labels.valid),
	}


## Metadata is engineering context only: short scalar values, no nesting.
static func _sanitized(metadata: Dictionary) -> Dictionary:
	var result := {}
	for key in metadata:
		var value: Variant = metadata[key]
		if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
			result[str(key)] = value
		elif typeof(value) == TYPE_STRING:
			result[str(key)] = str(value).substr(0, 120)
	return result


static func _merged(first: Dictionary, second: Dictionary) -> Dictionary:
	var result := first.duplicate(true)
	result.merge(second, true)
	return result


func _write(file: FileAccess, record: Dictionary) -> void:
	file.store_line(JSON.stringify(record))
	file.flush()
