class_name ControllerConnectionManager
extends Node

signal state_changed(controller_id: int, state: String, reason: String)

const Codec = preload("res://protocol/protocol_v1.gd")
const DEGRADED_AFTER_MS := 1000
const DISCONNECTED_AFTER_MS := 2000

var _pairing: PairingServer
var _clocks: HostClockService
var _controllers: Dictionary = {}


func attach(ingest: MotionIngest, pairing: PairingServer, clocks: HostClockService) -> void:
	_pairing = pairing
	_clocks = clocks
	pairing.pairing_event.connect(_on_pairing_event)
	ingest.message_received.connect(_on_message_received)
	clocks.metrics_updated.connect(_on_clock_metrics)
	set_process(true)


func should_accept_motion(controller_id: int, endpoint: String = "") -> bool:
	if not _controllers.has(controller_id):
		return false
	var controller: Dictionary = _controllers[controller_id]
	if not bool(controller.accepting_motion):
		return false
	if endpoint.is_empty():
		return true
	var separator := endpoint.rfind(":")
	var source_ip := endpoint.substr(0, separator) if separator >= 0 else endpoint
	if source_ip != str(controller.source_ip):
		return false
	# Controllers intentionally use a dedicated high-rate UDP socket. Pin its
	# ephemeral port on the first post-sync motion packet, and reset that pin on
	# every reconnect so the prior stream cannot continue feeding input.
	if str(controller.motion_endpoint).is_empty():
		controller.motion_endpoint = endpoint
	return str(controller.motion_endpoint) == endpoint


## CALIBRATION is control-plane traffic: accept it from a paired controller's
## paired IP while it is live or rejoining (a rejoin resends calibration before
## the clock gate reopens motion), never while Paused or Disconnected.
func accepts_calibration(controller_id: int, source_ip: String) -> bool:
	if not _controllers.has(controller_id):
		return false
	var controller: Dictionary = _controllers[controller_id]
	return (
		source_ip == str(controller.source_ip)
		and ["Reconnecting", "Connected", "Degraded"].has(str(controller.state))
	)


func state_for(controller_id: int) -> Dictionary:
	if not _controllers.has(controller_id):
		return {"state": "Disconnected", "reason": "not paired", "accepting_motion": false}
	var result: Dictionary = _controllers[controller_id].duplicate(true)
	result["last_packet_age_ms"] = Time.get_ticks_msec() - int(result.last_seen_ms)
	return result


func snapshot() -> Dictionary:
	var result := {}
	for raw_controller_id in _controllers:
		result[raw_controller_id] = state_for(int(raw_controller_id))
	return result


func _process(_delta: float) -> void:
	audit()


func audit(now_ms: int = -1) -> void:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	for raw_controller_id in _controllers:
		audit_controller(int(raw_controller_id), now)


func audit_controller(controller_id: int, now_ms: int = -1) -> void:
	if not _controllers.has(controller_id):
		return
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var controller: Dictionary = _controllers[controller_id]
	var age := now - int(controller.last_seen_ms)
	if age > DISCONNECTED_AFTER_MS and controller.state != "Disconnected":
		_set_state(controller_id, "Disconnected", "heartbeat timeout", false)
		_pairing.mark_disconnected(controller_id)
	elif age > DEGRADED_AFTER_MS and controller.state == "Connected":
		_set_state(controller_id, "Degraded", "heartbeat delayed", false)


func _on_pairing_event(event: Dictionary) -> void:
	if int(event.state) != 1:
		return
	var controller_id := int(event.controller_id)
	_controllers[controller_id] = {
		"state": "Reconnecting",
		"reason": "waiting for clock synchronization",
		"accepting_motion": false,
		"last_seen_ms": Time.get_ticks_msec(),
		"app_active": false,
		"sensor_valid": false,
		"actual_sample_hz": 0,
		"player": int(event.player),
		"endpoint": str(event.endpoint),
		"control_endpoint": str(event.endpoint),
		"motion_endpoint": "",
		"source_ip": str(event.get("source_ip", "")),
	}
	state_changed.emit(controller_id, "Reconnecting", "waiting for clock synchronization")


func _on_message_received(
	message: Dictionary, source_ip: String, source_port: int, _arrival_ns: int
) -> void:
	var controller_id := int(message.header.controller_id)
	if controller_id == 0 or not _controllers.has(controller_id):
		return
	var controller: Dictionary = _controllers[controller_id]
	var endpoint := "%s:%d" % [source_ip, source_port]
	if str(controller.control_endpoint) != endpoint:
		return
	controller.last_seen_ms = Time.get_ticks_msec()
	if int(message.header.message_type) == Codec.TYPE_STATUS:
		var previous_state := str(controller.state)
		var app_active := int(message.payload.app_state) == 0
		var sensor_valid := int(message.payload.sensor_state) == 2
		controller.app_active = app_active
		controller.sensor_valid = sensor_valid
		controller.actual_sample_hz = int(message.payload.actual_sample_hz)
		if not app_active:
			_set_state(controller_id, "Paused", "controller backgrounded or paused", false)
		elif not sensor_valid:
			_set_state(controller_id, "Degraded", "invalid sensor state", false)
		elif previous_state == "Paused" or previous_state == "Disconnected":
			controller.motion_endpoint = ""
			_set_state(controller_id, "Reconnecting", "resynchronizing after resume", false)
			_clocks.restart_sync(controller_id)
		elif bool(_clocks.metrics_for(controller_id).get("initialized", false)):
			_set_state(controller_id, "Connected", "heartbeat active", true)


func _on_clock_metrics(controller_id: int, _metrics: Dictionary) -> void:
	if not _controllers.has(controller_id):
		return
	var controller: Dictionary = _controllers[controller_id]
	# A clock update only completes a reconnect already in progress. Disconnected,
	# Degraded and Paused controllers must return through a fresh STATUS, which
	# resets the clock estimate and motion pin before acceptance resumes.
	if str(controller.state) != "Reconnecting":
		return
	if bool(controller.app_active) and bool(controller.sensor_valid):
		_set_state(controller_id, "Connected", "clock synchronized", true)


func _set_state(controller_id: int, state: String, reason: String, accepting: bool) -> void:
	var controller: Dictionary = _controllers[controller_id]
	var changed: bool = (
		str(controller.state) != state
		or bool(controller.accepting_motion) != accepting
	)
	controller.state = state
	controller.reason = reason
	controller.accepting_motion = accepting
	if changed:
		state_changed.emit(controller_id, state, reason)
