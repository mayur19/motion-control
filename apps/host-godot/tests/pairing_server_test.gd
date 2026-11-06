extends SceneTree

const Codec = preload("res://protocol/protocol_v1.gd")
const Ingest = preload("res://network/motion_ingest.gd")
const Sessions = preload("res://session/session_manager.gd")
const Pairing = preload("res://session/pairing_server.gd")

var _sequence := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ingest := Ingest.new()
	root.add_child(ingest)
	if ingest.start(7019, "127.0.0.1") != OK:
		_fail("Could not bind pairing test server")
		return
	var sessions := Sessions.new()
	root.add_child(sessions)
	var session := sessions.start_new_session(
		7019,
		"en0",
		[{"name": "en0", "friendly": "Test LAN", "addresses": ["127.0.0.2"]}],
		int(Time.get_unix_time_from_system())
	)
	# The selector intentionally rejects loopback, so inject the transport address
	# while retaining the generated session credentials for this local UDP test.
	sessions.current_session.address = "127.0.0.1"
	var pairing := Pairing.new()
	root.add_child(pairing)
	pairing.attach(ingest, sessions)

	var first := _client()
	var second := _client()
	var third := _client()
	var attacker := _client()
	var first_welcome: Dictionary = await _exchange(first, session.secret, session.session_id, 1)
	var second_welcome: Dictionary = await _exchange(second, session.secret, session.session_id, 2)
	var retry_welcome: Dictionary = await _exchange(first, session.secret, session.session_id, 1)
	var full_welcome: Dictionary = await _exchange(
		third, session.secret, session.session_id, 1, "Third Controller"
	)
	var wrong_welcome: Dictionary = await _exchange(
		attacker, "01" + "00".repeat(15), session.session_id, 2
	)

	if not _expect(first_welcome, 1, 1): return
	if not _expect(second_welcome, 1, 2): return
	if not _expect(retry_welcome, 1, 1): return
	if int(retry_welcome.header.controller_id) != int(first_welcome.header.controller_id):
		_fail("HELLO retry changed the stable controller assignment")
		return
	if not _expect(full_welcome, 4, 0): return
	if not _expect(wrong_welcome, 3, 0): return

	# A known controller may reclaim its bounded reservation even after the QR
	# credential's public join window expires. Unknown controllers remain barred.
	pairing.mark_disconnected(int(first_welcome.header.controller_id))
	sessions.current_session.expires_unix_s = 1
	var reconnecting := _client()
	var reconnect_welcome: Dictionary = await _exchange(
		reconnecting, session.secret, session.session_id, 1
	)
	if not _expect(reconnect_welcome, 1, 1): return
	if int(reconnect_welcome.header.controller_id) != int(first_welcome.header.controller_id):
		_fail("Expired-code reconnect did not retain the controller assignment")
		return

	# A controller still holding its slot (backgrounded briefly, never timed out)
	# re-HELLOs from a new socket after the QR expired: it keeps its assignment.
	var resumed := _client()
	var resumed_welcome: Dictionary = await _exchange(
		resumed, session.secret, session.session_id, 2
	)
	if not _expect(resumed_welcome, 1, 2): return
	if int(resumed_welcome.header.controller_id) != int(second_welcome.header.controller_id):
		_fail("Active controller lost its assignment re-HELLOing after QR expiry")
		return

	pairing.reset()
	var expired_welcome: Dictionary = await _exchange(third, session.secret, session.session_id, 1)
	if not _expect(expired_welcome, 2, 0): return

	print(
		"TMB-019_PAIRING_SERVER_OK first=P1 second=P2 retry_stable=true expired_reconnect=P1 active_resume=P2 third=FULL wrong=SECRET expired=EXPIRED"
	)
	quit(0)


func _client() -> PacketPeerUDP:
	var client := PacketPeerUDP.new()
	if client.bind(0, "127.0.0.1") != OK:
		_fail("Could not bind test client")
	client.set_dest_address("127.0.0.1", 7019)
	return client


func _exchange(
	client: PacketPeerUDP,
	secret_hex: String,
	session_id: int,
	platform: int,
	device_model: String = ""
) -> Dictionary:
	var encoded := Codec.encode({
		"header": {
			"protocol_version": Codec.VERSION,
			"message_type": Codec.TYPE_HELLO,
			"flags": 0,
			"session_id": session_id,
			"controller_id": 0,
			"sequence": _sequence,
		},
		"payload": {
			"message_type": Codec.TYPE_HELLO,
			"pairing_secret": secret_hex.hex_decode(),
			"platform": platform,
			"capabilities": 0x0F,
			"max_sample_hz": 200,
			"device_model": (
				device_model if not device_model.is_empty() else "Test Controller %d" % platform
			),
			"app_version": "0.1.0",
			"os_version": "Test OS",
		},
	})
	_sequence += 1
	if not encoded.ok:
		_fail("Could not encode HELLO: %s" % str(encoded))
		return {}
	var send_error := client.put_packet(encoded.data)
	if send_error != OK:
		_fail("Could not send HELLO: %s" % error_string(send_error))
		return {}
	var deadline := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline:
		ingest_poll()
		if client.get_available_packet_count() > 0:
			var decoded := Codec.decode(client.get_packet())
			if decoded.ok:
				return decoded
		await process_frame
	_fail("Timed out waiting for WELCOME")
	return {}


func ingest_poll() -> void:
	for child in root.get_children():
		if child is MotionIngest:
			child.poll_packets()


func _expect(welcome: Dictionary, state: int, player: int) -> bool:
	if welcome.is_empty():
		return false
	if (
		int(welcome.header.message_type) != Codec.TYPE_WELCOME
		or int(welcome.payload.session_state) != state
		or int(welcome.payload.player) != player
	):
		_fail("Unexpected WELCOME: %s" % str(welcome))
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
