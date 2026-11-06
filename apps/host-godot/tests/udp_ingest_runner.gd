extends SceneTree

const Ingest = preload("res://network/motion_ingest.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := 7001
	var duration := 3.0
	var queue_capacity := 4096
	var expected_packets := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--duration="):
			duration = float(argument.trim_prefix("--duration="))
		elif argument.begins_with("--queue-capacity="):
			queue_capacity = int(argument.trim_prefix("--queue-capacity="))
		elif argument.begins_with("--expected-packets="):
			expected_packets = int(argument.trim_prefix("--expected-packets="))

	var ingest := Ingest.new()
	ingest.queue_capacity = queue_capacity
	root.add_child(ingest)
	var error := ingest.start(port, "127.0.0.1")
	if error != OK:
		push_error("Could not bind UDP test port: %s" % error_string(error))
		quit(1)
		return
	var deadline_ms := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if expected_packets > 0 and int(ingest.snapshot().packets_processed) >= expected_packets:
			break
		await process_frame
	await create_timer(0.1).timeout
	var result := ingest.snapshot()
	print("TMB-011_INGEST_SUMMARY %s" % JSON.stringify(result))
	ingest.stop()
	quit(0)
