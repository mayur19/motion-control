package com.motionbadminton.controller.android.protocol

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction
import kotlin.math.abs
import kotlin.math.sqrt

object ProtocolV1 {
    const val MAGIC = 0x4D42
    const val VERSION = 1
    const val HEADER_SIZE = 28
    const val MAXIMUM_PAYLOAD_SIZE = 228

    enum class Rejection {
        TOO_SHORT,
        BAD_MAGIC,
        UNSUPPORTED_VERSION,
        UNKNOWN_MESSAGE_TYPE,
        INVALID_FLAGS,
        INVALID_HEADER_LENGTH,
        INVALID_PAYLOAD_LENGTH,
        NONZERO_RESERVED,
        INVALID_SESSION_ID,
        INVALID_CONTROLLER_ID,
        INVALID_UTF8,
        INVALID_ENUM,
        NON_FINITE_FLOAT,
        INVALID_QUATERNION,
        INVALID_VALUE,
    }

    class CodecException(val rejection: Rejection) : IllegalArgumentException(rejection.name)

    enum class MessageType(val code: Int, val payloadRange: IntRange) {
        HELLO(1, 28..153),
        WELCOME(2, 24..24),
        PING(3, 16..16),
        PONG(4, 32..32),
        MOTION(5, 52..52),
        CALIBRATION(6, 56..56),
        STATUS(7, 20..20),
        GOODBYE(8, 16..16);

        companion object {
            fun fromCode(code: Int): MessageType? = entries.firstOrNull { it.code == code }
        }
    }

    data class Header(
        val protocolVersion: Int,
        val messageType: MessageType,
        val flags: Int,
        val sessionId: ULong,
        val controllerId: UInt,
        val sequence: UInt,
    )

    sealed interface Payload {
        val messageType: MessageType
    }

    data class Hello(
        val pairingSecret: ByteArray,
        val platform: Int,
        val capabilities: Int,
        val maxSampleHz: Int,
        val deviceModel: String,
        val appVersion: String,
        val osVersion: String,
    ) : Payload {
        override val messageType = MessageType.HELLO
        override fun equals(other: Any?): Boolean =
            other is Hello && pairingSecret.contentEquals(other.pairingSecret) &&
                platform == other.platform && capabilities == other.capabilities &&
                maxSampleHz == other.maxSampleHz && deviceModel == other.deviceModel &&
                appVersion == other.appVersion && osVersion == other.osVersion

        override fun hashCode(): Int = pairingSecret.contentHashCode()
    }

    data class Welcome(
        val player: Int,
        val sessionState: Int,
        val heartbeatIntervalMs: Int,
        val disconnectTimeoutMs: Int,
        val reorderWindowPackets: Int,
        val hostMonotonicNs: ULong,
        val sessionExpiresUnixS: ULong,
    ) : Payload { override val messageType = MessageType.WELCOME }

    data class Ping(val pingId: UInt, val senderMonotonicNs: ULong) : Payload {
        override val messageType = MessageType.PING
    }

    data class Pong(
        val pingId: UInt,
        val echoSenderMonotonicNs: ULong,
        val receiverReceiveMonotonicNs: ULong,
        val receiverSendMonotonicNs: ULong,
    ) : Payload { override val messageType = MessageType.PONG }

    data class Motion(
        val sensorMonotonicNs: ULong,
        val acceleration: List<Float>,
        val angularVelocity: List<Float>,
        val orientation: List<Float>,
        val accuracy: Int,
        val sensorFlags: Int,
    ) : Payload { override val messageType = MessageType.MOTION }

    data class Calibration(
        val sensorMonotonicNs: ULong,
        val neutralOrientation: List<Float>,
        val accelerationBias: List<Float>,
        val gyroscopeBias: List<Float>,
        val quality: Float,
        val result: Int,
        val handedness: Int,
    ) : Payload { override val messageType = MessageType.CALIBRATION }

    data class Status(
        val senderMonotonicNs: ULong,
        val batteryPercent: Int,
        val sensorState: Int,
        val appState: Int,
        val pauseReason: Int,
        val actualSampleHz: Int,
        val lastMotionSequence: UInt,
    ) : Payload { override val messageType = MessageType.STATUS }

    data class Goodbye(
        val reason: Int,
        val lastSequence: UInt,
        val senderMonotonicNs: ULong,
    ) : Payload { override val messageType = MessageType.GOODBYE }

    data class Message(val header: Header, val payload: Payload)

