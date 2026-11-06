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

	ingest.datagram_accepted.emit(PackedByteArray([0]), "192.0.2.1:1", 10)
	panel.toggle_capture(100)
	if not panel.is_capturing():
		return _fail("Capture did not start")
	panel.set_labels({"player": 2, "phone": "Galaxy", "handedness": "left", "intended_shot": "drop", "valid": false})
	panel.toggle_take(200)
	ingest.datagram_accepted.emit(PackedByteArray([1, 2]), "192.0.2.1:1", 250)
	panel.toggle_take(300)
	var stopped := panel.toggle_capture(400)
	if panel.is_capturing() or not bool(stopped.get("ok", false)) or int(stopped.datagrams) != 1:
		return _fail("Capture must record only datagrams while running: %s" % str(stopped))
	var labels := FileAccess.get_file_as_string(str(stopped.directory).path_join("labels.jsonl")).split("\n", false)
	var take: Dictionary = JSON.parse_string(labels[-1])
	if int(take.player) != 2 or str(take.intended_shot) != "drop" or bool(take.valid) \
			or int(take.start_arrival_ns) != 200 or int(take.end_arrival_ns) != 300:
		return _fail("Take labels from the panel are wrong: %s" % str(take))
	if not panel.status_text().contains("Saved"):
		return _fail("Status must report the saved capture: %s" % panel.status_text())

	print("TMB-029_CAPTURE_PANEL_OK f6_overlay=true take_labels=true")
	quit(0)


func _root_dir() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=").get_base_dir().path_join("panel-test")
	return OS.get_user_data_dir().path_join("panel-test")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
