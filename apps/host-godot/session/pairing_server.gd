class_name PairingServer
extends Node

signal pairing_event(event: Dictionary)

const Codec = preload("res://protocol/protocol_v1.gd")
const STATE_PAIRED := 1
const STATE_EXPIRED := 2
const STATE_SECRET_REJECTED := 3
const STATE_FULL := 4
const STATE_UNSUPPORTED := 5
## Disconnect reservation: how long a controller keeps its ID and player after
## heartbeat loss. Game-dependent, so configurable; controllers retry for up to
## MAX_RECONNECT_WINDOW_S, and this host value decides restoration.
const DEFAULT_RECONNECT_WINDOW_S := 30
const MIN_RECONNECT_WINDOW_S := 5
const MAX_RECONNECT_WINDOW_S := 60
const MS_PER_SECOND := 1000

var _ingest: MotionIngest
var _sessions: HostSessionManager
var _assignments: Dictionary = {}
var _controller_ids: Dictionary = {}
var _identity_records: Dictionary = {}
var _sequence := 0
var _reconnect_window_ms := DEFAULT_RECONNECT_WINDOW_S * MS_PER_SECOND


func attach(ingest: MotionIngest, sessions: HostSessionManager) -> void:
	_ingest = ingest
	_sessions = sessions
	if not ingest.message_received.is_connected(_on_message_received):
		ingest.message_received.connect(_on_message_received)


func assignments() -> Dictionary:
	return _assignments.duplicate(true)


func reset() -> void:
	_assignments.clear()
	_controller_ids.clear()
	_identity_records.clear()
	_sequence = 0


func set_reconnect_window_seconds(seconds: int) -> void:
	_reconnect_window_ms = clampi(seconds, MIN_RECONNECT_WINDOW_S, MAX_RECONNECT_WINDOW_S) * MS_PER_SECOND


func reconnect_window_ms() -> int:
	return _reconnect_window_ms


func mark_disconnected(controller_id: int) -> void:
	for identity in _identity_records:
		var record: Dictionary = _identity_records[identity]
		if int(record.controller_id) == controller_id:
			record.reserved_until_ms = Time.get_ticks_msec() + _reconnect_window_ms
			return


func _on_message_received(
	message: Dictionary, source_ip: String, source_port: int, _arrival_ns: int
) -> void:
	if int(message.header.message_type) != Codec.TYPE_HELLO:
		return
	var endpoint := "%s:%d" % [source_ip, source_port]
	var state := STATE_PAIRED
	var player := 0
	var controller_id := _temporary_id()
	var reason := "paired"
	var identity := _identity_for(message.payload)
	_prune_expired_reservations()
	var session_expired := _sessions.is_expired()
	if int(message.header.session_id) != int(_sessions.current_session.session_id):
		state = STATE_SECRET_REJECTED
		reason = "wrong_session"
	elif not _constant_time_secret_matches(message.payload.pairing_secret):
		state = STATE_SECRET_REJECTED
		reason = "wrong_secret"
	elif _identity_records.has(identity):
		var record: Dictionary = _identity_records[identity]
		var reserved_until := int(record.reserved_until_ms)
		var same_endpoint := str(record.endpoint) == endpoint
		var reservation_active := (
			reserved_until > 0 and Time.get_ticks_msec() <= reserved_until
		)
		# An expired QR cannot create or take over an assignment. It may still
		# authenticate a known controller (correct secret and identity) that
		# either still holds its assignment (reserved_until == 0: e.g. briefly
		# backgrounded, re-HELLOing from a new socket before the heartbeat
		# timeout) or is reclaiming its bounded disconnect reservation.
		var still_assigned := reserved_until == 0
		if session_expired and not same_endpoint and not still_assigned and not reservation_active:
			state = STATE_EXPIRED
			reason = "expired"
		elif reserved_until == 0 or reservation_active:
			player = int(record.player)
			controller_id = int(record.controller_id)
			var old_endpoint := str(record.endpoint)
			if old_endpoint != endpoint:
				_assignments.erase(old_endpoint)
				_controller_ids.erase(old_endpoint)
				reason = "reconnect"
			else:
				reason = "retry"
			record.endpoint = endpoint
			record.reserved_until_ms = 0
			_assignments[endpoint] = player
			_controller_ids[endpoint] = controller_id
		else:
			_assignments.erase(str(record.endpoint))
			_controller_ids.erase(str(record.endpoint))
			_identity_records.erase(identity)
			player = _first_free_player()
			controller_id = _temporary_id()
			_register_identity(identity, endpoint, player, controller_id)
	elif session_expired:
		state = STATE_EXPIRED
		reason = "expired"
	elif _identity_records.size() >= 2:
		state = STATE_FULL
		reason = "full"
	else:
		player = _first_free_player()
		controller_id = _temporary_id()
		_register_identity(identity, endpoint, player, controller_id)

	_send_welcome(source_ip, source_port, controller_id, player, state)
	pairing_event.emit({
		"endpoint": endpoint,
		"source_ip": source_ip,
		"source_port": source_port,
		"state": state,
		"reason": reason,
		"player": player,
		"controller_id": controller_id,
		"platform": int(message.payload.platform),
		"device_model": str(message.payload.device_model),
	})


