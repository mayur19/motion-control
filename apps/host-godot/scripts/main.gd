extends Control

const MotionIngestNode = preload("res://network/motion_ingest.gd")
const SessionLoggerNode = preload("res://logging/session_logger.gd")
const DiagnosticsHUDNode = preload("res://ui/diagnostics_hud.gd")
const SessionManagerNode = preload("res://session/session_manager.gd")
const QrCodeGeneratorNode = preload("res://addons/greaby_qrcode/qr_code.gd")
const PairingServerNode = preload("res://session/pairing_server.gd")
const PairingLogFields = preload("res://logging/pairing_log_fields.gd")
const HostClockServiceNode = preload("res://network/host_clock_service.gd")
const ConnectionManagerNode = preload("res://network/connection_manager.gd")
const HostHeartbeatNode = preload("res://network/host_heartbeat.gd")
const AwdlDetector = preload("res://session/awdl_detector.gd")
const AWDL_CHECK_INTERVAL_S := 3.0
const RawLatencyStimulusNode = preload("res://latency/raw_latency_stimulus.gd")
const SoakTelemetryNode = preload("res://logging/soak_telemetry.gd")
const COLOR_BACKGROUND := Color("101824")
const COLOR_PANEL := Color("1a2636")
const COLOR_BORDER := Color("30445e")
const COLOR_TEXT := Color("edf5ff")
const COLOR_MUTED := Color("9fb0c5")
const COLOR_ACCENT := Color("54d6a7")

var motion_ingest: MotionIngest
var session_logger: SessionLogger
var diagnostics_hud: DiagnosticsHUD
var session_manager: HostSessionManager
var qr_generator: QrCode
var session_address_label: Label
var session_interface_label: Label
var session_manual_label: Label
var session_warning_label: Label
var session_qr: TextureRect
var interface_selector: OptionButton
var pairing_server: PairingServer
var clock_service: HostClockService
var connection_manager: ControllerConnectionManager
var host_heartbeat: HostHeartbeat
var awdl_state := -1  # AwdlDetector.State; -1 until first check
var raw_latency_stimulus
var soak_telemetry


func _process(_delta: float) -> void:
	# The engineering shell has no gameplay consumer yet. Signals have already
	# delivered samples to diagnostics, latency stimulus and soak telemetry, so
	# drain the handoff queue every frame to keep long physical runs bounded.
	if motion_ingest != null:
		motion_ingest.pop_samples(512)


func _ready() -> void:
	session_manager = SessionManagerNode.new()
	add_child(session_manager)
	qr_generator = QrCodeGeneratorNode.new()
	add_child(qr_generator)
	var configured_port := int(ProjectSettings.get_setting("network/udp/listen_port", 7000))
	session_manager.start_new_session(configured_port)
	_build_interface()
	var arguments := OS.get_cmdline_user_args()
	if arguments.has("--smoke-test"):
		call_deferred("_finish_smoke_test")
		return
	_start_motion_ingest()
	_start_awdl_monitor()
	if arguments.has("--print-session"):
		print("TMB_HOST_SESSION %s" % JSON.stringify({
			"address": session_manager.current_session.address,
			"port": session_manager.current_session.port,
			"join_uri": session_manager.current_session.join_uri,
			"interface": session_manager.current_session.interface_name,
		}))
	var screenshot_path := ""
	var capture_after_packets := 0
	var capture_timeout_ms := 60_000
	for argument in arguments:
		if argument.begins_with("--capture-screenshot="):
			screenshot_path = argument.trim_prefix("--capture-screenshot=")
		elif argument.begins_with("--capture-after-packets="):
			capture_after_packets = int(argument.trim_prefix("--capture-after-packets="))
		elif argument.begins_with("--capture-timeout-ms="):
			capture_timeout_ms = int(argument.trim_prefix("--capture-timeout-ms="))
	if not screenshot_path.is_empty():
		if capture_after_packets > 0:
			call_deferred(
				"_capture_after_packets", screenshot_path, capture_after_packets, capture_timeout_ms
			)
		else:
			call_deferred("_capture_screenshot", screenshot_path)


