extends SceneTree

const Codec = preload("res://protocol/protocol_v1.gd")
const Ingest = preload("res://network/motion_ingest.gd")
const Sessions = preload("res://session/session_manager.gd")
const Pairing = preload("res://session/pairing_server.gd")
const ClockService = preload("res://network/host_clock_service.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ingest := Ingest.new()
	root.add_child(ingest)
	if ingest.start(7021, "127.0.0.1") != OK:
		_fail("Could not bind clock integration port")
		return
	var sessions := Sessions.new()
	root.add_child(sessions)
	var session := sessions.start_new_session(
		7021, "en0", [{"name": "en0", "friendly": "Test", "addresses": ["192.168.1.2"]}]
	)
	var pairing := Pairing.new()
	root.add_child(pairing)
	pairing.attach(ingest, sessions)
	var clocks := ClockService.new()
	root.add_child(clocks)
	clocks.attach(ingest, pairing, sessions)
	ingest.set_clock_service(clocks)

	var client := PacketPeerUDP.new()
	client.bind(0, "127.0.0.1")
	client.set_dest_address("127.0.0.1", 7021)
	client.put_packet(_hello(session))
	var welcome: Dictionary = await _receive_type(client, ingest, Codec.TYPE_WELCOME, 1000)
	if welcome.is_empty() or int(welcome.payload.session_state) != 1:
		_fail("Controller did not pair before clock sync")
		return
	var controller_id := int(welcome.header.controller_id)
	var ping: Dictionary = await _receive_type(client, ingest, Codec.TYPE_PING, 1000)
	if ping.is_empty():
		_fail("Host did not request immediate clock sync")
		return
	var t1 := int(ping.payload.sender_monotonic_ns)
	var simulated_offset_ns := 50_000_000
	var t2 := t1 + simulated_offset_ns + 500_000
	var t3 := t2 + 100_000
	client.put_packet(_pong(session, controller_id, ping, t2, t3))
	var deadline := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline and not clocks.metrics_for(controller_id).get("initialized", false):
		ingest.poll_packets()
		await process_frame
	var metrics := clocks.metrics_for(controller_id)
	if not metrics.get("initialized", false) or absf(float(metrics.offset_ms) - 50.0) > 2.0:
		_fail("Live PING/PONG estimate out of tolerance: %s" % str(metrics))
		return

	var accepted_sample: Dictionary = {}
	var controller_now := Time.get_ticks_usec() * 1000 + int(round(float(metrics.offset_ms) * 1_000_000.0))
	client.put_packet(_motion(session, controller_id, controller_now))
	deadline = Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline and accepted_sample.is_empty():
		ingest.poll_packets()
		var samples := ingest.pop_samples(1)
		if not samples.is_empty():
			accepted_sample = samples[0]
		await process_frame
	if accepted_sample.is_empty() or not accepted_sample.clock_synchronized:
		_fail("MOTION sample was not clock adjusted: %s" % str(accepted_sample))
		return
	if float(accepted_sample.adjusted_sample_age_ms) < 0.0 or float(accepted_sample.adjusted_sample_age_ms) > 10.0:
		_fail("Adjusted sample age is implausible: %s" % str(accepted_sample))
		return
	print(
		"TMB-020_CLOCK_INTEGRATION_OK offset_ms=%.3f rtt_ms=%.3f adjusted_age_ms=%.3f" % [
			float(metrics.offset_ms), float(metrics.rtt_ms), float(accepted_sample.adjusted_sample_age_ms),
		]
	)
	quit(0)


func _receive_type(
	client: PacketPeerUDP, ingest: MotionIngest, message_type: int, timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		ingest.poll_packets()
		while client.get_available_packet_count() > 0:
			var decoded := Codec.decode(client.get_packet())
			if decoded.ok and int(decoded.header.message_type) == message_type:
				return decoded
		await process_frame
	return {}


func _hello(session: Dictionary) -> PackedByteArray:
	return Codec.encode({
		"header": {"protocol_version": 1, "message_type": 1, "flags": 0, "session_id": session.session_id, "controller_id": 0, "sequence": 0},
		"payload": {"message_type": 1, "pairing_secret": str(session.secret).hex_decode(), "platform": 1, "capabilities": 15, "max_sample_hz": 200, "device_model": "Clock Test", "app_version": "0.1.0", "os_version": "Test OS"},
	}).data


func _pong(
	session: Dictionary, controller_id: int, ping: Dictionary, receive_ns: int, send_ns: int
) -> PackedByteArray:
	return Codec.encode({
		"header": {"protocol_version": 1, "message_type": 4, "flags": 0, "session_id": session.session_id, "controller_id": controller_id, "sequence": 1},
		"payload": {"message_type": 4, "ping_id": ping.payload.ping_id, "echo_sender_monotonic_ns": ping.payload.sender_monotonic_ns, "receiver_receive_monotonic_ns": receive_ns, "receiver_send_monotonic_ns": send_ns},
	}).data


func _motion(session: Dictionary, controller_id: int, sensor_ns: int) -> PackedByteArray:
	return Codec.encode({
		"header": {"protocol_version": 1, "message_type": 5, "flags": 0, "session_id": session.session_id, "controller_id": controller_id, "sequence": 2},
		"payload": {"message_type": 5, "sensor_monotonic_ns": sensor_ns, "acceleration": [0.0, 0.0, -9.8], "angular_velocity": [0.0, 0.0, 0.0], "orientation": [0.0, 0.0, 0.0, 1.0], "accuracy": 3, "sensor_flags": 7},
	}).data


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
