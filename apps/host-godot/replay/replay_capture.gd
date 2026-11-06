extends SceneTree

## Offline replay CLI (TMB-029). No phone or network needed:
##   godot --headless --path apps/host-godot --script res://replay/replay_capture.gd -- \
##     --capture=<capture dir> --output=<result.json> [--config=<detector config .json>]
## Exits 0 and prints TMB-029_REPLAY_RESULT on success; exits 2 on any error.

const Replayer = preload("res://replay/capture_replayer.gd")
const Pipeline = preload("res://detection/detector_pipeline.gd")


func _initialize() -> void:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	if not options.has("capture") or not options.has("output"):
		return _exit_error("usage: --capture=<dir> --output=<result.json> [--config=<json>]")
	var config: Dictionary = Pipeline.DEFAULTS.duplicate(true)
	if options.has("config"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(options.config)))
		if typeof(parsed) != TYPE_DICTIONARY:
			return _exit_error("config is not a JSON object: %s" % str(options.config))
		config = parsed
	var result := Replayer.new().replay(str(options.capture), config)
	if not bool(result.get("ok", false)):
		return _exit_error(str(result.get("error", "replay failed")))
	var output := FileAccess.open(str(options.output), FileAccess.WRITE)
	if output == null:
		return _exit_error("cannot write %s" % str(options.output))
	output.store_string(JSON.stringify(result, "  ") + "\n")
	output.close()
	print("TMB-029_REPLAY_RESULT capture=%s datagrams=%d normalized=%d events=%d takes=%d output=%s" % [
		result.capture_id, result.totals.datagrams, result.totals.normalized_samples,
		result.totals.events, result.totals.takes, options.output,
	])
	quit(0)


func _exit_error(message: String) -> void:
	printerr("replay error: %s" % message)
	quit(2)
