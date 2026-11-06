class_name DiagnosticsHUD
extends PanelContainer

const HudSlots = preload("res://ui/hud_slots.gd")

const Graph = preload("res://ui/motion_signal_graph.gd")
const COLOR_PANEL := Color("1a2636")
const COLOR_BORDER := Color("30445e")
const COLOR_TEXT := Color("edf5ff")
const COLOR_MUTED := Color("9fb0c5")
const COLOR_LIVE := Color("54d6a7")
const COLOR_STALE := Color("f6b85f")
const COLOR_DISCONNECTED := Color("ef6a70")

var _ingest: MotionIngest
var _cards: Array[Dictionary] = []
var _controller_slots: Dictionary = {}
var _refresh_accumulator := 0.0
var _connection_manager: ControllerConnectionManager


func _ready() -> void:
	_build()
	set_process(true)
	set_process_unhandled_key_input(true)


func bind_ingest(ingest: MotionIngest) -> void:
	_ingest = ingest
	if not ingest.sample_received.is_connected(_on_sample_received):
		ingest.sample_received.connect(_on_sample_received)


func bind_connection_manager(connection_manager: ControllerConnectionManager) -> void:
	_connection_manager = connection_manager


func refresh_now() -> void:
	if _ingest == null:
		return
	var snapshot := _ingest.snapshot()
	if _connection_manager != null:
		_controller_slots = HudSlots.assign(
			snapshot.controllers.keys(), _connection_manager.snapshot()
		)
	for raw_controller_id in snapshot.controllers:
		var controller_id := int(raw_controller_id)
		var slot := _slot_for(controller_id)
		if slot >= 0:
			_update_card(_cards[slot], controller_id, snapshot.controllers[raw_controller_id])
	for slot in _cards.size():
		if not _controller_slots.values().has(slot):
			_show_disconnected(_cards[slot])


func graph_history_sizes() -> Array[int]:
	var result: Array[int] = []
	for card in _cards:
		result.append(card.graph.history_size())
	return result


func _process(delta: float) -> void:
	_refresh_accumulator += delta
	if _refresh_accumulator >= 0.1:
		_refresh_accumulator = 0.0
		refresh_now()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _on_sample_received(sample: Dictionary) -> void:
	var slot := _slot_for(int(sample.controller_id))
	if slot < 0:
		return
	_cards[slot].graph.push_sample(sample.acceleration, sample.angular_velocity)


func _slot_for(controller_id: int) -> int:
	if _controller_slots.has(controller_id):
		return int(_controller_slots[controller_id])
	if _connection_manager != null:
		return -1  # Cards follow assigned players; see HudSlots.
	if _controller_slots.size() >= 2:
		return -1
	var slot := _controller_slots.size()
	_controller_slots[controller_id] = slot
	return slot


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_top = 12
	style.content_margin_right = 16
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var title := _label("NETWORK DIAGNOSTICS", 14, COLOR_MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_label("F3  SHOW / HIDE", 11, COLOR_MUTED))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for player in [1, 2]:
		var card := _create_card(player)
		_cards.append(card)
		grid.add_child(card.root)


func _create_card(player: int) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	root.add_child(header)
	var player_label := _label("PLAYER %d" % player, 14, COLOR_TEXT)
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(player_label)
	var status := _label("DISCONNECTED", 12, COLOR_DISCONNECTED)
	header.add_child(status)
	var endpoint := _label("No controller endpoint", 11, COLOR_MUTED)
	root.add_child(endpoint)
	var metric_grid := GridContainer.new()
	metric_grid.columns = 6
	metric_grid.add_theme_constant_override("h_separation", 8)
	root.add_child(metric_grid)
	var values := {}
	for metric in ["HZ", "LOSS", "DUP", "REORDER", "JITTER", "AGE"]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 1)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(_label(metric, 9, COLOR_MUTED))
		var value := _label("—", 13, COLOR_TEXT)
		column.add_child(value)
		metric_grid.add_child(column)
		values[metric] = value
	var legend := _label("ACCEL", 9, Graph.ACCEL)
	legend.text += "   /   GYRO"
	legend.add_theme_color_override("font_shadow_color", Graph.GYRO)
	root.add_child(legend)
	var graph := Graph.new()
	root.add_child(graph)
	return {
		"root": root,
		"status": status,
		"endpoint": endpoint,
		"values": values,
		"graph": graph,
	}


func _update_card(card: Dictionary, controller_id: int, metrics: Dictionary) -> void:
	var age := float(metrics.last_packet_age_ms)
	card.endpoint.text = "%s  •  controller %08X" % [metrics.endpoint, controller_id]
	card.values.HZ.text = "%d" % int(metrics.packet_hz)
	card.values.LOSS.text = "%d" % int(metrics.loss)
	card.values.DUP.text = "%d" % int(metrics.duplicates)
	card.values.REORDER.text = "%d" % int(metrics.reordered)
	card.values.JITTER.text = "%.1f" % float(metrics.jitter_ms)
	card.values.AGE.text = "%.0fms" % age
	if _connection_manager != null:
		var connection := _connection_manager.state_for(controller_id)
		match str(connection.state):
			"Connected": _set_status(card, "CONNECTED", COLOR_LIVE)
			"Degraded": _set_status(card, "DEGRADED", COLOR_STALE)
			"Reconnecting": _set_status(card, "RECONNECTING", COLOR_STALE)
			"Paused": _set_status(card, "PAUSED", COLOR_STALE)
			_: _set_status(card, "DISCONNECTED", COLOR_DISCONNECTED)
	elif age > 1000.0:
		_set_status(card, "DISCONNECTED", COLOR_DISCONNECTED)
	elif age > 100.0:
		_set_status(card, "STALE", COLOR_STALE)
	else:
		_set_status(card, "LIVE", COLOR_LIVE)


func _show_disconnected(card: Dictionary) -> void:
	_set_status(card, "DISCONNECTED", COLOR_DISCONNECTED)


func _set_status(card: Dictionary, text: String, color: Color) -> void:
	card.status.text = text
	card.status.add_theme_color_override("font_color", color)


func _label(text: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result
