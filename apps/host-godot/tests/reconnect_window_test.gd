extends SceneTree

## The disconnect reservation is game-configurable: default 30 s, clamped to
## 5-60 s (the controllers retry for 60 s), and mark_disconnected() reserves for the configured window.

const Pairing = preload("res://session/pairing_server.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pairing := Pairing.new()
	if pairing.reconnect_window_ms() != 30_000:
		return _fail("default window is not 30 s: %d" % pairing.reconnect_window_ms())
	for case in [[60, 60_000], [1, 5_000], [500, 60_000], [15, 15_000]]:
		pairing.set_reconnect_window_seconds(case[0])
		if pairing.reconnect_window_ms() != case[1]:
			return _fail("window %d s -> %d ms, expected %d" % [case[0], pairing.reconnect_window_ms(), case[1]])

	pairing.set_reconnect_window_seconds(45)
	pairing._identity_records["test-identity"] = {
		"controller_id": 7, "player": 1, "endpoint": "192.0.2.1:5000", "reserved_until_ms": 0,
	}
	var before := Time.get_ticks_msec()
	pairing.mark_disconnected(7)
	var reserved := int(pairing._identity_records["test-identity"].reserved_until_ms)
	if reserved < before + 45_000 or reserved > Time.get_ticks_msec() + 45_000:
		return _fail("reservation not using configured window: %d (now %d)" % [reserved, before])
	pairing.free()
	print("TMB-021_RECONNECT_WINDOW_OK default_s=30 range_s=5-60")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("TMB-021_RECONNECT_WINDOW_FAIL")
	quit(1)
