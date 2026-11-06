extends SceneTree

const Codec = preload("res://protocol/protocol_v1.gd")
const Ingest = preload("res://network/motion_ingest.gd")
const Sessions = preload("res://session/session_manager.gd")
const Pairing = preload("res://session/pairing_server.gd")
const ClockService = preload("res://network/host_clock_service.gd")
const Connections = preload("res://network/connection_manager.gd")

const PORT := 7022

var ingest: MotionIngest
var sessions: HostSessionManager
var pairing: PairingServer
var clocks: HostClockService
var connections: ControllerConnectionManager
var session: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ingest = Ingest.new()
	root.add_child(ingest)
	if ingest.start(PORT, "127.0.0.1") != OK:
		_fail("Could not bind reconnect integration port")
		return
	sessions = Sessions.new()
	root.add_child(sessions)
	session = sessions.start_new_session(
		PORT, "en0", [{"name": "en0", "friendly": "Test", "addresses": ["192.168.1.2"]}]
	)
	pairing = Pairing.new()
	root.add_child(pairing)
	pairing.attach(ingest, sessions)
	clocks = ClockService.new()
	root.add_child(clocks)
	clocks.attach(ingest, pairing, sessions)
	ingest.set_clock_service(clocks)
	connections = Connections.new()
	root.add_child(connections)
	connections.attach(ingest, pairing, clocks)
	ingest.set_connection_manager(connections)

	var first := _client()
	var first_welcome := await _hello(first, "Reconnect Phone#A1B2C3D4", 1)
	if first_welcome.is_empty(): return
	var first_id := int(first_welcome.header.controller_id)
	if int(first_welcome.payload.player) != 1:
		_fail("First controller was not assigned P1")
		return
	var first_ping := await _receive_type(first, Codec.TYPE_PING, 1000)
	if first_ping.is_empty():
		_fail("P1 did not receive initial clock PING")
		return
	first.put_packet(_status(first_id, 1, true))
	first.put_packet(_motion(first_id, 2))
	await _pump(3)
	if connections.should_accept_motion(first_id) or not ingest.pop_samples().is_empty():
		_fail("Motion passed before initial clock synchronization")
		return
	first.put_packet(_pong(first_id, first_ping, 3))
	await _wait_for_clock(first_id)
	first.put_packet(_status(first_id, 4, true))
	await _pump(3)
	if not _expect_state(first_id, "Connected", true): return
	first.put_packet(_motion(first_id, 5))
	await _pump(3)
	if ingest.pop_samples(1).size() != 1:
		_fail("Synchronized P1 motion was not accepted")
		return

	# Keep P2 live while P1 backgrounds, disconnects and reconnects.
	var second := _client()
	var second_welcome := await _hello(second, "Other Phone#E5F6A7B8", 2)
	if second_welcome.is_empty(): return
	var second_id := int(second_welcome.header.controller_id)
	var second_ping := await _receive_type(second, Codec.TYPE_PING, 1000)
	second.put_packet(_pong(second_id, second_ping, 1))
	await _wait_for_clock(second_id)
	second.put_packet(_status(second_id, 2, true))
	await _pump(3)
	if not _expect_state(second_id, "Connected", true): return

	first.put_packet(_status(first_id, 6, false))
	first.put_packet(_motion(first_id, 7))
	await _pump(3)
	if not _expect_state(first_id, "Paused", false): return
	if not ingest.pop_samples().is_empty():
		_fail("Backgrounded controller motion was accepted")
		return
	first.put_packet(_status(first_id, 8, true))
	first.put_packet(_motion(first_id, 9))
	await _pump(3)
	if not _expect_state(first_id, "Reconnecting", false): return
	if not ingest.pop_samples().is_empty():
		_fail("Resumed motion passed before a fresh clock sync")
		return
	var resume_ping := await _receive_type(first, Codec.TYPE_PING, 1000)
	if resume_ping.is_empty():
		_fail("Foreground resume did not trigger a fresh clock PING")
		return
	first.put_packet(_pong(first_id, resume_ping, 10))
	await _wait_for_clock(first_id)
	if not _expect_state(first_id, "Connected", true): return
	first.put_packet(_motion(first_id, 11))
	await _pump(3)
	if ingest.pop_samples(1).size() != 1:
		_fail("Foreground resume did not restore motion")
		return
	first.put_packet(_status(first_id, 12, false))
	await _pump(3)
	if not _expect_state(first_id, "Paused", false): return

	var last_seen := int(connections.state_for(first_id).last_seen_ms)
	connections.audit_controller(first_id, last_seen + Connections.DISCONNECTED_AFTER_MS + 1)
	if not _expect_state(first_id, "Disconnected", false): return
	var original_session_id := int(session.session_id)
	second.put_packet(_motion(second_id, 3))
	await _pump(3)
	if ingest.pop_samples(1).size() != 1 or not connections.should_accept_motion(second_id):
		_fail("P2 did not continue while P1 was disconnected")
		return

	var reconnected := _client()
	var reconnect_welcome := await _hello(reconnected, "Reconnect Phone#A1B2C3D4", 1)
	if reconnect_welcome.is_empty(): return
	if (
		int(reconnect_welcome.header.controller_id) != first_id
		or int(reconnect_welcome.payload.player) != 1
		or int(sessions.current_session.session_id) != original_session_id
	):
		_fail("Reconnect did not retain P1 identity and host session")
		return
	reconnected.put_packet(_status(first_id, 20, true))
	reconnected.put_packet(_motion(first_id, 21))
	await _pump(3)
	if not _expect_state(first_id, "Reconnecting", false): return
	if not ingest.pop_samples().is_empty():
		_fail("Reconnect motion passed before the fresh clock sync")
		return
	var reconnect_ping := await _receive_type(reconnected, Codec.TYPE_PING, 1000)
	if reconnect_ping.is_empty():
		_fail("Reconnect did not trigger a fresh clock PING")
		return
	reconnected.put_packet(_pong(first_id, reconnect_ping, 22))
	await _wait_for_clock(first_id)
	if not _expect_state(first_id, "Connected", true): return
	reconnected.put_packet(_motion(first_id, 23))
	# A packet from the old endpoint must no longer be accepted.
	first.put_packet(_motion(first_id, 14))
	await _pump(3)
	if ingest.pop_samples().size() != 1:
		_fail("Expected exactly one motion packet from the reconnected endpoint")
		return

	print(
		"TMB-021_RECONNECT_OK disconnect_ms=%d player_stable=P1 clock_gate=true background_gate=true resume_gate=true p2_continued=true stale_endpoint_rejected=true"
		% Connections.DISCONNECTED_AFTER_MS
	)
	quit(0)