    fun decode(data: ByteArray): Message {
        if (data.size < HEADER_SIZE) reject(Rejection.TOO_SHORT)
        val reader = Reader(data)
        if (reader.u16() != MAGIC) reject(Rejection.BAD_MAGIC)
        val protocolVersion = reader.u8()
        if (protocolVersion != VERSION) reject(Rejection.UNSUPPORTED_VERSION)
        val messageType = MessageType.fromCode(reader.u8()) ?: reject(Rejection.UNKNOWN_MESSAGE_TYPE)
        val flags = reader.u16()
        if ((flags and 0xFFFC) != 0 ||
            ((messageType == MessageType.MOTION || messageType == MessageType.CALIBRATION) && flags != 0)
        ) reject(Rejection.INVALID_FLAGS)
        if (reader.u16() != HEADER_SIZE) reject(Rejection.INVALID_HEADER_LENGTH)
        val payloadLength = reader.u16()
        if (payloadLength > MAXIMUM_PAYLOAD_SIZE ||
            data.size != HEADER_SIZE + payloadLength ||
            payloadLength !in messageType.payloadRange
        ) reject(Rejection.INVALID_PAYLOAD_LENGTH)
        if (reader.u16() != 0) reject(Rejection.NONZERO_RESERVED)
        val sessionId = reader.u64()
        val controllerId = reader.u32()
        val sequence = reader.u32()
        if (sessionId == 0uL) reject(Rejection.INVALID_SESSION_ID)
        if ((messageType == MessageType.HELLO && controllerId != 0u) ||
            (messageType != MessageType.HELLO && controllerId == 0u)
        ) reject(Rejection.INVALID_CONTROLLER_ID)

        val payload = decodePayload(messageType, Reader(reader.bytes(payloadLength)))
        return Message(
            Header(protocolVersion, messageType, flags, sessionId, controllerId, sequence),
            payload,
        )
    }

    fun encode(message: Message): ByteArray {
        if (message.header.messageType != message.payload.messageType) reject(Rejection.INVALID_ENUM)
        val payload = encodePayload(message.payload)
        if (payload.size > MAXIMUM_PAYLOAD_SIZE) reject(Rejection.INVALID_PAYLOAD_LENGTH)
        val writer = Writer()
        writer.u16(MAGIC)
        writer.u8(message.header.protocolVersion)
        writer.u8(message.header.messageType.code)
        writer.u16(message.header.flags)
        writer.u16(HEADER_SIZE)
        writer.u16(payload.size)
        writer.u16(0)
        writer.u64(message.header.sessionId)
        writer.u32(message.header.controllerId)
        writer.u32(message.header.sequence)
        writer.bytes(payload)
        return writer.toByteArray().also(::decode)
    }

