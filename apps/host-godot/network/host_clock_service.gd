class_name HostClockService
extends Node

signal metrics_updated(controller_id: int, metrics: Dictionary)

const Codec = preload("res://protocol/protocol_v1.gd")
const Synchronizer = preload("res://network/clock_synchronizer.gd")
const SYNC_INTERVAL_MS := 5000

var _ingest: MotionIngest
var _sessions: HostSessionManager
var _clients: Dictionary = {}


func attach(ingest: MotionIngest, pairing: PairingServer, sessions: HostSessionManager) -> void:
	_ingest = ingest
	_sessions = sessions
	if not pairing.pairing_event.is_connected(_on_pairing_event):
		pairing.pairing_event.connect(_on_pairing_event)
	if not ingest.message_received.is_connected(_on_message_received):
		ingest.message_received.connect(_on_message_received)
	set_process(true)


func metrics_for(controller_id: int) -> Dictionary:
	if not _clients.has(controller_id):
		return {"initialized": false}
	return _clients[controller_id].synchronizer.snapshot()


func controller_to_host(controller_id: int, controller_ns: int) -> Dictionary:
	if not _clients.has(controller_id):
		return {"initialized": false, "host_ns": 0}
	var synchronizer: ClockSynchronizer = _clients[controller_id].synchronizer
	if not synchronizer.snapshot().initialized:
		return {"initialized": false, "host_ns": 0}
	return {"initialized": true, "host_ns": synchronizer.controller_to_host(controller_ns)}


func request_sync(controller_id: int) -> void:
	if not _clients.has(controller_id):
		return
	var client: Dictionary = _clients[controller_id]
	var ping_id: int = int(client.next_ping_id)
	var sent_ns := Time.get_ticks_usec() * 1000
	var encoded := Codec.encode({
		"header": {
			"protocol_version": Codec.VERSION,
			"message_type": Codec.TYPE_PING,
			"flags": 0,
			"session_id": int(_sessions.current_session.session_id),
			"controller_id": controller_id,
			"sequence": int(client.sequence),
		},
		"payload": {
			"message_type": Codec.TYPE_PING,
			"ping_id": ping_id,
			"sender_monotonic_ns": sent_ns,
		},
	})
	client.next_ping_id = (ping_id + 1) & 0xFFFF_FFFF
	client.sequence = (int(client.sequence) + 1) & 0xFFFF_FFFF
	client.next_sync_ms = Time.get_ticks_msec() + SYNC_INTERVAL_MS
	client.pending[ping_id] = sent_ns
	while client.pending.size() > 8:
		client.pending.erase(client.pending.keys()[0])
	if encoded.ok:
		_ingest.send_to(encoded.data, client.ip, int(client.port))


func restart_sync(controller_id: int) -> void:
	if not _clients.has(controller_id):
		return
	var client: Dictionary = _clients[controller_id]
	client.synchronizer = Synchronizer.new()
	client.pending.clear()
	client.next_sync_ms = 0
	request_sync(controller_id)


func _process(_delta: float) -> void:
	var now_ms := Time.get_ticks_msec()
	for raw_controller_id in _clients:
		var controller_id := int(raw_controller_id)
		if now_ms >= int(_clients[controller_id].next_sync_ms):
			request_sync(controller_id)


func _on_pairing_event(event: Dictionary) -> void:
	if int(event.state) != 1:
		return
	var controller_id := int(event.controller_id)
	var endpoint := str(event.endpoint)
	var separator := endpoint.rfind(":")
	if separator < 0:
		return
	if not _clients.has(controller_id):
		_clients[controller_id] = {
			"ip": endpoint.substr(0, separator),
			"port": int(endpoint.substr(separator + 1)),
			"synchronizer": Synchronizer.new(),
			"pending": {},
			"next_ping_id": 1,
			"sequence": 0,
			"next_sync_ms": 0,
		}
	else:
		# A reconnect must establish a fresh clock estimate. Keeping the old
		# mapping would allow motion through before the new network path is timed.
		var client: Dictionary = _clients[controller_id]
		client.ip = endpoint.substr(0, separator)
		client.port = int(endpoint.substr(separator + 1))
		client.synchronizer = Synchronizer.new()
		client.pending.clear()
		client.next_sync_ms = 0
	call_deferred("request_sync", controller_id)


func _on_message_received(
	message: Dictionary, source_ip: String, source_port: int, arrival_ns: int
) -> void:
	if int(message.header.message_type) != Codec.TYPE_PONG:
		return
	var controller_id := int(message.header.controller_id)
	if not _clients.has(controller_id):
		return
	var client: Dictionary = _clients[controller_id]
	if str(client.ip) != source_ip or int(client.port) != source_port:
		return
	var ping_id := int(message.payload.ping_id)
	if not client.pending.has(ping_id):
		return
	var t1 := int(client.pending[ping_id])
	client.pending.erase(ping_id)
	var synchronizer: ClockSynchronizer = client.synchronizer
	if synchronizer.record_exchange(
		t1,
		int(message.payload.receiver_receive_monotonic_ns),
		int(message.payload.receiver_send_monotonic_ns),
		arrival_ns
	):
		var metrics := synchronizer.snapshot()
		metrics["controller_id"] = controller_id
		metrics_updated.emit(controller_id, metrics)
