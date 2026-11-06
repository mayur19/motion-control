import Foundation

enum ProtocolV1 {
    static let magic: UInt16 = 0x4D42
    static let version: UInt8 = 1
    static let headerSize = 28
    static let maximumPayloadSize = 228

    enum CodecError: String, Error {
        case tooShort = "TOO_SHORT"
        case badMagic = "BAD_MAGIC"
        case unsupportedVersion = "UNSUPPORTED_VERSION"
        case unknownMessageType = "UNKNOWN_MESSAGE_TYPE"
        case invalidFlags = "INVALID_FLAGS"
        case invalidHeaderLength = "INVALID_HEADER_LENGTH"
        case invalidPayloadLength = "INVALID_PAYLOAD_LENGTH"
        case nonzeroReserved = "NONZERO_RESERVED"
        case invalidSessionID = "INVALID_SESSION_ID"
        case invalidControllerID = "INVALID_CONTROLLER_ID"
        case invalidUTF8 = "INVALID_UTF8"
        case invalidEnum = "INVALID_ENUM"
        case nonFiniteFloat = "NON_FINITE_FLOAT"
        case invalidQuaternion = "INVALID_QUATERNION"
        case invalidValue = "INVALID_VALUE"
    }

    enum MessageType: UInt8, CaseIterable {
        case hello = 1
        case welcome = 2
        case ping = 3
        case pong = 4
        case motion = 5
        case calibration = 6
        case status = 7
        case goodbye = 8
    }

    struct Header: Equatable {
        let protocolVersion: UInt8
        let messageType: MessageType
        let flags: UInt16
        let sessionID: UInt64
        let controllerID: UInt32
        let sequence: UInt32
    }

    struct Hello: Equatable {
        let pairingSecret: Data
        let platform: UInt8
        let capabilities: UInt16
        let maxSampleHz: UInt16
        let deviceModel: String
        let appVersion: String
        let osVersion: String
    }

    struct Welcome: Equatable {
        let player: UInt8
        let sessionState: UInt8
        let heartbeatIntervalMs: UInt16
        let disconnectTimeoutMs: UInt16
        let reorderWindowPackets: UInt16
        let hostMonotonicNs: UInt64
        let sessionExpiresUnixS: UInt64
    }

    struct Ping: Equatable {
        let pingID: UInt32
        let senderMonotonicNs: UInt64
    }

    struct Pong: Equatable {
        let pingID: UInt32
        let echoSenderMonotonicNs: UInt64
        let receiverReceiveMonotonicNs: UInt64
        let receiverSendMonotonicNs: UInt64
    }

    struct Motion: Equatable {
        let sensorMonotonicNs: UInt64
        let acceleration: SIMD3<Float>
        let angularVelocity: SIMD3<Float>
        let orientation: SIMD4<Float>
        let accuracy: UInt8
        let sensorFlags: UInt8
    }

    struct Calibration: Equatable {
        let sensorMonotonicNs: UInt64
        let neutralOrientation: SIMD4<Float>
        let accelerationBias: SIMD3<Float>
        let gyroscopeBias: SIMD3<Float>
        let quality: Float
        let result: UInt8
        let handedness: UInt8
    }

    struct Status: Equatable {
        let senderMonotonicNs: UInt64
        let batteryPercent: UInt8
        let sensorState: UInt8
        let appState: UInt8
        let pauseReason: UInt8
        let actualSampleHz: UInt16
        let lastMotionSequence: UInt32
    }

    struct Goodbye: Equatable {
        let reason: UInt8
        let lastSequence: UInt32
        let senderMonotonicNs: UInt64
    }

    enum Payload: Equatable {
        case hello(Hello)
        case welcome(Welcome)
        case ping(Ping)
        case pong(Pong)
        case motion(Motion)
        case calibration(Calibration)
        case status(Status)
        case goodbye(Goodbye)

        var messageType: MessageType {
            switch self {
            case .hello: .hello
            case .welcome: .welcome
            case .ping: .ping
            case .pong: .pong
            case .motion: .motion
            case .calibration: .calibration
            case .status: .status
            case .goodbye: .goodbye
            }
        }
    }

    struct Message: Equatable {
        let header: Header
        let payload: Payload
    }

