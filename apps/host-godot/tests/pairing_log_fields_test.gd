extends SceneTree

const PairingLogFields = preload("res://logging/pairing_log_fields.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := {
		"endpoint": "192.0.2.10:50000",
		"source_ip": "192.0.2.10",
		"source_port": 50000,
		"state": 1,
		"reason": "reconnect",
		"player": 1,
		"controller_id": 168496141,
		"platform": 1,
		"device_model": "iPhone18,5",
		"pairing_secret": PackedByteArray([1, 2, 3]),
		"installation_id": "do-not-log",
	}
	var fields: Dictionary = PairingLogFields.from_event(source)
	var expected_keys := ["controller_id", "endpoint", "platform", "player", "reason", "state"]
	var keys := fields.keys()
	keys.sort()
	if keys != expected_keys:
		_fail("unexpected keys %s" % str(keys))
		return
	if int(fields.player) != 1 or int(fields.controller_id) != 168496141:
		_fail("assignment fields not preserved")
		return
	if str(fields.reason) != "reconnect" or int(fields.state) != 1:
		_fail("state/reason not preserved")
		return
	if source.has("pairing_secret") == false:
		_fail("source event was mutated")
		return
	var sparse: Dictionary = PairingLogFields.from_event({"reason": "full"})
	if int(sparse.player) != 0 or int(sparse.controller_id) != 0 or str(sparse.endpoint) != "":
		_fail("missing fields did not default safely")
		return
	print("TMB-021_PAIRING_LOG_FIELDS_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
