extends SceneTree

## Host→controller liveness: STATUS every 500 ms to each live controller's
## control endpoint, never to Disconnected controllers, and one GOODBYE
## (host shutdown) per controller on close, after which STATUS stops.

const Codec = preload("res://protocol/protocol_v1.gd")
const Heartbeat = preload("res://network/host_heartbeat.gd")

const SESSION_ID := 72623859790382856
const LIVE_ID := 168496141
const PAUSED_ID := 268496141
const GONE_ID := 368496141


class FakeSender:
	var sent: Array = []

	func send_to(packet: PackedByteArray, ip: String, port: int) -> Error:
		sent.append({"packet": packet, "ip": ip, "port": port})
		return OK

	func snapshot() -> Dictionary:
		return {"controllers": {LIVE_ID: {"latest_sequence": 41}}}


class FakeConnections:
	func snapshot() -> Dictionary:
		return {
			LIVE_ID: {"state": "Connected", "control_endpoint": "192.0.2.4:50001"},
			PAUSED_ID: {"state": "Paused", "control_endpoint": "192.0.2.5:50002"},
			GONE_ID: {"state": "Disconnected", "control_endpoint": "192.0.2.6:50003"},
		}


class FakeSessions:
	var current_session := {"session_id": SESSION_ID}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sender := FakeSender.new()
	var heartbeat := Heartbeat.new()
	heartbeat.set_process(false)
	heartbeat.attach(sender, FakeConnections.new(), FakeSessions.new())
	root.add_child(heartbeat)

	if heartbeat.tick(1000) != 2:
		return _fail("first tick should reach the two live controllers")
	if heartbeat.tick(1499) != 0:
		return _fail("STATUS sent before the 500 ms interval elapsed")
	if heartbeat.tick(1500) != 2:
		return _fail("second STATUS not sent at the interval")
	for record in sender.sent:
		if int(record.port) == 50003:
			return _fail("STATUS sent to a Disconnected controller")
	var status := _decode(sender.sent[0].packet)
	if int(status.header.message_type) != Codec.TYPE_STATUS:
		return _fail("heartbeat is not STATUS")
	if int(status.header.session_id) != SESSION_ID:
		return _fail("STATUS session id wrong")
	var addressed := {}
	for record in sender.sent.slice(0, 2):
		var decoded := _decode(record.packet)
		addressed[int(decoded.header.controller_id)] = decoded
	if not addressed.has(LIVE_ID) or not addressed.has(PAUSED_ID):
		return _fail("STATUS not addressed per controller: %s" % str(addressed.keys()))
	var live: Dictionary = addressed[LIVE_ID].payload
	if int(live.battery_percent) != 255 or int(live.last_motion_sequence) != 41:
		return _fail("host STATUS fields wrong: %s" % str(live))
	if int(addressed[PAUSED_ID].payload.last_motion_sequence) != 0:
		return _fail("controller without motion should report sequence 0")

	var before_goodbye := sender.sent.size()
	if heartbeat.send_goodbye() != 2:
		return _fail("GOODBYE not sent to live controllers")
	if heartbeat.send_goodbye() != 0:
		return _fail("GOODBYE sent twice")
	var goodbye := _decode(sender.sent[before_goodbye].packet)
	if int(goodbye.header.message_type) != Codec.TYPE_GOODBYE or int(goodbye.payload.reason) != 3:
		return _fail("GOODBYE wrong: %s" % str(goodbye))
	if heartbeat.tick(5000) != 0:
		return _fail("STATUS continued after GOODBYE")
	print("TMB-021_HOST_HEARTBEAT_OK interval_ms=500 goodbye_reason=3 skips_disconnected=true")
	quit(0)


func _decode(packet: PackedByteArray) -> Dictionary:
	var decoded := Codec.decode(packet)
	if not decoded.ok:
		push_error("decode failed: %s" % str(decoded))
	return decoded


func _fail(message: String) -> void:
	push_error(message)
	print("TMB-021_HOST_HEARTBEAT_FAIL")
	quit(1)
