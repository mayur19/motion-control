extends SceneTree

const HUD = preload("res://ui/diagnostics_hud.gd")
const Ingest = preload("res://network/motion_ingest.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Control.new()
	root.add_child(host)
	var ingest := Ingest.new()
	host.add_child(ingest)
	var hud := HUD.new()
	host.add_child(hud)
	await process_frame
	hud.bind_ingest(ingest)

	for sequence in 150:
		ingest.sample_received.emit({
			"controller_id": 0x0A0B0C0D,
			"acceleration": [float(sequence), 1.0, -9.8],
			"angular_velocity": [0.1, float(sequence) / 10.0, 0.3],
		})
	if hud.graph_history_sizes() != [120, 0]:
		_fail("Graph history was not bounded: %s" % str(hud.graph_history_sizes()))
		return

	var toggle := InputEventKey.new()
	toggle.keycode = KEY_F3
	toggle.pressed = true
	hud._unhandled_key_input(toggle)
	if hud.visible:
		_fail("F3 did not hide diagnostics")
		return
	hud._unhandled_key_input(toggle)
	if not hud.visible:
		_fail("F3 did not restore diagnostics")
		return

	print("TMB-013_HUD_TEST_OK history=%s f3_toggle=true" % str(hud.graph_history_sizes()))
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
