extends SceneTree

const CapturePanelScript = preload("res://ui/capture_panel.gd")
const Ingest = preload("res://network/motion_ingest.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var window := Control.new()
	window.size = Vector2(1280, 720)
	root.add_child(window)
	var ingest := Ingest.new()
	window.add_child(ingest)
	var panel := CapturePanelScript.new()
	panel.capture_root = _root_dir()
	window.add_child(panel)
	panel.place_as_overlay()
	panel.bind_ingest(ingest)
	await process_frame
	if panel.visible:
		return _fail("Capture panel must start hidden")

	var key := InputEventKey.new()
	key.keycode = KEY_F6
	key.pressed = true
	panel._unhandled_key_input(key)
	await process_frame
	var rect := panel.get_rect()
	if not panel.visible or rect.position.x < 0 or rect.end.x > 1280.5 or rect.position.y < 0 or rect.end.y > 720.5:
		return _fail("F6 overlay not fully on screen: %s" % str(rect))

	ingest.datagram_accepted.emit(PackedByteArray([0]), "192.0.2.1:1", 10, 0)
	panel.toggle_capture(100)
	if not panel.is_capturing():
		return _fail("Capture did not start")
	if panel.visible:
		return _fail("Starting capture must hide the panel so the pairing QR is visible")
	panel.set_labels({"player": 2, "phone": "Pixel", "handedness": "left", "intended_shot": "drop",
		"valid": false, "speed": "gentle", "swing_count": 5})
	panel.toggle_take(200)
	ingest.datagram_accepted.emit(PackedByteArray([1, 2]), "192.0.2.1:1", 250, 0)
	# Labels selected before END TAKE are authoritative, not a stale snapshot
	# from BEGIN TAKE.
	panel.set_labels({"player": 2, "phone": "Pixel", "handedness": "left", "intended_shot": "drop",
		"valid": false, "speed": "normal", "swing_count": 6})
	panel.toggle_take(300)
	var reset: Dictionary = panel.current_labels()
	if str(reset.speed) != "none" or int(reset.swing_count) != 0:
		return _fail("Ending a take must clear stale speed/count: %s" % str(reset))
	# Swing takes may begin before the operator enters the final labels, but END
	# TAKE must refuse missing speed/count and leave the take open for repair.
	panel.toggle_take(310)
	var rejected := panel.toggle_take(320)
	if bool(rejected.get("ok", true)) or panel._capture.open_take().is_empty() \
			or not panel.status_text().contains("speed"):
		return _fail("Incomplete swing labels must block END TAKE: %s" % str(rejected))
	# A non-swing selection forces none/zero even when stale swing values are
	# supplied, locks both controls, and can repair the still-open take.
	panel.set_labels({"player": 2, "phone": "Pixel", "handedness": "left", "intended_shot": "handling",
		"valid": true, "speed": "fast", "swing_count": 7})
	var handling: Dictionary = panel.current_labels()
	if str(handling.speed) != "none" or int(handling.swing_count) != 0 \
			or not panel._speed.disabled or panel._swings.editable:
		return _fail("Non-swing labels must force and lock none/zero: %s" % str(handling))
	panel.toggle_take(330)
	# An invalid/aborted swing is allowed to end with zero swings so unsafe or
	# incorrectly performed attempts can be retained instead of fabricated.
	panel.set_labels({"player": 2, "phone": "Pixel", "handedness": "left", "intended_shot": "drop",
		"valid": false, "speed": "none", "swing_count": 0})
	panel.toggle_take(340)
	var invalid_ended := panel.toggle_take(350)
	if not bool(invalid_ended.get("ok", false)):
		return _fail("Invalid swing take with zero count must remain recordable: %s" % str(invalid_ended))
	var stopped := panel.toggle_capture(400)
	if panel.is_capturing() or not bool(stopped.get("ok", false)) or int(stopped.datagrams) != 1:
		return _fail("Capture must record only datagrams while running: %s" % str(stopped))
	var labels := FileAccess.get_file_as_string(str(stopped.directory).path_join("labels.jsonl")).split("\n", false)
	if labels.size() != 4:
		return _fail("Expected three takes plus header: %s" % str(labels))
	var take: Dictionary = JSON.parse_string(labels[1])
	var non_swing: Dictionary = JSON.parse_string(labels[2])
	var invalid_swing: Dictionary = JSON.parse_string(labels[3])
	if str(take.speed) != "normal" or int(take.swing_count) != 6:
		return _fail("End-time panel labels not recorded: %s" % str(take))
	if int(take.player) != 2 or str(take.phone) != "Pixel" or str(take.intended_shot) != "drop" or bool(take.valid) \
			or int(take.start_arrival_ns) != 200 or int(take.end_arrival_ns) != 300:
		return _fail("Take labels from the panel are wrong: %s" % str(take))
	if str(non_swing.intended_shot) != "handling" or str(non_swing.speed) != "none" \
			or int(non_swing.swing_count) != 0 or int(non_swing.end_arrival_ns) != 330:
		return _fail("Corrected non-swing labels are wrong: %s" % str(non_swing))
	if bool(invalid_swing.valid) or str(invalid_swing.intended_shot) != "drop" \
			or int(invalid_swing.swing_count) != 0:
		return _fail("Invalid swing take labels are wrong: %s" % str(invalid_swing))
	if not panel.status_text().contains("Saved"):
		return _fail("Status must report the saved capture: %s" % panel.status_text())

	print("TMB-029_CAPTURE_PANEL_OK f6_overlay=true take_labels=true guarded_labels=true qr_visible=true")
	quit(0)


func _root_dir() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=").get_base_dir().path_join("panel-test")
	return OS.get_user_data_dir().path_join("panel-test")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
