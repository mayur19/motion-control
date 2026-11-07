class_name CapturePanel
extends PanelContainer

## TMB-029 capture controls (F6). Starts/stops a MotionCapture fed by
## MotionIngest.datagram_accepted and records labeled takes. Labels are
## written to labels.jsonl only; raw datagrams are never relabeled.

const Capture = preload("res://capture/motion_capture.gd")
const PHONES := ["iPhone", "Galaxy", "Pixel"]
const SWING_SHOTS := ["smash", "clear", "drop", "lift", "other_swing"]
const WIDTH := 300.0
const HEIGHT := 430.0
const MARGIN := 16.0
const COLOR_PANEL := Color("1a2636")
const COLOR_TEXT := Color("edf5ff")
const COLOR_RECORDING := Color("ef6a70")

@export var capture_root := "user://captures"

var _capture := Capture.new()
var _ingest: MotionIngest
var _status: Label
var _capture_button: Button
var _take_button: Button
var _player: OptionButton
var _phone: OptionButton
var _hand: OptionButton
var _shot: OptionButton
var _valid: CheckBox
var _speed: OptionButton
var _swings: SpinBox
var _status_text := "Not capturing"


func _ready() -> void:
	visible = false
	_build()
	set_process_unhandled_key_input(true)


## Closing the host finishes an open capture so raw.sha256 is always written.
func _exit_tree() -> void:
	if _capture.is_recording():
		_capture.stop(_now(-1))


func place_as_overlay() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -WIDTH - MARGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + HEIGHT
	z_index = 11


func bind_ingest(ingest: MotionIngest) -> void:
	_ingest = ingest
	if not ingest.datagram_accepted.is_connected(_capture.record_datagram):
		ingest.datagram_accepted.connect(_capture.record_datagram)


func is_capturing() -> bool:
	return _capture.is_recording()


func status_text() -> String:
	return _status_text


func set_labels(labels: Dictionary) -> void:
	_select(_player, "P%d" % int(labels.get("player", 1)))
	_select(_phone, str(labels.get("phone", PHONES[0])))
	_select(_hand, str(labels.get("handedness", "right")))
	_select(_shot, str(labels.get("intended_shot", "smash")))
	_valid.button_pressed = bool(labels.get("valid", true))
	_select(_speed, str(labels.get("speed", "none")))
	_swings.value = int(labels.get("swing_count", 0))
	_sync_shot_controls()


func current_labels() -> Dictionary:
	return {
		"player": _player.selected + 1,
		"phone": _phone.get_item_text(_phone.selected),
		"handedness": _hand.get_item_text(_hand.selected),
		"intended_shot": _shot.get_item_text(_shot.selected),
		"valid": _valid.button_pressed,
		"speed": _speed.get_item_text(_speed.selected),
		"swing_count": int(_swings.value),
	}


func toggle_capture(now_ns := -1) -> Dictionary:
	var now := _now(now_ns)
	if _capture.is_recording():
		if not _capture.open_take().is_empty():
			var label_error := _end_label_error()
			if not label_error.is_empty():
				_set_status(label_error)
				return {"ok": false, "error": label_error}
			var ended := _capture.end_take(now, current_labels())
			if not bool(ended.ok):
				_set_status("End take failed: %s" % str(ended.get("error", "")))
				return ended
		var stopped := _capture.stop(now)
		_set_status(
			"Saved %d datagrams: %s" % [int(stopped.get("datagrams", 0)), _capture.capture_id()]
			if bool(stopped.ok) else "Stop failed: %s" % str(stopped.get("error", ""))
		)
		_refresh()
		return stopped
	var seed: Array[Dictionary] = _ingest.calibration_seed() if _ingest != null else []
	var started := _capture.start(capture_root, {"source": "host capture panel"}, seed)
	_set_status("Recording %s" % _capture.capture_id() if started == OK else "Start failed: %s" % error_string(started))
	_refresh()
	if started == OK:
		_reset_take_fields()
		visible = false  # expose the pairing QR; capture continues in the background
	return {"ok": started == OK}


