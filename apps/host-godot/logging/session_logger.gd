class_name SessionLogger
extends Node

signal log_limit_reached(path: String)

const SCHEMA_VERSION := 1

@export var enabled := true
@export var maximum_bytes := 10 * 1024 * 1024
@export var flush_interval_ms := 1000
@export var log_directory := "user://logs"

var _file: FileAccess
var _path := ""
var _session_id := ""
var _last_flush_ms := 0
var _records_written := 0
var _limit_reached := false


func _ready() -> void:
	set_process(false)


func start(session_id: String, metadata := {}, path_override := "") -> Error:
	close()
	_session_id = session_id
	_records_written = 0
	_limit_reached = false
	if not enabled:
		return OK
	if session_id.is_empty() or maximum_bytes < 1024:
		return ERR_INVALID_PARAMETER

	if path_override.is_empty():
		var absolute_directory := ProjectSettings.globalize_path(log_directory)
		var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
		if directory_error != OK:
			return directory_error
		var timestamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
		_path = absolute_directory.path_join("session-%s-%s.jsonl" % [timestamp, session_id])
	else:
		_path = ProjectSettings.globalize_path(path_override)
		var parent_error := DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
		if parent_error != OK:
			return parent_error

	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_last_flush_ms = Time.get_ticks_msec()
	set_process(true)
	return _write({
		"record_type": "session_header",
		"schema_version": SCHEMA_VERSION,
		"session_id": session_id,
		"started_unix_ms": Time.get_unix_time_from_system() * 1000.0,
		"host_monotonic_ns": Time.get_ticks_usec() * 1000,
		"application": {
			"name": ProjectSettings.get_setting("application/config/name", "unknown"),
			"version": ProjectSettings.get_setting("application/config/version", "unknown"),
			"godot": Engine.get_version_info().string,
		},
		"protocol_version": 1,
		"host": {
			"os": OS.get_name(),
			"os_version": OS.get_version(),
			"model": OS.get_model_name(),
		},
		"metadata": metadata,
		"privacy": "motion/network engineering data only; no audio, video, or account data",
	})


func attach(ingest: MotionIngest) -> void:
	if not ingest.packet_observed.is_connected(log_packet):
		ingest.packet_observed.connect(log_packet)
	if not ingest.calibration_received.is_connected(log_calibration):
		ingest.calibration_received.connect(log_calibration)


## Records each accepted CALIBRATION so physical runs can check repeatability.
## Fields are allow-listed; vectors are written as plain numeric arrays.
func log_calibration(controller_id: int, calibration: Dictionary) -> void:
	log_event("calibration", {
		"controller_id": controller_id,
		"handedness": str(calibration.get("handedness", "")),
		"neutral_orientation": _number_array(calibration.get("neutral_orientation", [])),
		"acceleration_bias": _number_array(calibration.get("acceleration_bias", [])),
		"gyroscope_bias": _number_array(calibration.get("gyroscope_bias", [])),
		"quality": float(calibration.get("quality", 0.0)),
		"sensor_monotonic_ns": int(calibration.get("sensor_monotonic_ns", 0)),
	})


static func _number_array(value: Variant) -> Array:
	var result: Array = []
	match typeof(value):
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			for component in value:
				result.append(float(component))
		TYPE_VECTOR3:
			result = [value.x, value.y, value.z]
		TYPE_QUATERNION:
			result = [value.x, value.y, value.z, value.w]
	return result


func log_packet(packet_record: Dictionary) -> void:
	if not is_open():
		return
	var record := packet_record.duplicate(true)
	record["record_type"] = "packet"
	record["schema_version"] = SCHEMA_VERSION
	record["session_id"] = _session_id
	_write(record)


func log_event(event_name: String, fields := {}) -> void:
	if not is_open():
		return
	var record := fields.duplicate(true)
	record["record_type"] = "event"
	record["schema_version"] = SCHEMA_VERSION
	record["session_id"] = _session_id
	record["event"] = event_name
	record["host_monotonic_ns"] = Time.get_ticks_usec() * 1000
	_write(record)


func flush() -> void:
	if _file != null:
		_file.flush()
		_last_flush_ms = Time.get_ticks_msec()


func close() -> void:
	set_process(false)
	if _file != null:
		_file.flush()
		_file.close()
	_file = null


func is_open() -> bool:
	return enabled and _file != null and not _limit_reached


func path() -> String:
	return _path


func records_written() -> int:
	return _records_written


func reached_limit() -> bool:
	return _limit_reached


func _process(_delta: float) -> void:
	if _file != null and Time.get_ticks_msec() - _last_flush_ms >= flush_interval_ms:
		flush()


func _exit_tree() -> void:
	close()


func _write(record: Dictionary) -> Error:
	if not is_open():
		return ERR_UNAVAILABLE
	var line := JSON.stringify(record)
	var encoded_size := line.to_utf8_buffer().size() + 1
	if _file.get_position() + encoded_size > maximum_bytes:
		_limit_reached = true
		_file.flush()
		_file.close()
		_file = null
		set_process(false)
		log_limit_reached.emit(_path)
		return ERR_FILE_CANT_WRITE
	_file.store_line(line)
	_records_written += 1
	return OK
