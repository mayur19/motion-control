extends SceneTree

## A routine clock-sync PONG may only complete a reconnect (Reconnecting ->
## Connected). It must not revive a Disconnected controller: that path skips
## the re-HELLO/STATUS resync that resets the clock estimate and motion pin.
## Found physically in the TMB-022 attempt (Galaxy Disconnected -> Connected
## "clock synchronized" with no resync).

const Connections = preload("res://network/connection_manager.gd")
const Pairing = preload("res://session/pairing_server.gd")
const Clocks = preload("res://network/host_clock_service.gd")

const CONTROLLER_ID := 5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var connections := Connections.new()
	connections._pairing = Pairing.new()
	connections._clocks = Clocks.new()
	connections.set_process(false)
	root.add_child(connections)
	connections._on_pairing_event({
		"state": 1, "controller_id": CONTROLLER_ID, "player": 1,
		"endpoint": "192.0.2.1:5000", "source_ip": "192.0.2.1",
	})
	var controller: Dictionary = connections._controllers[CONTROLLER_ID]
	controller.app_active = true
	controller.sensor_valid = true

	connections._on_clock_metrics(CONTROLLER_ID, {})
	if not _expect(connections, "Connected", true, "fresh sync completes reconnect"): return

	connections.audit_controller(CONTROLLER_ID, int(controller.last_seen_ms) + 2500)
	if not _expect(connections, "Disconnected", false, "heartbeat timeout"): return

	connections._on_clock_metrics(CONTROLLER_ID, {})
	if not _expect(connections, "Disconnected", false, "late PONG must not revive"): return

	connections.audit_controller(CONTROLLER_ID, int(controller.last_seen_ms) + 1500)
	controller.state = "Degraded"
	controller.accepting_motion = false
	connections._on_clock_metrics(CONTROLLER_ID, {})
	if not _expect(connections, "Degraded", false, "PONG must not clear a heartbeat delay"): return
	connections._pairing.free()
	connections._clocks.free()
	print("TMB-021_CONNECTION_STATE_OK pong_revives_disconnected=false")
	quit(0)


func _expect(connections, state: String, accepting: bool, label: String) -> bool:
	var actual: Dictionary = connections.state_for(CONTROLLER_ID)
	if str(actual.state) != state or bool(actual.accepting_motion) != accepting:
		push_error("%s: expected %s/%s, got %s/%s" % [label, state, accepting, actual.state, actual.accepting_motion])
		print("TMB-021_CONNECTION_STATE_FAIL")
		quit(1)
		return false
	return true