    static func decode(_ data: Data) throws -> Message {
        guard data.count >= headerSize else { throw CodecError.tooShort }
        var reader = Reader(data: data)

        guard try reader.readUInt16() == magic else { throw CodecError.badMagic }
        let protocolVersion = try reader.readUInt8()
        guard protocolVersion == version else { throw CodecError.unsupportedVersion }
        let rawType = try reader.readUInt8()
        guard let messageType = MessageType(rawValue: rawType) else {
            throw CodecError.unknownMessageType
        }
        let flags = try reader.readUInt16()
        guard flags & ~UInt16(0x0003) == 0,
              !([MessageType.motion, .calibration].contains(messageType) && flags != 0)
        else { throw CodecError.invalidFlags }

        guard try reader.readUInt16() == UInt16(headerSize) else {
            throw CodecError.invalidHeaderLength
        }
        let payloadLength = Int(try reader.readUInt16())
        let expectedSize = expectedPayloadSize(for: messageType)
        guard payloadLength <= maximumPayloadSize,
              data.count == headerSize + payloadLength,
              expectedSize.contains(payloadLength)
        else { throw CodecError.invalidPayloadLength }

        guard try reader.readUInt16() == 0 else { throw CodecError.nonzeroReserved }
        let sessionID = try reader.readUInt64()
        let controllerID = try reader.readUInt32()
        let sequence = try reader.readUInt32()
        guard sessionID != 0 else { throw CodecError.invalidSessionID }
        guard (messageType == .hello && controllerID == 0) ||
                (messageType != .hello && controllerID != 0)
        else { throw CodecError.invalidControllerID }

        let payloadData = try reader.readData(count: payloadLength)
        let payload = try decodePayload(type: messageType, data: payloadData)
        return Message(
            header: Header(
                protocolVersion: protocolVersion,
                messageType: messageType,
                flags: flags,
                sessionID: sessionID,
                controllerID: controllerID,
                sequence: sequence
            ),
            payload: payload
        )
    }

    static func encode(_ message: Message) throws -> Data {
        guard message.header.messageType == message.payload.messageType else {
            throw CodecError.invalidEnum
        }
        let payloadData = encodePayload(message.payload)
        guard payloadData.count <= maximumPayloadSize else {
            throw CodecError.invalidPayloadLength
        }

        var writer = Writer()
        writer.writeUInt16(magic)
        writer.writeUInt8(message.header.protocolVersion)
        writer.writeUInt8(message.header.messageType.rawValue)
        writer.writeUInt16(message.header.flags)
        writer.writeUInt16(UInt16(headerSize))
        writer.writeUInt16(UInt16(payloadData.count))
        writer.writeUInt16(0)
        writer.writeUInt64(message.header.sessionID)
        writer.writeUInt32(message.header.controllerID)
        writer.writeUInt32(message.header.sequence)
        writer.writeData(payloadData)

        let result = writer.data
        _ = try decode(result)
        return result
    }

    private static func expectedPayloadSize(for type: MessageType) -> ClosedRange<Int> {
        switch type {
        case .hello: 28...153
        case .welcome: 24...24
        case .ping: 16...16
        case .pong: 32...32
        case .motion: 52...52
        case .calibration: 56...56
        case .status: 20...20
        case .goodbye: 16...16
        }
    }

