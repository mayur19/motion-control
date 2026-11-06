import Combine
import Foundation
import Network

struct MotionStreamerSnapshot: Equatable, Sendable {
    let sent: UInt64
    let sentHz: Int
    let networkErrors: UInt64
    let lastSuccessfulSendNanoseconds: UInt64?
    let status: String
}

enum MotionPacketFactory {
    static func encode(
        sample: MotionSample,
        sessionID: UInt64,
        controllerID: UInt32,
        sequence: UInt32
    ) throws -> Data {
        try ProtocolV1.encode(ProtocolV1.Message(
            header: ProtocolV1.Header(
                protocolVersion: ProtocolV1.version,
                messageType: .motion,
                flags: 0,
                sessionID: sessionID,
                controllerID: controllerID,
                sequence: sequence
            ),
            payload: .motion(ProtocolV1.Motion(
                sensorMonotonicNs: sample.monotonicNanoseconds,
                acceleration: sample.acceleration,
                angularVelocity: sample.angularVelocity,
                orientation: sample.orientation,
                accuracy: sample.accuracy,
                sensorFlags: sample.sensorFlags
            ))
        ))
    }
}

enum CalibrationPacketFactory {
    static func encode(
        record: CalibrationRecord,
        sessionID: UInt64,
        controllerID: UInt32,
        sequence: UInt32
    ) throws -> Data {
        try ProtocolV1.encode(ProtocolV1.Message(
            header: ProtocolV1.Header(
                protocolVersion: ProtocolV1.version,
                messageType: .calibration,
                flags: 0,
                sessionID: sessionID,
                controllerID: controllerID,
                sequence: sequence
            ),
            payload: .calibration(ProtocolV1.Calibration(
                sensorMonotonicNs: record.sensorMonotonicNanoseconds,
                neutralOrientation: record.neutralOrientation,
                accelerationBias: record.accelerationBias,
                gyroscopeBias: record.gyroscopeBias,
                quality: record.quality,
                result: 1,
                handedness: record.hand.rawValue
            ))
        ))
    }
}

final class MotionStreamer: ObservableObject, @unchecked Sendable {
    @Published private(set) var snapshot = MotionStreamerSnapshot(
        sent: 0,
        sentHz: 0,
        networkErrors: 0,
        lastSuccessfulSendNanoseconds: nil,
        status: "Stopped"
    )

    private(set) var sessionID: UInt64
    private(set) var controllerID: UInt32

    private let buffer: MotionSampleBuffer
    private let worker = DispatchQueue(label: "MotionBadminton.UDP", qos: .userInteractive)
    private let statsLock = NSLock()
    private var connection: NWConnection?
    private var pump: DispatchSourceTimer?
    private var sequence: UInt32 = 0
    private var sent: UInt64 = 0
    private var networkErrors: UInt64 = 0
    private var lastSuccessfulSend: UInt64?
    private var recentSends: [UInt64] = []
    private var refreshTimer: Timer?

    init(
        buffer: MotionSampleBuffer,
        sessionID: UInt64 = UInt64.random(in: 1...UInt64.max),
        controllerID: UInt32 = UInt32.random(in: 1...UInt32.max)
    ) {
        self.buffer = buffer
        self.sessionID = sessionID
        self.controllerID = controllerID
    }

    deinit {
        pump?.cancel()
        connection?.cancel()
        refreshTimer?.invalidate()
    }

    @MainActor
    func configure(sessionID: UInt64, controllerID: UInt32) {
        self.sessionID = sessionID
        self.controllerID = controllerID
        sequence = 0
    }

    @MainActor
    func start(host: String, port: UInt16) {
        stop()
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let endpointPort = NWEndpoint.Port(rawValue: port)
        else {
            publish(status: "Invalid destination")
            return
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .udp
        )
        self.connection = connection
        connection.start(queue: worker)
        let pump = makePump()
        pump.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(250))
        self.pump = pump
        pump.resume()
        publish(status: "Streaming")
        refreshTimer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish(status: "Streaming") }
        }
    }

    // Creating this handler outside the @MainActor start method prevents Swift
    // 6 from inheriting the main-actor executor onto a dispatch source that is
    // intentionally invoked by the dedicated UDP worker queue.
    private nonisolated func makePump() -> DispatchSourceTimer {
        let result = DispatchSource.makeTimerSource(queue: worker)
        result.setEventHandler { [weak self] in
            self?.sendOneIfAvailable()
        }
        return result
    }

    @MainActor
    func stop() {
        pump?.cancel()
        pump = nil
        connection?.cancel()
        connection = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        publish(status: "Stopped")
    }

    @MainActor
    func sendCalibration(
        _ record: CalibrationRecord,
        host: String,
        port: UInt16,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let endpointPort = NWEndpoint.Port(rawValue: port),
              let packet = try? CalibrationPacketFactory.encode(
                record: record,
                sessionID: sessionID,
                controllerID: controllerID,
                sequence: sequence
              ) else {
            completion(false)
            return
        }
        sequence &+= 1
        let calibrationConnection = NWConnection(
            host: NWEndpoint.Host(host), port: endpointPort, using: .udp
        )
        calibrationConnection.start(queue: worker)
        calibrationConnection.send(content: packet, completion: .contentProcessed { error in
            calibrationConnection.cancel()
            Task { @MainActor in completion(error == nil) }
        })
    }

    private func sendOneIfAvailable() {
        guard let connection, let sample = buffer.takeOne() else { return }
        let packet: Data
        do {
            packet = try MotionPacketFactory.encode(
                sample: sample,
                sessionID: sessionID,
                controllerID: controllerID,
                sequence: sequence
            )
            sequence &+= 1
        } catch {
            recordError()
            return
        }
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.recordSuccess()
            } else {
                self?.recordError()
            }
        })
    }

    private func recordSuccess() {
        let now = DispatchTime.now().uptimeNanoseconds
        statsLock.lock()
        sent += 1
        lastSuccessfulSend = now
        recentSends.append(now)
        let cutoff = now > 1_000_000_000 ? now - 1_000_000_000 : 0
        while recentSends.first.map({ $0 < cutoff }) == true {
            recentSends.removeFirst()
        }
        statsLock.unlock()
    }

    private func recordError() {
        statsLock.lock()
        networkErrors += 1
        statsLock.unlock()
    }

    @MainActor
    private func publish(status: String) {
        statsLock.lock()
        let currentSent = sent
        let currentRate = recentSends.count
        let currentErrors = networkErrors
        let currentLastSend = lastSuccessfulSend
        statsLock.unlock()
        snapshot = MotionStreamerSnapshot(
            sent: currentSent,
            sentHz: currentRate,
            networkErrors: currentErrors,
            lastSuccessfulSendNanoseconds: currentLastSend,
            status: status
        )
    }
}