func _client() -> PacketPeerUDP:
	var client := PacketPeerUDP.new()
	if client.bind(0, "127.0.0.1") != OK:
		_fail("Could not bind test client")
	client.set_dest_address("127.0.0.1", PORT)
	return client


func _hello(client: PacketPeerUDP, identity: String, platform: int) -> Dictionary:
	client.put_packet(Codec.encode({
		"header": {"protocol_version": 1, "message_type": 1, "flags": 0, "session_id": session.session_id, "controller_id": 0, "sequence": 0},
		"payload": {"message_type": 1, "pairing_secret": str(session.secret).hex_decode(), "platform": platform, "capabilities": 15, "max_sample_hz": 200, "device_model": identity, "app_version": "0.1.0", "os_version": "Test OS"},
	}).data)
	var welcome := await _receive_type(client, Codec.TYPE_WELCOME, 1000)
	if welcome.is_empty() or int(welcome.payload.session_state) != 1:
		_fail("Controller HELLO was not accepted: %s" % str(welcome))
		return {}
	return welcome


func _status(controller_id: int, sequence: int, active: bool) -> PackedByteArray:
	return Codec.encode({
		"header": {"protocol_version": 1, "message_type": 7, "flags": 0, "session_id": session.session_id, "controller_id": controller_id, "sequence": sequence},
		"payload": {"message_type": 7, "sender_monotonic_ns": Time.get_ticks_usec() * 1000, "battery_percent": 80, "sensor_state": 2, "app_state": 0 if active else 1, "pause_reason": 0 if active else 1, "actual_sample_hz": 200, "last_motion_sequence": sequence - 1},
	}).data


func _pong(controller_id: int, ping: Dictionary, sequence: int) -> PackedByteArray:
	var t1 := int(ping.payload.sender_monotonic_ns)
	return Codec.encode({
		"header": {"protocol_version": 1, "message_type": 4, "flags": 0, "session_id": session.session_id, "controller_id": controller_id, "sequence": sequence},
		"payload": {"message_type": 4, "ping_id": ping.payload.ping_id, "echo_sender_monotonic_ns": t1, "receiver_receive_monotonic_ns": t1 + 30_500_000, "receiver_send_monotonic_ns": t1 + 30_600_000},
	}).data


func _motion(controller_id: int, sequence: int) -> PackedByteArray:
	return Codec.encode({
		"header": {"protocol_version": 1, "message_type": 5, "flags": 0, "session_id": session.session_id, "controller_id": controller_id, "sequence": sequence},
		"payload": {"message_type": 5, "sensor_monotonic_ns": Time.get_ticks_usec() * 1000 + 30_000_000, "acceleration": [0.0, 0.0, -9.8], "angular_velocity": [0.0, 0.0, 0.0], "orientation": [0.0, 0.0, 0.0, 1.0], "accuracy": 3, "sensor_flags": 7},
	}).data


func _receive_type(client: PacketPeerUDP, message_type: int, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		ingest.poll_packets()
		while client.get_available_packet_count() > 0:
			var decoded := Codec.decode(client.get_packet())
			if decoded.ok and int(decoded.header.message_type) == message_type:
				return decoded
		await process_frame
	return {}


func _wait_for_clock(controller_id: int) -> void:
	var deadline := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline:
		ingest.poll_packets()
		if bool(clocks.metrics_for(controller_id).get("initialized", false)):
			return
		await process_frame
	_fail("Clock did not synchronize for controller %d" % controller_id)


func _pump(frames: int) -> void:
	for _index in frames:
		ingest.poll_packets()
		await process_frame


func _expect_state(controller_id: int, expected: String, accepting: bool) -> bool:
	var actual := connections.state_for(controller_id)
	if str(actual.state) != expected or bool(actual.accepting_motion) != accepting:
		_fail("Expected %s/%s, got %s" % [expected, accepting, str(actual)])
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
