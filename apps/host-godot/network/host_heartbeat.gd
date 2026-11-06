class_name HostHeartbeat
extends Node

## Host→controller liveness (protocol sections 4.7 and 4.8). Controllers leave
## Connected when no host packet arrives within WELCOME `disconnect_timeout_ms`,
## so the host sends STATUS to each live controller's control endpoint every
## WELCOME heartbeat interval, and a GOODBYE when it shuts down cleanly.
##
## Collaborators are duck-typed so tests can substitute fakes:
## sender: send_to(packet, ip, port) and snapshot() (MotionIngest)
## connections: snapshot() (ControllerConnectionManager)
## sessions: current_session.session_id (HostSessionManager)

const Codec = preload("res://protocol/protocol_v1.gd")
const INTERVAL_MS := 500
const BATTERY_UNKNOWN := 255
const SENSOR_UNAVAILABLE := 0
const APP_FOREGROUND := 0
const PAUSE_NONE := 0
const GOODBYE_HOST_SHUTDOWN := 3
const SILENT_STATES := ["Disconnected"]

var _sender
var _connections
var _sessions
var _sequence := 0
var _next_status_ms := 0
var _goodbye_sent := false


func attach(sender, connections, sessions) -> void:
	_sender = sender
	_connections = connections
	_sessions = sessions


func _process(_delta: float) -> void:
	tick(Time.get_ticks_msec())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		send_goodbye()


func _exit_tree() -> void:
	send_goodbye()


## Sends STATUS to every live controller when the interval has elapsed.
## Returns the number of packets sent.
func tick(now_ms: int) -> int:
	if _goodbye_sent or _sender == null or now_ms < _next_status_ms:
		return 0
	_next_status_ms = now_ms + INTERVAL_MS
	var accepted: Dictionary = _sender.snapshot().get("controllers", {})
	var sent := 0
	for target in _live_targets():
		var last_sequence := maxi(0, int(accepted.get(target.controller_id, {}).get("latest_sequence", 0)))
		if _send(target, Codec.TYPE_STATUS, {
			"sender_monotonic_ns": _now_ns(),
			"battery_percent": BATTERY_UNKNOWN,
			"sensor_state": SENSOR_UNAVAILABLE,
			"app_state": APP_FOREGROUND,
			"pause_reason": PAUSE_NONE,
			"actual_sample_hz": 0,
			"last_motion_sequence": last_sequence,
		}):
			sent += 1
	return sent


## Sends one GOODBYE per live controller; later calls are no-ops.
func send_goodbye(reason := GOODBYE_HOST_SHUTDOWN) -> int:
	if _goodbye_sent or _sender == null:
		return 0
	_goodbye_sent = true
	var sent := 0
	for target in _live_targets():
		if _send(target, Codec.TYPE_GOODBYE, {
			"reason": reason,
			"last_sequence": _sequence,
			"sender_monotonic_ns": _now_ns(),
		}):
			sent += 1
	return sent


func _live_targets() -> Array:
	var targets := []
	var controllers: Dictionary = _connections.snapshot()
	for raw_id in controllers:
		var controller: Dictionary = controllers[raw_id]
		if str(controller.get("state", "")) in SILENT_STATES:
			continue
		var endpoint := str(controller.get("control_endpoint", ""))
		var separator := endpoint.rfind(":")
		if separator <= 0:
			continue
		targets.append({
			"controller_id": int(raw_id),
			"ip": endpoint.substr(0, separator),
			"port": int(endpoint.substr(separator + 1)),
		})
	return targets


func _send(target: Dictionary, message_type: int, fields: Dictionary) -> bool:
	var payload := fields.duplicate()
	payload["message_type"] = message_type
	var encoded := Codec.encode({
		"header": {
			"protocol_version": Codec.VERSION,
			"message_type": message_type,
			"flags": 0,
			"session_id": int(_sessions.current_session.session_id),
			"controller_id": int(target.controller_id),
			"sequence": _sequence,
		},
		"payload": payload,
	})
	_sequence = (_sequence + 1) & 0xFFFF_FFFF
	if not encoded.ok:
		push_error("Could not encode host heartbeat: %s" % str(encoded.error))
		return false
	var error: Error = _sender.send_to(encoded.data, str(target.ip), int(target.port))
	if error != OK:
		push_warning("Host heartbeat to controller %d failed: %s" % [target.controller_id, error_string(error)])
		return false
	return true


func _now_ns() -> int:
	return maxi(1, Time.get_ticks_usec() * 1000)
