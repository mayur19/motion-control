class_name ProtocolV1
extends RefCounted

const MAGIC := 0x4D42
const VERSION := 1
const HEADER_SIZE := 28
const MAXIMUM_PAYLOAD_SIZE := 228

const TYPE_HELLO := 1
const TYPE_WELCOME := 2
const TYPE_PING := 3
const TYPE_PONG := 4
const TYPE_MOTION := 5
const TYPE_CALIBRATION := 6
const TYPE_STATUS := 7
const TYPE_GOODBYE := 8


static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() < HEADER_SIZE:
		return _error("TOO_SHORT")
	var reader := Reader.new(data)
	if reader.u16() != MAGIC:
		return _error("BAD_MAGIC")
	var protocol_version := reader.u8()
	if protocol_version != VERSION:
		return _error("UNSUPPORTED_VERSION")
	var message_type := reader.u8()
	if message_type < TYPE_HELLO or message_type > TYPE_GOODBYE:
		return _error("UNKNOWN_MESSAGE_TYPE")
	var flags := reader.u16()
	if (flags & 0xFFFC) != 0 or (
		(message_type == TYPE_MOTION or message_type == TYPE_CALIBRATION) and flags != 0
	):
		return _error("INVALID_FLAGS")
	if reader.u16() != HEADER_SIZE:
		return _error("INVALID_HEADER_LENGTH")
	var payload_length := reader.u16()
	var expected_range := _payload_size_range(message_type)
	if (
		payload_length > MAXIMUM_PAYLOAD_SIZE
		or data.size() != HEADER_SIZE + payload_length
		or payload_length < expected_range.x
		or payload_length > expected_range.y
	):
		return _error("INVALID_PAYLOAD_LENGTH")
	if reader.u16() != 0:
		return _error("NONZERO_RESERVED")
	var session_id := reader.u64()
	var controller_id := reader.u32()
	var sequence := reader.u32()
	if session_id == 0:
		return _error("INVALID_SESSION_ID")
	if (
		(message_type == TYPE_HELLO and controller_id != 0)
		or (message_type != TYPE_HELLO and controller_id == 0)
	):
		return _error("INVALID_CONTROLLER_ID")

	var payload_result := _decode_payload(message_type, Reader.new(reader.bytes(payload_length)))
	if not payload_result.ok:
		return payload_result
	return {
		"ok": true,
		"header": {
			"protocol_version": protocol_version,
			"message_type": message_type,
			"flags": flags,
			"session_id": session_id,
			"controller_id": controller_id,
			"sequence": sequence,
		},
		"payload": payload_result.payload,
	}


static func encode(message: Dictionary) -> Dictionary:
	if not message.has("header") or not message.has("payload"):
		return _error("INVALID_VALUE")
	var header: Dictionary = message.header
	var payload: Dictionary = message.payload
	if not header.has("message_type") or not payload.has("message_type"):
		return _error("INVALID_ENUM")
	if int(header.message_type) != int(payload.message_type):
		return _error("INVALID_ENUM")
	var payload_result := _encode_payload(payload)
	if not payload_result.ok:
		return payload_result
	var payload_bytes: PackedByteArray = payload_result.data
	if payload_bytes.size() > MAXIMUM_PAYLOAD_SIZE:
		return _error("INVALID_PAYLOAD_LENGTH")

	var writer := Writer.new()
	writer.u16(MAGIC)
	writer.u8(int(header.protocol_version))
	writer.u8(int(header.message_type))
	writer.u16(int(header.flags))
	writer.u16(HEADER_SIZE)
	writer.u16(payload_bytes.size())
	writer.u16(0)
	writer.u64(int(header.session_id))
	writer.u32(int(header.controller_id))
	writer.u32(int(header.sequence))
	writer.bytes(payload_bytes)
	var encoded := writer.data
	var validation := decode(encoded)
	if not validation.ok:
		return validation
	return {"ok": true, "data": encoded}