func _start_motion_ingest() -> void:
	motion_ingest = MotionIngestNode.new()
	add_child(motion_ingest)
	var port := int(ProjectSettings.get_setting("network/udp/listen_port", 7000))
	var error := motion_ingest.start(port)
	if error != OK:
		push_warning("UDP ingest could not bind port %d: %s" % [port, error_string(error)])
		return
	diagnostics_hud.bind_ingest(motion_ingest)
	pairing_server = PairingServerNode.new()
	add_child(pairing_server)
	pairing_server.attach(motion_ingest, session_manager)
	pairing_server.set_reconnect_window_seconds(_reconnect_window_seconds())
	clock_service = HostClockServiceNode.new()
	add_child(clock_service)
	clock_service.attach(motion_ingest, pairing_server, session_manager)
	motion_ingest.set_clock_service(clock_service)
	connection_manager = ConnectionManagerNode.new()
	add_child(connection_manager)
	connection_manager.attach(motion_ingest, pairing_server, clock_service)
	motion_ingest.set_connection_manager(connection_manager)
	diagnostics_hud.bind_connection_manager(connection_manager)
	host_heartbeat = HostHeartbeatNode.new()
	host_heartbeat.attach(motion_ingest, connection_manager, session_manager)
	add_child(host_heartbeat)
	_start_session_logger(port)
	_start_raw_latency_stimulus()


## Game-configurable disconnect reservation: `--reconnect-window-s=N` overrides
## the `network/reconnect/window_seconds` project setting (PairingServer clamps).
func _reconnect_window_seconds() -> int:
	var seconds := int(ProjectSettings.get_setting(
		"network/reconnect/window_seconds", PairingServerNode.DEFAULT_RECONNECT_WINDOW_S
	))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--reconnect-window-s="):
			var value := argument.trim_prefix("--reconnect-window-s=")
			if value.is_valid_int():
				seconds = int(value)
			else:
				push_warning("Ignoring invalid --reconnect-window-s value: %s" % value)
	return seconds


## AWDL can switch on at any time (AirDrop, AirPlay, Sidecar), so re-check it
## periodically, warn on the pairing panel and log each change for soak reports.
func _start_awdl_monitor() -> void:
	_refresh_awdl()
	var timer := Timer.new()
	timer.wait_time = AWDL_CHECK_INTERVAL_S
	timer.autostart = true
	timer.timeout.connect(_refresh_awdl)
	add_child(timer)


func _refresh_awdl() -> void:
	var state := AwdlDetector.current_state()
	if state == awdl_state:
		return
	awdl_state = state
	if session_logger != null:
		session_logger.log_event("awdl_state", {"state": AwdlDetector.state_name(state)})
	_render_session()


func _start_raw_latency_stimulus() -> void:
	raw_latency_stimulus = RawLatencyStimulusNode.new()
	raw_latency_stimulus.threshold_rad_s = float(
		ProjectSettings.get_setting("latency_test/gyro_threshold_rad_s", 3.5)
	)
	raw_latency_stimulus.cooldown_ms = int(
		ProjectSettings.get_setting("latency_test/cooldown_ms", 700)
	)
	add_child(raw_latency_stimulus)
	raw_latency_stimulus.bind(motion_ingest, session_logger)
	raw_latency_stimulus.armed = OS.get_cmdline_user_args().has("--latency-test")