    private fun decodePayload(type: MessageType, reader: Reader): Payload = when (type) {
        MessageType.HELLO -> {
            val secret = reader.bytes(16)
            val platform = reader.u8()
            val reserved0 = reader.u8()
            val capabilities = reader.u16()
            val maxSampleHz = reader.u16()
            val modelLength = reader.u8()
            val appLength = reader.u8()
            val osLength = reader.u8()
            val reserved1 = reader.bytes(3)
            if (reserved0 != 0 || reserved1.any { it.toInt() != 0 }) reject(Rejection.NONZERO_RESERVED)
            if (modelLength !in 1..63 || appLength !in 1..31 || osLength !in 1..31 ||
                reader.remaining != modelLength + appLength + osLength
            ) reject(Rejection.INVALID_PAYLOAD_LENGTH)
            val model = decodeString(reader.bytes(modelLength))
            val app = decodeString(reader.bytes(appLength))
            val os = decodeString(reader.bytes(osLength))
            if (platform !in 1..2 || (capabilities and 0xFFE0) != 0 ||
                (capabilities and 0x0007) != 0x0007
            ) reject(Rejection.INVALID_ENUM)
            if (secret.all { it.toInt() == 0 } || maxSampleHz !in 1..1000) reject(Rejection.INVALID_VALUE)
            Hello(secret, platform, capabilities, maxSampleHz, model, app, os)
        }
        MessageType.WELCOME -> {
            val player = reader.u8()
            val state = reader.u8()
            val heartbeat = reader.u16()
            val disconnect = reader.u16()
            val reorder = reader.u16()
            val hostTime = reader.u64()
            val expiry = reader.u64()
            if (!((state == 1 && player in 1..2) || (state in 2..5 && player == 0))) {
                reject(Rejection.INVALID_ENUM)
            }
            if (heartbeat !in 100..5000 || disconnect < heartbeat * 2 || disconnect > 30_000 ||
                reorder !in 0..64 || hostTime == 0uL || expiry == 0uL
            ) reject(Rejection.INVALID_VALUE)
            Welcome(player, state, heartbeat, disconnect, reorder, hostTime, expiry)
        }
        MessageType.PING -> {
            val id = reader.u32()
            if (reader.u32() != 0u) reject(Rejection.NONZERO_RESERVED)
            val time = reader.u64()
            if (time == 0uL) reject(Rejection.INVALID_VALUE)
            Ping(id, time)
        }
        MessageType.PONG -> {
            val id = reader.u32()
            if (reader.u32() != 0u) reject(Rejection.NONZERO_RESERVED)
            val echo = reader.u64()
            val receive = reader.u64()
            val send = reader.u64()
            if (echo == 0uL || receive == 0uL || send < receive) reject(Rejection.INVALID_VALUE)
            Pong(id, echo, receive, send)
        }
        MessageType.MOTION -> {
            val time = reader.u64()
            val acceleration = reader.floats(3)
            val angularVelocity = reader.floats(3)
            val orientation = reader.floats(4)
            val accuracy = reader.u8()
            val sensorFlags = reader.u8()
            if (reader.u16() != 0) reject(Rejection.NONZERO_RESERVED)
            if (accuracy !in setOf(0, 1, 2, 3, 255) ||
                (sensorFlags and 0xE0) != 0 || (sensorFlags and 0x07) != 0x07
            ) reject(Rejection.INVALID_ENUM)
            finite(acceleration + angularVelocity + orientation)
            quaternion(orientation)
            if (time == 0uL || acceleration.any { abs(it) > 200 } ||
                angularVelocity.any { abs(it) > 100 }
            ) reject(Rejection.INVALID_VALUE)
            Motion(time, acceleration, angularVelocity, orientation, accuracy, sensorFlags)
        }
        MessageType.CALIBRATION -> {
            val time = reader.u64()
            val orientation = reader.floats(4)
            val accelerationBias = reader.floats(3)
            val gyroscopeBias = reader.floats(3)
            val quality = reader.f32()
            val result = reader.u8()
            val handedness = reader.u8()
            if (reader.bytes(2).any { it.toInt() != 0 }) reject(Rejection.NONZERO_RESERVED)
            if (result !in 1..2 || handedness !in 1..2) reject(Rejection.INVALID_ENUM)
            finite(orientation + accelerationBias + gyroscopeBias + quality)
            quaternion(orientation)
            if (time == 0uL || accelerationBias.any { abs(it) > 50 } ||
                gyroscopeBias.any { abs(it) > 20 } || quality !in 0f..1f
            ) reject(Rejection.INVALID_VALUE)
            Calibration(time, orientation, accelerationBias, gyroscopeBias, quality, result, handedness)
        }
        MessageType.STATUS -> {
            val time = reader.u64()
            val battery = reader.u8()
            val sensorState = reader.u8()
            val appState = reader.u8()
            val pauseReason = reader.u8()
            val sampleHz = reader.u16()
            if (reader.u16() != 0) reject(Rejection.NONZERO_RESERVED)
            val lastMotion = reader.u32()
            if (sensorState !in 0..3 || appState !in 0..2 || pauseReason !in 0..5) {
                reject(Rejection.INVALID_ENUM)
            }
            if ((battery !in 0..100 && battery != 255) || sampleHz !in 0..1000 ||
                time == 0uL || (appState == 0 && pauseReason != 0)
            ) reject(Rejection.INVALID_VALUE)
            Status(time, battery, sensorState, appState, pauseReason, sampleHz, lastMotion)
        }
        MessageType.GOODBYE -> {
            val reason = reader.u8()
            if (reader.bytes(3).any { it.toInt() != 0 }) reject(Rejection.NONZERO_RESERVED)
            val lastSequence = reader.u32()
            val time = reader.u64()
            if (reason !in 1..5) reject(Rejection.INVALID_ENUM)
            if (time == 0uL) reject(Rejection.INVALID_VALUE)
            Goodbye(reason, lastSequence, time)
        }
    }