func toggle_take(now_ns := -1) -> Dictionary:
	var now := _now(now_ns)
	if not _capture.open_take().is_empty():
		var label_error := _end_label_error()
		if not label_error.is_empty():
			_set_status(label_error)
			return {"ok": false, "error": label_error}
		var ended := _capture.end_take(now, current_labels())
		_set_status("Take %d saved" % int(ended.get("take_id", 0)))
		if bool(ended.ok):
			_reset_take_fields()
		_refresh()
		return ended
	var begun := _capture.begin_take(current_labels(), now)
	_set_status(
		"Take %d recording" % int(begun.take_id) if bool(begun.ok) else "Take rejected: %s" % str(begun.error)
	)
	_refresh()
	return begun


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		visible = not visible
		if is_inside_tree() and get_viewport() != null:
			get_viewport().set_input_as_handled()


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	box.add_child(_label("MOTION CAPTURE (F6)"))
	_status = _label(_status_text)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_capture_button = Button.new()
	_capture_button.pressed.connect(func() -> void: toggle_capture())
	box.add_child(_capture_button)
	_player = _options(box, "Player", ["P1", "P2"])
	_phone = _options(box, "Phone", PHONES)
	_hand = _options(box, "Hand", Capture.HANDEDNESS)
	_shot = _options(box, "Intended shot", Capture.SHOTS)
	_shot.item_selected.connect(func(_index: int) -> void: _sync_shot_controls())
	_speed = _options(box, "Speed", Capture.SPEEDS)
	var swings_row := HBoxContainer.new()
	var swings_caption := _label("Swings in take")
	swings_caption.custom_minimum_size = Vector2(110, 0)
	swings_row.add_child(swings_caption)
	_swings = SpinBox.new()
	_swings.min_value = 0
	_swings.max_value = Capture.MAX_SWINGS_PER_TAKE
	_swings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swings_row.add_child(_swings)
	box.add_child(swings_row)
	_valid = CheckBox.new()
	_valid.text = "Valid take"
	_valid.button_pressed = true
	box.add_child(_valid)
	_take_button = Button.new()
	_take_button.pressed.connect(func() -> void: toggle_take())
	box.add_child(_take_button)
	_refresh()
	_sync_shot_controls()


func _options(box: VBoxContainer, title: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	var caption := _label(title)
	caption.custom_minimum_size = Vector2(110, 0)
	row.add_child(caption)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		option.add_item(str(item))
	row.add_child(option)
	box.add_child(row)
	return option


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _select(option: OptionButton, text: String) -> void:
	for index in option.item_count:
		if option.get_item_text(index) == text:
			option.select(index)
			return


func _sync_shot_controls() -> void:
	if _shot == null or _speed == null or _swings == null:
		return
	var is_swing := SWING_SHOTS.has(_shot.get_item_text(_shot.selected))
	if not is_swing:
		_select(_speed, "none")
		_swings.value = 0
	_speed.disabled = not is_swing
	_swings.editable = is_swing


func _reset_take_fields() -> void:
	_select(_speed, "none")
	_swings.value = 0
	_valid.button_pressed = true
	_sync_shot_controls()


func _end_label_error() -> String:
	var labels := current_labels()
	if bool(labels.valid) and SWING_SHOTS.has(str(labels.intended_shot)) \
			and (str(labels.speed) == "none" or int(labels.swing_count) <= 0):
		return "Set speed and swing count before END TAKE"
	return ""


func _refresh() -> void:
	if _capture_button == null:
		return
	var recording := _capture.is_recording()
	_capture_button.text = "STOP CAPTURE" if recording else "START CAPTURE"
	_take_button.disabled = not recording
	_take_button.text = "END TAKE" if not _capture.open_take().is_empty() else "BEGIN TAKE"
	_status.add_theme_color_override("font_color", COLOR_RECORDING if recording else COLOR_TEXT)


func _set_status(text: String) -> void:
	_status_text = text
	if _status != null:
		_status.text = text


func _now(now_ns: int) -> int:
	return now_ns if now_ns >= 0 else Time.get_ticks_usec() * 1000
