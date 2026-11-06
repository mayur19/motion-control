class_name NormalizationPlot
extends Control

## TMB-028 debug view (F5): rolling raw native-frame angular velocity beside
## the same samples normalized into the common racket frame, for the most
## recently calibrated controller. Only calibrated samples are plotted.

const HISTORY := 240
const RAW := "raw"
const NORMALIZED := "normalized"
const AXIS_COLORS := [Color("ef6a70"), Color("54d6a7"), Color("6aa8ff")]
const AXIS_NAMES := ["X", "Y", "Z"]
const BACKGROUND := Color("111a25")
const GRID := Color("2a3a4d")
const TEXT := Color("9fb0c5")
const MIN_SCALE_RAD_S := 2.0
const PANEL_GAP := 12.0
const OVERLAY_HEIGHT := 220.0
const OVERLAY_MARGIN := 16.0

## controller_id -> {raw: [Array x3], normalized: [Array x3]}
var _history: Dictionary = {}
var _latest_controller := -1


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(0, 180)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_process_unhandled_key_input(true)


## Pins the plot across the bottom of a full-window parent, above the layout,
## so the fixed 1280x720 host stack cannot push it off-screen.
func place_as_overlay() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = OVERLAY_MARGIN
	offset_right = -OVERLAY_MARGIN
	offset_top = -OVERLAY_HEIGHT - OVERLAY_MARGIN
	offset_bottom = -OVERLAY_MARGIN
	z_index = 10
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind_ingest(ingest: MotionIngest) -> void:
	if not ingest.normalized_sample_received.is_connected(_on_normalized_sample):
		ingest.normalized_sample_received.connect(_on_normalized_sample)


func history_size(controller_id: int) -> int:
	if not _history.has(controller_id):
		return 0
	return _history[controller_id][RAW][0].size()


func series(controller_id: int, kind: String, axis: int) -> Array:
	if not _history.has(controller_id):
		return []
	return _history[controller_id][kind][axis].duplicate()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		visible = not visible
		if is_inside_tree() and get_viewport() != null:
			get_viewport().set_input_as_handled()


func _on_normalized_sample(sample: Dictionary) -> void:
	var controller_id := int(sample.get("controller_id", 0))
	if not _history.has(controller_id):
		_history[controller_id] = {RAW: [[], [], []], NORMALIZED: [[], [], []]}
	var raw: Array = sample.get("angular_velocity", [])
	var normalized: Array = sample.get("normalized", {}).get("angular_velocity", [])
	if raw.size() != 3 or normalized.size() != 3:
		return
	for axis in 3:
		_append(_history[controller_id][RAW][axis], float(raw[axis]))
		_append(_history[controller_id][NORMALIZED][axis], float(normalized[axis]))
	_latest_controller = controller_id
	if visible:
		queue_redraw()


func _append(values: Array, value: float) -> void:
	values.append(value)
	if values.size() > HISTORY:
		values.pop_front()


func _draw() -> void:
	var panel_width := (size.x - PANEL_GAP) / 2.0
	var panels := {
		RAW: Rect2(Vector2.ZERO, Vector2(panel_width, size.y)),
		NORMALIZED: Rect2(Vector2(panel_width + PANEL_GAP, 0), Vector2(panel_width, size.y)),
	}
	var titles := {RAW: "RAW gyro (device frame)", NORMALIZED: "NORMALIZED gyro (racket frame)"}
	var range_rad_s := _range()
	for kind in panels:
		var rect: Rect2 = panels[kind]
		draw_rect(rect, BACKGROUND)
		var mid_y := rect.position.y + rect.size.y / 2.0
		draw_line(Vector2(rect.position.x, mid_y), Vector2(rect.end.x, mid_y), GRID)
		var font := get_theme_default_font()
		draw_string(font, rect.position + Vector2(8, 16), "%s  ±%.1f rad/s" % [titles[kind], range_rad_s],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT)
		if _latest_controller < 0:
			continue
		for axis in 3:
			_draw_series(rect, _history[_latest_controller][kind][axis], range_rad_s, AXIS_COLORS[axis])
			draw_string(font, rect.position + Vector2(8 + axis * 22, rect.size.y - 8), AXIS_NAMES[axis],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, AXIS_COLORS[axis])


func _draw_series(rect: Rect2, values: Array, range_rad_s: float, color: Color) -> void:
	if values.size() < 2:
		return
	var points := PackedVector2Array()
	var step := rect.size.x / float(HISTORY - 1)
	var offset := HISTORY - values.size()
	for index in values.size():
		var y := rect.position.y + rect.size.y / 2.0 - (float(values[index]) / range_rad_s) * (rect.size.y / 2.0 - 20.0)
		points.append(Vector2(rect.position.x + (offset + index) * step, clampf(y, rect.position.y, rect.end.y)))
	draw_polyline(points, color, 1.5)


func _range() -> float:
	var maximum := MIN_SCALE_RAD_S
	if _latest_controller >= 0:
		for kind in [RAW, NORMALIZED]:
			for axis in 3:
				for value in _history[_latest_controller][kind][axis]:
					maximum = maxf(maximum, absf(float(value)))
	return maximum