static func _decode_payload(message_type: int, reader: Reader) -> Dictionary:
	match message_type:
		TYPE_HELLO:
			var secret := reader.bytes(16)
			var platform := reader.u8()
			var reserved_0 := reader.u8()
			var capabilities := reader.u16()
			var max_sample_hz := reader.u16()
			var model_length := reader.u8()
			var app_length := reader.u8()
			var os_length := reader.u8()
			var reserved_1 := reader.bytes(3)
			if reserved_0 != 0 or not _all_zero(reserved_1):
				return _error("NONZERO_RESERVED")
			if (
				model_length < 1 or model_length > 63
				or app_length < 1 or app_length > 31
				or os_length < 1 or os_length > 31
				or reader.remaining() != model_length + app_length + os_length
			):
				return _error("INVALID_PAYLOAD_LENGTH")
			var model_result := _decode_string(reader.bytes(model_length))
			if not model_result.ok:
				return model_result
			var app_result := _decode_string(reader.bytes(app_length))
			if not app_result.ok:
				return app_result
			var os_result := _decode_string(reader.bytes(os_length))
			if not os_result.ok:
				return os_result
			if (
				platform < 1 or platform > 2
				or (capabilities & 0xFFE0) != 0
				or (capabilities & 0x0007) != 0x0007
			):
				return _error("INVALID_ENUM")
			if _all_zero(secret) or max_sample_hz < 1 or max_sample_hz > 1000:
				return _error("INVALID_VALUE")
			return _payload({
				"message_type": TYPE_HELLO,
				"pairing_secret": secret,
				"platform": platform,
				"capabilities": capabilities,
				"max_sample_hz": max_sample_hz,
				"device_model": model_result.value,
				"app_version": app_result.value,
				"os_version": os_result.value,
			})

		TYPE_WELCOME:
			var player := reader.u8()
			var session_state := reader.u8()
			var heartbeat := reader.u16()
			var disconnect := reader.u16()
			var reorder := reader.u16()
			var host_time := reader.u64()
			var expiry := reader.u64()
			if not (
				(session_state == 1 and player >= 1 and player <= 2)
				or (session_state >= 2 and session_state <= 5 and player == 0)
			):
				return _error("INVALID_ENUM")
			if (
				heartbeat < 100 or heartbeat > 5000
				or disconnect < heartbeat * 2 or disconnect > 30000
				or reorder > 64 or host_time == 0 or expiry == 0
			):
				return _error("INVALID_VALUE")
			return _payload({
				"message_type": TYPE_WELCOME,
				"player": player,
				"session_state": session_state,
				"heartbeat_interval_ms": heartbeat,
				"disconnect_timeout_ms": disconnect,
				"reorder_window_packets": reorder,
				"host_monotonic_ns": host_time,
				"session_expires_unix_s": expiry,
			})

		TYPE_PING:
			var ping_id := reader.u32()
			if reader.u32() != 0:
				return _error("NONZERO_RESERVED")
			var ping_time := reader.u64()
			if ping_time == 0:
				return _error("INVALID_VALUE")
			return _payload({
				"message_type": TYPE_PING,
				"ping_id": ping_id,
				"sender_monotonic_ns": ping_time,
			})

		TYPE_PONG:
			var pong_id := reader.u32()
			if reader.u32() != 0:
				return _error("NONZERO_RESERVED")
			var echo := reader.u64()
			var receive := reader.u64()
			var send := reader.u64()
			if echo == 0 or receive == 0 or send < receive:
				return _error("INVALID_VALUE")
			return _payload({
				"message_type": TYPE_PONG,
				"ping_id": pong_id,
				"echo_sender_monotonic_ns": echo,
				"receiver_receive_monotonic_ns": receive,
				"receiver_send_monotonic_ns": send,
			})

		TYPE_MOTION:
			var motion_time := reader.u64()
			var acceleration := reader.floats(3)
			var angular_velocity := reader.floats(3)
			var orientation := reader.floats(4)
			var accuracy := reader.u8()
			var sensor_flags := reader.u8()
			if reader.u16() != 0:
				return _error("NONZERO_RESERVED")
			if (
				not [0, 1, 2, 3, 255].has(accuracy)
				or (sensor_flags & 0xE0) != 0
				or (sensor_flags & 0x07) != 0x07
			):
				return _error("INVALID_ENUM")
			var finite_result := _finite(acceleration + angular_velocity + orientation)
			if not finite_result.ok:
				return finite_result
			var quaternion_result := _quaternion(orientation)
			if not quaternion_result.ok:
				return quaternion_result
			if (
				motion_time == 0
				or _outside_limit(acceleration, 200.0)
				or _outside_limit(angular_velocity, 100.0)
			):
				return _error("INVALID_VALUE")
			return _payload({
				"message_type": TYPE_MOTION,
				"sensor_monotonic_ns": motion_time,
				"acceleration": acceleration,
				"angular_velocity": angular_velocity,
				"orientation": orientation,
				"accuracy": accuracy,
				"sensor_flags": sensor_flags,
			})

		TYPE_CALIBRATION:
			var calibration_time := reader.u64()
			var neutral := reader.floats(4)
			var accel_bias := reader.floats(3)
			var gyro_bias := reader.floats(3)
			var quality := reader.f32()
			var calibration_result := reader.u8()
			var handedness := reader.u8()
			if not _all_zero(reader.bytes(2)):
				return _error("NONZERO_RESERVED")
			if not [1, 2].has(calibration_result) or not [1, 2].has(handedness):
				return _error("INVALID_ENUM")
			var calibration_finite := _finite(neutral + accel_bias + gyro_bias + [quality])
			if not calibration_finite.ok:
				return calibration_finite
			var neutral_result := _quaternion(neutral)
			if not neutral_result.ok:
				return neutral_result
			if (
				calibration_time == 0
				or _outside_limit(accel_bias, 50.0)
				or _outside_limit(gyro_bias, 20.0)
				or quality < 0.0 or quality > 1.0
			):
				return _error("INVALID_VALUE")
			return _payload({
				"message_type": TYPE_CALIBRATION,
				"sensor_monotonic_ns": calibration_time,
				"neutral_orientation": neutral,
				"acceleration_bias": accel_bias,
				"gyroscope_bias": gyro_bias,
				"quality": quality,
				"result": calibration_result,
				"handedness": handedness,
			})

		TYPE_STATUS:
			var status_time := reader.u64()
			var battery := reader.u8()
			var sensor_state := reader.u8()
			var app_state := reader.u8()
			var pause_reason := reader.u8()
			var sample_hz := reader.u16()
			if reader.u16() != 0:
				return _error("NONZERO_RESERVED")
			var last_motion := reader.u32()
			if sensor_state > 3 or app_state > 2 or pause_reason > 5:
				return _error("INVALID_ENUM")
			if (
				(battery > 100 and battery != 255)
				or sample_hz > 1000 or status_time == 0
				or (app_state == 0 and pause_reason != 0)
			):
				return _error("INVALID_VALUE")
			return _payload({
				"message_type": TYPE_STATUS,
				"sender_monotonic_ns": status_time,
				"battery_percent": battery,
				"sensor_state": sensor_state,
				"app_state": app_state,
				"pause_reason": pause_reason,
				"actual_sample_hz": sample_hz,
				"last_motion_sequence": last_motion,
			})

		TYPE_GOODBYE:
			var reason := reader.u8()
			if not _all_zero(reader.bytes(3)):
				return _error("NONZERO_RESERVED")
			var last_sequence := reader.u32()
			var goodbye_time := reader.u64()
			if reason < 1 or reason > 5:
				return _error("INVALID_ENUM")
			if goodbye_time == 0:
				return _error("INVALID_VALUE")
			return _payload({
				"message_type": TYPE_GOODBYE,
				"reason": reason,
				"last_sequence": last_sequence,
				"sender_monotonic_ns": goodbye_time,
			})

	return _error("UNKNOWN_MESSAGE_TYPE")