    private static func decodePayload(type: MessageType, data: Data) throws -> Payload {
        var reader = Reader(data: data)
        switch type {
        case .hello:
            let secret = try reader.readData(count: 16)
            let platform = try reader.readUInt8()
            let reserved0 = try reader.readUInt8()
            let capabilities = try reader.readUInt16()
            let maxSampleHz = try reader.readUInt16()
            let modelLength = Int(try reader.readUInt8())
            let appLength = Int(try reader.readUInt8())
            let osLength = Int(try reader.readUInt8())
            let reserved1 = try reader.readData(count: 3)
            guard reserved0 == 0, reserved1.allSatisfy({ $0 == 0 }) else {
                throw CodecError.nonzeroReserved
            }
            guard modelLength >= 1, modelLength <= 63,
                  appLength >= 1, appLength <= 31,
                  osLength >= 1, osLength <= 31,
                  reader.remaining == modelLength + appLength + osLength
            else { throw CodecError.invalidPayloadLength }
            let model = try decodeString(try reader.readData(count: modelLength))
            let app = try decodeString(try reader.readData(count: appLength))
            let os = try decodeString(try reader.readData(count: osLength))
            guard [UInt8(1), 2].contains(platform),
                  capabilities & ~UInt16(0x001F) == 0,
                  capabilities & 0x0007 == 0x0007
            else { throw CodecError.invalidEnum }
            guard !secret.allSatisfy({ $0 == 0 }), (1...1000).contains(maxSampleHz) else {
                throw CodecError.invalidValue
            }
            return .hello(Hello(
                pairingSecret: secret,
                platform: platform,
                capabilities: capabilities,
                maxSampleHz: maxSampleHz,
                deviceModel: model,
                appVersion: app,
                osVersion: os
            ))

        case .welcome:
            let player = try reader.readUInt8()
            let sessionState = try reader.readUInt8()
            let heartbeat = try reader.readUInt16()
            let disconnect = try reader.readUInt16()
            let reorder = try reader.readUInt16()
            let hostTime = try reader.readUInt64()
            let expiry = try reader.readUInt64()
            guard (sessionState == 1 && [UInt8(1), 2].contains(player)) ||
                    ((2...5).contains(sessionState) && player == 0) else {
                throw CodecError.invalidEnum
            }
            guard (100...5000).contains(heartbeat),
                  disconnect >= heartbeat * 2,
                  disconnect <= 30_000,
                  reorder <= 64,
                  hostTime > 0,
                  expiry > 0
            else { throw CodecError.invalidValue }
            return .welcome(Welcome(
                player: player,
                sessionState: sessionState,
                heartbeatIntervalMs: heartbeat,
                disconnectTimeoutMs: disconnect,
                reorderWindowPackets: reorder,
                hostMonotonicNs: hostTime,
                sessionExpiresUnixS: expiry
            ))

        case .ping:
            let pingID = try reader.readUInt32()
            guard try reader.readUInt32() == 0 else { throw CodecError.nonzeroReserved }
            let time = try reader.readUInt64()
            guard time > 0 else { throw CodecError.invalidValue }
            return .ping(Ping(pingID: pingID, senderMonotonicNs: time))

        case .pong:
            let pingID = try reader.readUInt32()
            guard try reader.readUInt32() == 0 else { throw CodecError.nonzeroReserved }
            let echo = try reader.readUInt64()
            let receive = try reader.readUInt64()
            let send = try reader.readUInt64()
            guard echo > 0, receive > 0, send >= receive else { throw CodecError.invalidValue }
            return .pong(Pong(
                pingID: pingID,
                echoSenderMonotonicNs: echo,
                receiverReceiveMonotonicNs: receive,
                receiverSendMonotonicNs: send
            ))

        case .motion:
            let sensorTime = try reader.readUInt64()
            let acceleration = try readVector3(&reader)
            let angularVelocity = try readVector3(&reader)
            let orientation = try readVector4(&reader)
            let accuracy = try reader.readUInt8()
            let sensorFlags = try reader.readUInt8()
            guard try reader.readUInt16() == 0 else { throw CodecError.nonzeroReserved }
            guard [UInt8(0), 1, 2, 3, 255].contains(accuracy),
                  sensorFlags & 0xE0 == 0,
                  sensorFlags & 0x07 == 0x07
            else { throw CodecError.invalidEnum }
            try validateFinite(vector3Values(acceleration) + vector3Values(angularVelocity) + vector4Values(orientation))
            try validateQuaternion(orientation)
            guard sensorTime > 0,
                  vector3Values(acceleration).allSatisfy({ abs($0) <= 200 }),
                  vector3Values(angularVelocity).allSatisfy({ abs($0) <= 100 })
            else { throw CodecError.invalidValue }
            return .motion(Motion(
                sensorMonotonicNs: sensorTime,
                acceleration: acceleration,
                angularVelocity: angularVelocity,
                orientation: orientation,
                accuracy: accuracy,
                sensorFlags: sensorFlags
            ))

        case .calibration:
            let sensorTime = try reader.readUInt64()
            let orientation = try readVector4(&reader)
            let accelerationBias = try readVector3(&reader)
            let gyroscopeBias = try readVector3(&reader)
            let quality = try reader.readFloat()
            let result = try reader.readUInt8()
            let handedness = try reader.readUInt8()
            let reserved = try reader.readData(count: 2)
            guard reserved.allSatisfy({ $0 == 0 }) else { throw CodecError.nonzeroReserved }
            guard [UInt8(1), 2].contains(result), [UInt8(1), 2].contains(handedness) else {
                throw CodecError.invalidEnum
            }
            try validateFinite(
                vector4Values(orientation) + vector3Values(accelerationBias) +
                    vector3Values(gyroscopeBias) + [quality]
            )
            try validateQuaternion(orientation)
            guard sensorTime > 0,
                  vector3Values(accelerationBias).allSatisfy({ abs($0) <= 50 }),
                  vector3Values(gyroscopeBias).allSatisfy({ abs($0) <= 20 }),
                  (0...1).contains(quality)
            else { throw CodecError.invalidValue }
            return .calibration(Calibration(
                sensorMonotonicNs: sensorTime,
                neutralOrientation: orientation,
                accelerationBias: accelerationBias,
                gyroscopeBias: gyroscopeBias,
                quality: quality,
                result: result,
                handedness: handedness
            ))

        case .status:
            let time = try reader.readUInt64()
            let battery = try reader.readUInt8()
            let sensorState = try reader.readUInt8()
            let appState = try reader.readUInt8()
            let pauseReason = try reader.readUInt8()
            let sampleHz = try reader.readUInt16()
            guard try reader.readUInt16() == 0 else { throw CodecError.nonzeroReserved }
            let lastMotion = try reader.readUInt32()
            guard sensorState <= 3, appState <= 2, pauseReason <= 5 else {
                throw CodecError.invalidEnum
            }
            guard (battery <= 100 || battery == 255),
                  sampleHz <= 1000,
                  time > 0,
                  !(appState == 0 && pauseReason != 0)
            else { throw CodecError.invalidValue }
            return .status(Status(
                senderMonotonicNs: time,
                batteryPercent: battery,
                sensorState: sensorState,
                appState: appState,
                pauseReason: pauseReason,
                actualSampleHz: sampleHz,
                lastMotionSequence: lastMotion
            ))

        case .goodbye:
            let reason = try reader.readUInt8()
            let reserved = try reader.readData(count: 3)
            guard reserved.allSatisfy({ $0 == 0 }) else { throw CodecError.nonzeroReserved }
            let lastSequence = try reader.readUInt32()
            let time = try reader.readUInt64()
            guard (1...5).contains(reason) else { throw CodecError.invalidEnum }
            guard time > 0 else { throw CodecError.invalidValue }
            return .goodbye(Goodbye(
                reason: reason,
                lastSequence: lastSequence,
                senderMonotonicNs: time
            ))
        }
    }