    private fun encodePayload(payload: Payload): ByteArray = Writer().apply {
        when (payload) {
            is Hello -> {
                bytes(payload.pairingSecret); u8(payload.platform); u8(0)
                u16(payload.capabilities); u16(payload.maxSampleHz)
                val model = payload.deviceModel.toByteArray(Charsets.UTF_8)
                val app = payload.appVersion.toByteArray(Charsets.UTF_8)
                val os = payload.osVersion.toByteArray(Charsets.UTF_8)
                u8(model.size); u8(app.size); u8(os.size); bytes(ByteArray(3))
                bytes(model); bytes(app); bytes(os)
            }
            is Welcome -> {
                u8(payload.player); u8(payload.sessionState)
                u16(payload.heartbeatIntervalMs); u16(payload.disconnectTimeoutMs)
                u16(payload.reorderWindowPackets); u64(payload.hostMonotonicNs)
                u64(payload.sessionExpiresUnixS)
            }
            is Ping -> { u32(payload.pingId); u32(0u); u64(payload.senderMonotonicNs) }
            is Pong -> {
                u32(payload.pingId); u32(0u); u64(payload.echoSenderMonotonicNs)
                u64(payload.receiverReceiveMonotonicNs); u64(payload.receiverSendMonotonicNs)
            }
            is Motion -> {
                u64(payload.sensorMonotonicNs); floats(payload.acceleration)
                floats(payload.angularVelocity); floats(payload.orientation)
                u8(payload.accuracy); u8(payload.sensorFlags); u16(0)
            }
            is Calibration -> {
                u64(payload.sensorMonotonicNs); floats(payload.neutralOrientation)
                floats(payload.accelerationBias); floats(payload.gyroscopeBias)
                f32(payload.quality); u8(payload.result); u8(payload.handedness); bytes(ByteArray(2))
            }
            is Status -> {
                u64(payload.senderMonotonicNs); u8(payload.batteryPercent)
                u8(payload.sensorState); u8(payload.appState); u8(payload.pauseReason)
                u16(payload.actualSampleHz); u16(0); u32(payload.lastMotionSequence)
            }
            is Goodbye -> {
                u8(payload.reason); bytes(ByteArray(3)); u32(payload.lastSequence)
                u64(payload.senderMonotonicNs)
            }
        }
    }.toByteArray()

    private fun decodeString(bytes: ByteArray): String {
        if (bytes.any { it.toInt() == 0 }) reject(Rejection.INVALID_UTF8)
        return try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
                .ifEmpty { reject(Rejection.INVALID_UTF8) }
        } catch (_: java.nio.charset.CharacterCodingException) {
            reject(Rejection.INVALID_UTF8)
        }
    }

    private fun finite(values: List<Float>) {
        if (values.any { !it.isFinite() }) reject(Rejection.NON_FINITE_FLOAT)
    }

    private fun finite(vararg values: Any) {
        val flattened = values.flatMap {
            when (it) {
                is List<*> -> it.filterIsInstance<Float>()
                is Float -> listOf(it)
                else -> emptyList()
            }
        }
        finite(flattened)
    }

    private fun quaternion(values: List<Float>) {
        val magnitude = sqrt(values.sumOf { (it * it).toDouble() })
        if (magnitude !in 0.98..1.02) reject(Rejection.INVALID_QUATERNION)
    }

    private fun reject(reason: Rejection): Nothing = throw CodecException(reason)

    private class Reader(bytes: ByteArray) {
        private val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        val remaining: Int get() = buffer.remaining()
        fun u8(): Int = buffer.get().toInt() and 0xFF
        fun u16(): Int = buffer.short.toInt() and 0xFFFF
        fun u32(): UInt = buffer.int.toUInt()
        fun u64(): ULong = buffer.long.toULong()
        fun f32(): Float = buffer.float
        fun floats(count: Int): List<Float> = List(count) { f32() }
        fun bytes(count: Int): ByteArray = ByteArray(count).also(buffer::get)
    }

    private class Writer {
        private val output = ByteArrayOutputStream()
        private val data = DataOutputStream(output)
        fun u8(value: Int) = data.writeByte(value)
        fun u16(value: Int) = data.writeShort(value)
        fun u32(value: UInt) = data.writeInt(value.toInt())
        fun u64(value: ULong) = data.writeLong(value.toLong())
        fun f32(value: Float) = data.writeFloat(if (value == 0f) 0f else value)
        fun floats(values: List<Float>) = values.forEach(::f32)
        fun bytes(value: ByteArray) = data.write(value)
        fun toByteArray(): ByteArray = output.toByteArray()
    }
}