static func _encode_payload(payload: Dictionary) -> Dictionary:
	var writer := Writer.new()
	match int(payload.message_type):
		TYPE_HELLO:
			var secret: PackedByteArray = payload.pairing_secret
			var model := String(payload.device_model).to_utf8_buffer()
			var app := String(payload.app_version).to_utf8_buffer()
			var os_version := String(payload.os_version).to_utf8_buffer()
			writer.bytes(secret)
			writer.u8(int(payload.platform))
			writer.u8(0)
			writer.u16(int(payload.capabilities))
			writer.u16(int(payload.max_sample_hz))
			writer.u8(model.size())
			writer.u8(app.size())
			writer.u8(os_version.size())
			writer.bytes(PackedByteArray([0, 0, 0]))
			writer.bytes(model)
			writer.bytes(app)
			writer.bytes(os_version)
		TYPE_WELCOME:
			writer.u8(int(payload.player))
			writer.u8(int(payload.session_state))
			writer.u16(int(payload.heartbeat_interval_ms))
			writer.u16(int(payload.disconnect_timeout_ms))
			writer.u16(int(payload.reorder_window_packets))
			writer.u64(int(payload.host_monotonic_ns))
			writer.u64(int(payload.session_expires_unix_s))
		TYPE_PING:
			writer.u32(int(payload.ping_id))
			writer.u32(0)
			writer.u64(int(payload.sender_monotonic_ns))
		TYPE_PONG:
			writer.u32(int(payload.ping_id))
			writer.u32(0)
			writer.u64(int(payload.echo_sender_monotonic_ns))
			writer.u64(int(payload.receiver_receive_monotonic_ns))
			writer.u64(int(payload.receiver_send_monotonic_ns))
		TYPE_MOTION:
			writer.u64(int(payload.sensor_monotonic_ns))
			writer.floats(payload.acceleration)
			writer.floats(payload.angular_velocity)
			writer.floats(payload.orientation)
			writer.u8(int(payload.accuracy))
			writer.u8(int(payload.sensor_flags))
			writer.u16(0)
		TYPE_CALIBRATION:
			writer.u64(int(payload.sensor_monotonic_ns))
			writer.floats(payload.neutral_orientation)
			writer.floats(payload.acceleration_bias)
			writer.floats(payload.gyroscope_bias)
			writer.f32(float(payload.quality))
			writer.u8(int(payload.result))
			writer.u8(int(payload.handedness))
			writer.bytes(PackedByteArray([0, 0]))
		TYPE_STATUS:
			writer.u64(int(payload.sender_monotonic_ns))
			writer.u8(int(payload.battery_percent))
			writer.u8(int(payload.sensor_state))
			writer.u8(int(payload.app_state))
			writer.u8(int(payload.pause_reason))
			writer.u16(int(payload.actual_sample_hz))
			writer.u16(0)
			writer.u32(int(payload.last_motion_sequence))
		TYPE_GOODBYE:
			writer.u8(int(payload.reason))
			writer.bytes(PackedByteArray([0, 0, 0]))
			writer.u32(int(payload.last_sequence))
			writer.u64(int(payload.sender_monotonic_ns))
		_:
			return _error("UNKNOWN_MESSAGE_TYPE")
	return {"ok": true, "data": writer.data}