    private static func encodePayload(_ payload: Payload) -> Data {
        var writer = Writer()
        switch payload {
        case let .hello(value):
            writer.writeData(value.pairingSecret)
            writer.writeUInt8(value.platform)
            writer.writeUInt8(0)
            writer.writeUInt16(value.capabilities)
            writer.writeUInt16(value.maxSampleHz)
            let model = Data(value.deviceModel.utf8)
            let app = Data(value.appVersion.utf8)
            let os = Data(value.osVersion.utf8)
            writer.writeUInt8(UInt8(model.count))
            writer.writeUInt8(UInt8(app.count))
            writer.writeUInt8(UInt8(os.count))
            writer.writeData(Data(repeating: 0, count: 3))
            writer.writeData(model)
            writer.writeData(app)
            writer.writeData(os)
        case let .welcome(value):
            writer.writeUInt8(value.player)
            writer.writeUInt8(value.sessionState)
            writer.writeUInt16(value.heartbeatIntervalMs)
            writer.writeUInt16(value.disconnectTimeoutMs)
            writer.writeUInt16(value.reorderWindowPackets)
            writer.writeUInt64(value.hostMonotonicNs)
            writer.writeUInt64(value.sessionExpiresUnixS)
        case let .ping(value):
            writer.writeUInt32(value.pingID)
            writer.writeUInt32(0)
            writer.writeUInt64(value.senderMonotonicNs)
        case let .pong(value):
            writer.writeUInt32(value.pingID)
            writer.writeUInt32(0)
            writer.writeUInt64(value.echoSenderMonotonicNs)
            writer.writeUInt64(value.receiverReceiveMonotonicNs)
            writer.writeUInt64(value.receiverSendMonotonicNs)
        case let .motion(value):
            writer.writeUInt64(value.sensorMonotonicNs)
            writer.writeVector3(value.acceleration)
            writer.writeVector3(value.angularVelocity)
            writer.writeVector4(value.orientation)
            writer.writeUInt8(value.accuracy)
            writer.writeUInt8(value.sensorFlags)
            writer.writeUInt16(0)
        case let .calibration(value):
            writer.writeUInt64(value.sensorMonotonicNs)
            writer.writeVector4(value.neutralOrientation)
            writer.writeVector3(value.accelerationBias)
            writer.writeVector3(value.gyroscopeBias)
            writer.writeFloat(value.quality)
            writer.writeUInt8(value.result)
            writer.writeUInt8(value.handedness)
            writer.writeData(Data(repeating: 0, count: 2))
        case let .status(value):
            writer.writeUInt64(value.senderMonotonicNs)
            writer.writeUInt8(value.batteryPercent)
            writer.writeUInt8(value.sensorState)
            writer.writeUInt8(value.appState)
            writer.writeUInt8(value.pauseReason)
            writer.writeUInt16(value.actualSampleHz)
            writer.writeUInt16(0)
            writer.writeUInt32(value.lastMotionSequence)
        case let .goodbye(value):
            writer.writeUInt8(value.reason)
            writer.writeData(Data(repeating: 0, count: 3))
            writer.writeUInt32(value.lastSequence)
            writer.writeUInt64(value.senderMonotonicNs)
        }
        return writer.data
    }

