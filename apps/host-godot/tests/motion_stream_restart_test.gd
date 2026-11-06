extends SceneTree

## Reproduces the 2026-11-06 physical iPhone reconnect: the controller keeps its
## controller ID but opens a new motion socket whose sequence restarts at 0.
## The host must treat that as a new sender stream, not as ~1650 reordered
## packets, while keeping cumulative loss from the previous stream.

const Codec = preload("res://protocol/protocol_v1.gd")
const Ingest = preload("res://network/motion_ingest.gd")

const CONTROLLER_ID := 201461948
const SESSION_ID := 72623859790382856
const OLD_ENDPOINT := "192.0.2.4:54212"
const NEW_ENDPOINT := "192.0.2.4:59974"
const OLD_LAST_SEQUENCE := 1648
const NEW_PACKETS := 200


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ingest := Ingest.new()
	root.add_child(ingest)
	var arrival_ns := 1_000_000_000
	for sequence in OLD_LAST_SEQUENCE + 1:
		if sequence == 100 or sequence == 101:
			continue  # two genuinely lost packets on the old stream
		ingest._process_packet(_motion(sequence), OLD_ENDPOINT, arrival_ns)
		arrival_ns += 10_000_000
	var before: Dictionary = ingest.snapshot().controllers[CONTROLLER_ID]
	if int(before.loss) != 2 or int(before.reordered) != 0:
		_fail("old stream baseline wrong: %s" % str(before))
		return

	for sequence in NEW_PACKETS:
		ingest._process_packet(_motion(sequence), NEW_ENDPOINT, arrival_ns)
		arrival_ns += 10_000_000
	var after: Dictionary = ingest.snapshot().controllers[CONTROLLER_ID]
	if int(after.reordered) != 0:
		_fail("restarted stream counted as reordered: %s" % str(after))
		return
	if int(after.duplicates) != 0:
		_fail("restarted stream counted as duplicates: %s" % str(after))
		return
	if int(after.loss) != 2:
		_fail("cumulative loss not preserved across stream restart: %s" % str(after))
		return
	if int(after.latest_sequence) != NEW_PACKETS - 1:
		_fail("new stream sequence not tracked: %s" % str(after))
		return
	if int(after.received) != OLD_LAST_SEQUENCE - 1 + NEW_PACKETS:
		_fail("received total wrong: %s" % str(after))
		return

	# Within one stream, a late packet is still reordered and a repeat is a duplicate.
	ingest._process_packet(_motion(NEW_PACKETS + 1), NEW_ENDPOINT, arrival_ns)
	ingest._process_packet(_motion(NEW_PACKETS), NEW_ENDPOINT, arrival_ns + 1)
	ingest._process_packet(_motion(NEW_PACKETS), NEW_ENDPOINT, arrival_ns + 2)
	var tail: Dictionary = ingest.snapshot().controllers[CONTROLLER_ID]
	if int(tail.reordered) != 1 or int(tail.duplicates) != 1 or int(tail.loss) != 2:
		_fail("same-stream ordering metrics wrong: %s" % str(tail))
		return
	print("TMB-021_MOTION_STREAM_RESTART_OK reordered=0 loss_preserved=2")
	quit(0)


func _motion(sequence: int) -> PackedByteArray:
	return Codec.encode({
		"header": {"protocol_version": 1, "message_type": 5, "flags": 0, "session_id": SESSION_ID, "controller_id": CONTROLLER_ID, "sequence": sequence},
		"payload": {"message_type": 5, "sensor_monotonic_ns": 5_000_000_000 + sequence * 10_000_000, "acceleration": [0.0, 0.0, -9.8], "angular_velocity": [0.0, 0.0, 0.0], "orientation": [0.0, 0.0, 0.0, 1.0], "accuracy": 3, "sensor_flags": 7},
	}).data


func _fail(message: String) -> void:
	push_error(message)
	print("TMB-021_MOTION_STREAM_RESTART_FAIL")
	quit(1)