static func _payload_size_range(message_type: int) -> Vector2i:
	match message_type:
		TYPE_HELLO: return Vector2i(28, 153)
		TYPE_WELCOME: return Vector2i(24, 24)
		TYPE_PING: return Vector2i(16, 16)
		TYPE_PONG: return Vector2i(32, 32)
		TYPE_MOTION: return Vector2i(52, 52)
		TYPE_CALIBRATION: return Vector2i(56, 56)
		TYPE_STATUS: return Vector2i(20, 20)
		TYPE_GOODBYE: return Vector2i(16, 16)
	return Vector2i.ZERO


static func _decode_string(bytes: PackedByteArray) -> Dictionary:
	if bytes.has(0):
		return _error("INVALID_UTF8")
	var value := bytes.get_string_from_utf8()
	if value.is_empty() or value.to_utf8_buffer() != bytes:
		return _error("INVALID_UTF8")
	return {"ok": true, "value": value}


static func _finite(values: Array) -> Dictionary:
	for value in values:
		if not is_finite(float(value)):
			return _error("NON_FINITE_FLOAT")
	return {"ok": true}


static func _quaternion(values: Array) -> Dictionary:
	var magnitude_squared := 0.0
	for value in values:
		magnitude_squared += float(value) * float(value)
	var magnitude := sqrt(magnitude_squared)
	if magnitude < 0.98 or magnitude > 1.02:
		return _error("INVALID_QUATERNION")
	return {"ok": true}


static func _outside_limit(values: Array, limit: float) -> bool:
	for value in values:
		if abs(float(value)) > limit:
			return true
	return false


static func _all_zero(bytes: PackedByteArray) -> bool:
	for byte in bytes:
		if byte != 0:
			return false
	return true


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}


static func _payload(value: Dictionary) -> Dictionary:
	return {"ok": true, "payload": value}


class Reader:
	var data: PackedByteArray
	var position := 0

	func _init(value: PackedByteArray) -> void:
		data = value

	func remaining() -> int:
		return data.size() - position

	func u8() -> int:
		var value := data[position]
		position += 1
		return value

	func u16() -> int:
		return (u8() << 8) | u8()

	func u32() -> int:
		return (u8() << 24) | (u8() << 16) | (u8() << 8) | u8()

	func u64() -> int:
		var high := u32()
		var low := u32()
		return (high << 32) | low

	func f32() -> float:
		var network_bytes := bytes(4)
		var little_endian := PackedByteArray([
			network_bytes[3], network_bytes[2], network_bytes[1], network_bytes[0]
		])
		return little_endian.decode_float(0)

	func floats(count: int) -> Array:
		var result: Array = []
		for index in count:
			result.append(f32())
		return result

	func bytes(count: int) -> PackedByteArray:
		var result := data.slice(position, position + count)
		position += count
		return result


class Writer:
	var data := PackedByteArray()

	func u8(value: int) -> void:
		data.append(value & 0xFF)

	func u16(value: int) -> void:
		u8(value >> 8)
		u8(value)

	func u32(value: int) -> void:
		u8(value >> 24)
		u8(value >> 16)
		u8(value >> 8)
		u8(value)

	func u64(value: int) -> void:
		u32(value >> 32)
		u32(value)

	func f32(value: float) -> void:
		var canonical := 0.0 if value == 0.0 else value
		var little_endian := PackedByteArray()
		little_endian.resize(4)
		little_endian.encode_float(0, canonical)
		data.append(little_endian[3])
		data.append(little_endian[2])
		data.append(little_endian[1])
		data.append(little_endian[0])

	func floats(values: Array) -> void:
		for value in values:
			f32(float(value))

	func bytes(value: PackedByteArray) -> void:
		data.append_array(value)