    private static func decodeString(_ data: Data) throws -> String {
        guard !data.contains(0), let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw CodecError.invalidUTF8
        }
        return value
    }

    private static func readVector3(_ reader: inout Reader) throws -> SIMD3<Float> {
        try SIMD3(reader.readFloat(), reader.readFloat(), reader.readFloat())
    }

    private static func readVector4(_ reader: inout Reader) throws -> SIMD4<Float> {
        try SIMD4(reader.readFloat(), reader.readFloat(), reader.readFloat(), reader.readFloat())
    }

    private static func validateFinite(_ values: [Float]) throws {
        guard values.allSatisfy(\.isFinite) else { throw CodecError.nonFiniteFloat }
    }

    private static func vector3Values(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
    }

    private static func vector4Values(_ value: SIMD4<Float>) -> [Float] {
        [value.x, value.y, value.z, value.w]
    }

    private static func validateQuaternion(_ value: SIMD4<Float>) throws {
        let magnitude = sqrt(value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w)
        guard (0.98...1.02).contains(magnitude) else { throw CodecError.invalidQuaternion }
    }

    private struct Reader {
        let data: Data
        var index = 0
        var remaining: Int { data.count - index }

        mutating func readUInt8() throws -> UInt8 {
            guard remaining >= 1 else { throw CodecError.invalidPayloadLength }
            defer { index += 1 }
            return data[index]
        }

        mutating func readUInt16() throws -> UInt16 {
            let bytes = try readData(count: 2)
            return bytes.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        }

        mutating func readUInt32() throws -> UInt32 {
            let bytes = try readData(count: 4)
            return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }

        mutating func readUInt64() throws -> UInt64 {
            let bytes = try readData(count: 8)
            return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }

        mutating func readFloat() throws -> Float {
            Float(bitPattern: try readUInt32())
        }

        mutating func readData(count: Int) throws -> Data {
            guard count >= 0, remaining >= count else { throw CodecError.invalidPayloadLength }
            let result = data[index..<(index + count)]
            index += count
            return Data(result)
        }
    }

    private struct Writer {
        var data = Data()

        mutating func writeUInt8(_ value: UInt8) { data.append(value) }
        mutating func writeUInt16(_ value: UInt16) {
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
        mutating func writeUInt32(_ value: UInt32) {
            for shift in stride(from: 24, through: 0, by: -8) {
                data.append(UInt8((value >> UInt32(shift)) & 0xFF))
            }
        }
        mutating func writeUInt64(_ value: UInt64) {
            for shift in stride(from: 56, through: 0, by: -8) {
                data.append(UInt8((value >> UInt64(shift)) & 0xFF))
            }
        }
        mutating func writeFloat(_ value: Float) {
            writeUInt32((value == 0 ? Float(0) : value).bitPattern)
        }
        mutating func writeData(_ value: Data) { data.append(value) }
        mutating func writeVector3(_ value: SIMD3<Float>) {
            writeFloat(value.x); writeFloat(value.y); writeFloat(value.z)
        }
        mutating func writeVector4(_ value: SIMD4<Float>) {
            writeFloat(value.x); writeFloat(value.y); writeFloat(value.z); writeFloat(value.w)
        }
    }
}