func _start_session_logger(port: int) -> void:
	session_logger = SessionLoggerNode.new()
	session_logger.enabled = bool(ProjectSettings.get_setting("logging/session/enabled", true))
	session_logger.flush_interval_ms = int(
		ProjectSettings.get_setting("logging/session/flush_interval_ms", 1000)
	)
	session_logger.maximum_bytes = int(
		ProjectSettings.get_setting("logging/session/maximum_bytes", 10 * 1024 * 1024)
	)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--session-log-max-mb="):
			var megabytes := clampi(
				int(argument.trim_prefix("--session-log-max-mb=")), 1, 1024
			)
			session_logger.maximum_bytes = megabytes * 1024 * 1024
	add_child(session_logger)
	var engineering_session_id := str(session_manager.current_session.session_hex)
	var error := session_logger.start(engineering_session_id, {"udp_port": port})
	if error != OK:
		push_warning("Session logger could not start: %s" % error_string(error))
		return
	session_logger.attach(motion_ingest)
	clock_service.metrics_updated.connect(func(controller_id: int, metrics: Dictionary) -> void:
		var fields := metrics.duplicate(true)
		fields["controller_id"] = controller_id
		session_logger.log_event("clock_sync", fields)
	)
	pairing_server.pairing_event.connect(func(event: Dictionary) -> void:
		session_logger.log_event("pairing", PairingLogFields.from_event(event))
	)
	connection_manager.state_changed.connect(func(controller_id: int, state: String, reason: String) -> void:
		session_logger.log_event("controller_state", {
			"controller_id": controller_id,
			"state": state,
			"reason": reason,
		})
	)
	soak_telemetry = SoakTelemetryNode.new()
	add_child(soak_telemetry)
	soak_telemetry.attach(motion_ingest, clock_service, connection_manager, session_logger)
	session_logger.log_event("host_started", {
		"udp_port": port,
		"reconnect_window_s": pairing_server.reconnect_window_ms() / 1000,
	})


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)

	var heading := _label("MOTION BADMINTON", 30, COLOR_TEXT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)

	var version := _label(
		"HOST  v%s" % ProjectSettings.get_setting("application/config/version", "unknown"),
		16,
		COLOR_MUTED
	)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(version)

	content.add_child(_session_panel())

	var player_grid := GridContainer.new()
	player_grid.columns = 2
	player_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_grid.add_theme_constant_override("h_separation", 18)
	content.add_child(player_grid)
	player_grid.add_child(_player_card("PLAYER 1", "Waiting for controller", "P1"))
	player_grid.add_child(_player_card("PLAYER 2", "Waiting for controller", "P2"))

	diagnostics_hud = DiagnosticsHUDNode.new()
	content.add_child(diagnostics_hud)

	var footer := _label(
		"Fixed simulation: %d Hz  •  Local session  •  Engineering shell" %
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60),
		13,
		COLOR_MUTED
	)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(footer)


