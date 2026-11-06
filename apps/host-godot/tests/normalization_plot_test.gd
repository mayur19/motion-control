extends SceneTree

const Plot = preload("res://ui/normalization_plot.gd")
const Ingest = preload("res://network/motion_ingest.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Control.new()
	root.add_child(host)
	var ingest := Ingest.new()
	host.add_child(ingest)
	var plot := Plot.new()
	host.add_child(plot)
	await process_frame
	plot.bind_ingest(ingest)
	if plot.visible:
		return _fail("Debug plot must start hidden")

	ingest.sample_received.emit({"controller_id": 9, "angular_velocity": [9.0, 9.0, 9.0]})
	if plot.history_size(9) != 0:
		return _fail("Uncalibrated samples must not be plotted")

	for step in Plot.HISTORY + 40:
		ingest.normalized_sample_received.emit({
			"controller_id": 9,
			"angular_velocity": [float(step), 0.0, -1.0],
			"normalized": {"angular_velocity": [-float(step), 2.0, 1.0]},
		})
	if plot.history_size(9) != Plot.HISTORY:
		return _fail("History not bounded: %d" % plot.history_size(9))
	var raw_x := plot.series(9, Plot.RAW, 0)
	var normalized_x := plot.series(9, Plot.NORMALIZED, 0)
	if raw_x[-1] != float(Plot.HISTORY + 39) or normalized_x[-1] != -float(Plot.HISTORY + 39):
		return _fail("Raw and normalized series mixed up: %s / %s" % [raw_x[-1], normalized_x[-1]])
	if plot.series(9, Plot.NORMALIZED, 1)[0] != 2.0:
		return _fail("Normalized Y series wrong")

	var key := InputEventKey.new()
	key.keycode = KEY_F5
	key.pressed = true
	plot._unhandled_key_input(key)
	if not plot.visible:
		return _fail("F5 did not show the plot")
	plot.queue_redraw()
	await process_frame

	# The host layout is a full 1280x720 stack; the plot must overlay the
	# window bottom instead of being pushed off-screen by the stack.
	var window := Control.new()
	window.size = Vector2(1280, 720)
	root.add_child(window)
	var overlay := Plot.new()
	window.add_child(overlay)
	overlay.place_as_overlay()
	overlay.visible = true
	await process_frame
	var rect := overlay.get_rect()
	if rect.position.y < 0 or rect.end.y > 720.5 or rect.size.y < 180 or rect.size.x < 1000:
		return _fail("Overlay plot not fully on screen: %s" % str(rect))

	print("TMB-028_NORMALIZATION_PLOT_OK history=%d f5_toggle=true calibrated_only=true" % Plot.HISTORY)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