func _send_welcome(
	destination_ip: String,
	destination_port: int,
	controller_id: int,
	player: int,
	state: int
) -> void:
	var encoded := Codec.encode({
		"header": {
			"protocol_version": Codec.VERSION,
			"message_type": Codec.TYPE_WELCOME,
			"flags": 0,
			"session_id": int(_sessions.current_session.session_id),
			"controller_id": controller_id,
			"sequence": _sequence,
		},
		"payload": {
			"message_type": Codec.TYPE_WELCOME,
			"player": player,
			"session_state": state,
			"heartbeat_interval_ms": 500,
			"disconnect_timeout_ms": 2000,
			"reorder_window_packets": 8,
			"host_monotonic_ns": Time.get_ticks_usec() * 1000,
			"session_expires_unix_s": int(_sessions.current_session.expires_unix_s),
		},
	})
	_sequence = (_sequence + 1) & 0xFFFF_FFFF
	if encoded.ok:
		var error := _ingest.send_to(encoded.data, destination_ip, destination_port)
		if error != OK:
			push_warning("Could not send WELCOME: %s" % error_string(error))
	else:
		push_error("Could not encode WELCOME: %s" % str(encoded.error))


func _constant_time_secret_matches(candidate: PackedByteArray) -> bool:
	var expected := str(_sessions.current_session.secret).hex_decode()
	var difference := candidate.size() ^ expected.size()
	var count := maxi(candidate.size(), expected.size())
	for index in count:
		var left := int(candidate[index]) if index < candidate.size() else 0
		var right := int(expected[index]) if index < expected.size() else 0
		difference |= left ^ right
	return difference == 0


func _first_free_player() -> int:
	for record in _identity_records.values():
		if int(record.player) == 1:
			return 2
	return 1


func _prune_expired_reservations() -> void:
	var now := Time.get_ticks_msec()
	for raw_identity in _identity_records.keys():
		var identity := str(raw_identity)
		var record: Dictionary = _identity_records[identity]
		var reserved_until := int(record.reserved_until_ms)
		if reserved_until > 0 and now > reserved_until:
			_assignments.erase(str(record.endpoint))
			_controller_ids.erase(str(record.endpoint))
			_identity_records.erase(identity)


func _identity_for(payload: Dictionary) -> String:
	return "%d|%s" % [int(payload.platform), str(payload.device_model)]


func _register_identity(identity: String, endpoint: String, player: int, controller_id: int) -> void:
	_identity_records[identity] = {
		"endpoint": endpoint,
		"player": player,
		"controller_id": controller_id,
		"reserved_until_ms": 0,
	}
	_assignments[endpoint] = player
	_controller_ids[endpoint] = controller_id


func _temporary_id() -> int:
	var bytes := Crypto.new().generate_random_bytes(4)
	bytes[0] = bytes[0] & 0x7F
	var result := 0
	for byte in bytes:
		result = (result << 8) | int(byte)
	return result if result != 0 else 1