func _player_card(title: String, state: String, badge: String) -> PanelContainer:
	var card := _panel()
	card.custom_minimum_size = Vector2(280, 150)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_content := VBoxContainer.new()
	card_content.add_theme_constant_override("separation", 12)
	card.add_child(card_content)

	var badge_label := _label(badge, 22, COLOR_ACCENT)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.custom_minimum_size = Vector2(0, 48)
	card_content.add_child(badge_label)
	var title_label := _label(title, 24, COLOR_TEXT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_content.add_child(title_label)
	var state_label := _label(state, 16, COLOR_MUTED)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_content.add_child(state_label)
	var detail := _label("Not paired  •  No motion data", 13, COLOR_MUTED)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_content.add_child(detail)
	return card


func _session_panel() -> PanelContainer:
	var panel := _panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 5)
	row.add_child(details)
	var heading := HBoxContainer.new()
	details.add_child(heading)
	var title := _label("PAIRING SESSION", 14, COLOR_MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var ready := _label("READY TO JOIN", 16, COLOR_ACCENT)
	heading.add_child(ready)
	session_address_label = _label("", 19, COLOR_TEXT)
	details.add_child(session_address_label)
	session_interface_label = _label("", 12, COLOR_MUTED)
	details.add_child(session_interface_label)
	session_manual_label = _label("", 12, COLOR_TEXT)
	session_manual_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(session_manual_label)
	session_warning_label = _label("", 11, Color("f6b85f"))
	# Network/AWDL guidance can be several sentences; wrap within the panel.
	session_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	session_warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_warning_label.custom_minimum_size = Vector2(320, 0)
	details.add_child(session_warning_label)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	details.add_child(controls)
	interface_selector = OptionButton.new()
	interface_selector.custom_minimum_size = Vector2(220, 34)
	for candidate in session_manager.available_interfaces:
		interface_selector.add_item("%s — %s" % [candidate.friendly, candidate.address])
		interface_selector.set_item_metadata(interface_selector.item_count - 1, candidate.name)
		if candidate.name == session_manager.current_session.interface_name:
			interface_selector.select(interface_selector.item_count - 1)
	interface_selector.item_selected.connect(_on_interface_selected)
	controls.add_child(interface_selector)
	var rotate := Button.new()
	rotate.text = "NEW PAIRING CODE"
	rotate.pressed.connect(_on_rotate_session)
	controls.add_child(rotate)

	session_qr = TextureRect.new()
	session_qr.custom_minimum_size = Vector2(148, 148)
	session_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	session_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	session_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(session_qr)
	_render_session()
	return panel


func _on_interface_selected(index: int) -> void:
	var interface_name := str(interface_selector.get_item_metadata(index))
	session_manager.rotate(interface_name)
	if pairing_server != null:
		pairing_server.reset()
	_render_session()


func _on_rotate_session() -> void:
	session_manager.rotate(str(session_manager.current_session.interface_name))
	if pairing_server != null:
		pairing_server.reset()
	_render_session()


func _render_session() -> void:
	var session := session_manager.current_session
	var address := str(session.address)
	session_address_label.text = (
		"%s:%d" % [address, int(session.port)]
		if not address.is_empty()
		else "NO USABLE LAN INTERFACE"
	)
	session_interface_label.text = "Interface: %s (%s)  •  expires in %ds" % [
		str(session.interface_friendly),
		str(session.interface_name),
		session_manager.lifetime_seconds,
	]
	session_manual_label.text = "Manual code: %s" % str(session.manual_code)
	session_warning_label.text = AwdlDetector.combine_warnings(
		str(session.network_warning),
		AwdlDetector.warning_for(awdl_state) if awdl_state >= 0 else "",
	)
	var join_uri := str(session.join_uri)
	session_qr.texture = qr_generator.get_texture(join_uri) if not join_uri.is_empty() else null


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_top = 16
	style.content_margin_right = 20
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


func _finish_smoke_test() -> void:
	print(
		"TMB-004_HOST_SMOKE_OK version=%s physics_hz=%d" % [
			ProjectSettings.get_setting("application/config/version", "unknown"),
			ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0),
		]
	)
	get_tree().quit(0)


func _capture_screenshot(output_path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	var error := screenshot.save_png(output_path)
	if error == OK:
		print("TMB-004_SCREENSHOT_OK path=%s" % output_path)
	else:
		push_error("Could not save screenshot: %s" % error_string(error))
	get_tree().quit(0 if error == OK else 1)


func _capture_after_packets(output_path: String, packet_count: int, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if motion_ingest != null and int(motion_ingest.snapshot().packets_processed) >= packet_count:
			diagnostics_hud.refresh_now()
			await get_tree().create_timer(0.1).timeout
			print(
				"TMB-013_HUD_CAPTURE packets=%d graph_history=%s controllers=%s" % [
					int(motion_ingest.snapshot().packets_processed),
					str(diagnostics_hud.graph_history_sizes()),
					str(motion_ingest.snapshot().controllers),
				]
			)
			await _capture_screenshot(output_path)
			return
		await get_tree().process_frame
	push_error("Timed out waiting for %d packets before screenshot" % packet_count)
	get_tree().quit(1)
