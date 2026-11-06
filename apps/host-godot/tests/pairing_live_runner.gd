extends SceneTree

const Ingest = preload("res://network/motion_ingest.gd")
const Sessions = preload("res://session/session_manager.gd")
const Pairing = preload("res://session/pairing_server.gd")

var _events: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := 7020
	var timeout_ms := 20_000
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--timeout-ms="):
			timeout_ms = int(argument.trim_prefix("--timeout-ms="))
	var ingest := Ingest.new()
	root.add_child(ingest)
	if ingest.start(port, "0.0.0.0") != OK:
		push_error("Could not bind live pairing runner")
		quit(1)
		return
	var sessions := Sessions.new()
	root.add_child(sessions)
	sessions.start_new_session(
		port,
		"en0",
		[{"name": "en0", "friendly": "Test", "addresses": ["192.168.1.1"]}]
	)
	var ios_session := sessions.current_session.duplicate(true)
	ios_session.address = "127.0.0.1"
	var android_session := sessions.current_session.duplicate(true)
	android_session.address = "10.0.2.2"
	var pairing := Pairing.new()
	root.add_child(pairing)
	pairing.attach(ingest, sessions)
	pairing.pairing_event.connect(func(event: Dictionary) -> void:
		_events.append(event.duplicate(true))
		print("TMB-019_LIVE_EVENT %s" % JSON.stringify(event))
	)
	print("TMB-019_LIVE_READY %s" % JSON.stringify({
		"ios_uri": Sessions.build_join_uri(ios_session),
		"android_uri": Sessions.build_join_uri(android_session),
	}))
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		ingest.poll_packets()
		if pairing.assignments().size() >= 2:
			await create_timer(0.5).timeout
			print("TMB-019_LIVE_COMPLETE events=%s" % JSON.stringify(_events))
			quit(0)
			return
		await process_frame
	push_error("Timed out waiting for two controller assignments; events=%s" % JSON.stringify(_events))
	quit(1)
