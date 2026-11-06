class_name RawLatencyStimulus
extends ColorRect

signal stimulus_triggered(record: Dictionary)

const COLOR_A := Color("ffffff")
const COLOR_B := Color("101010")

@export var threshold_rad_s := 3.5
@export var cooldown_ms := 700

var armed := false:
	set(value):
		armed = value
		visible = value
		_update_label()

var _logger: SessionLogger
var _pending := false
var _last_trigger_ms: Dictionary = {}
var _phase := false
var _label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	visible = armed
	_build_label()
	set_process_unhandled_key_input(true)


func bind(ingest: MotionIngest, logger: SessionLogger = null) -> void:
	_logger = logger
	if not ingest.sample_received.is_connected(_on_sample_received):
		ingest.sample_received.connect(_on_sample_received)


func set_threshold(value: float) -> void:
	threshold_rad_s = clampf(value, 0.25, 50.0)
	_update_label()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F4:
			armed = not armed
		KEY_BRACKETLEFT, KEY_MINUS:
			set_threshold(threshold_rad_s - 0.25)
		KEY_BRACKETRIGHT, KEY_EQUAL:
			set_threshold(threshold_rad_s + 0.25)
		_:
			return
	get_viewport().set_input_as_handled()


func _on_sample_received(sample: Dictionary) -> void:
	if not armed or _pending:
		return
	var magnitude := _magnitude(sample.get("angular_velocity", []))
	if magnitude < threshold_rad_s:
		return
	var controller_id := int(sample.controller_id)
	var now_ms := Time.get_ticks_msec()
	if now_ms - int(_last_trigger_ms.get(controller_id, -cooldown_ms)) < cooldown_ms:
		return
	_last_trigger_ms[controller_id] = now_ms
	_pending = true
	var record := {
		"controller_id": controller_id,
		"sequence": int(sample.sequence),
		"sensor_monotonic_ns": int(sample.sensor_monotonic_ns),
		"adjusted_sample_monotonic_ns": int(sample.get("adjusted_host_monotonic_ns", 0)),
		"arrival_monotonic_ns": int(sample.arrival_monotonic_ns),
		"threshold_monotonic_ns": Time.get_ticks_usec() * 1000,
		"threshold_rad_s": threshold_rad_s,
		"measured_rad_s": magnitude,
	}
	call_deferred("_commit_stimulus", record)


func _commit_stimulus(record: Dictionary) -> void:
	record["simulation_marker_monotonic_ns"] = Time.get_ticks_usec() * 1000
	_phase = not _phase
	color = COLOR_A if _phase else COLOR_B
	_update_label()
	# The color mutation is queued immediately; this marker is the next process
	# frame boundary at which the renderer can present it. Camera testing remains
	# the authority for the physical display transition.
	await get_tree().process_frame
	record["render_marker_monotonic_ns"] = Time.get_ticks_usec() * 1000
	record["software_sample_to_render_ms"] = (
		(int(record.render_marker_monotonic_ns) - int(record.adjusted_sample_monotonic_ns))
		/ 1_000_000.0
		if int(record.adjusted_sample_monotonic_ns) > 0
		else -1.0
	)
	if _logger != null:
		_logger.log_event("raw_latency_stimulus", record)
	stimulus_triggered.emit(record.duplicate(true))
	_pending = false


func _build_label() -> void:
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 42)
	_label.add_theme_color_override("font_color", Color("ff3b30"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	add_child(_label)
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	_label.text = (
		"RAW INPUT LATENCY\n%.2f rad/s\nF4 EXIT  [ / ] THRESHOLD" % threshold_rad_s
		if armed
		else ""
	)


## Gyro magnitude in rad/s. The protocol decoder delivers angular velocity as a
## 3-element Array; accept a Vector3 too. Malformed input yields 0 (no trigger).
static func _magnitude(value) -> float:
	if value is Vector3:
		return value.length()
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2])).length()
	return 0.0
