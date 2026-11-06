import Combine
import CoreMotion
import Foundation

struct MotionSamplerSnapshot: Equatable, Sendable {
    let requestedHz: Int
    let actualHz: Int
    let status: String
    let buffer: MotionBufferSnapshot
}

final class MotionSampler: ObservableObject, @unchecked Sendable {
    static let requestedHz = 200
    static let gravityMetersPerSecondSquared = 9.80665

    @Published private(set) var snapshot = MotionSamplerSnapshot(
        requestedHz: requestedHz,
        actualHz: 0,
        status: "Stopped",
        buffer: MotionBufferSnapshot(
            queued: 0,
            accepted: 0,
            droppedForCapacity: 0,
            rejectedNonMonotonic: 0,
            lastTimestampNanoseconds: nil
        )
    )

    let buffer: MotionSampleBuffer

    private let manager: CMMotionManager
    private let callbackQueue: OperationQueue
    private let rateLock = NSLock()
    private var recentTimestamps: [UInt64] = []
    private var refreshTimer: Timer?

    init(
        manager: CMMotionManager = CMMotionManager(),
        buffer: MotionSampleBuffer = MotionSampleBuffer()
    ) {
        self.manager = manager
        self.buffer = buffer
        callbackQueue = OperationQueue()
        callbackQueue.name = "MotionBadminton.CoreMotion"
        callbackQueue.maxConcurrentOperationCount = 1
        callbackQueue.qualityOfService = .userInteractive
    }

    deinit {
        manager.stopDeviceMotionUpdates()
        refreshTimer?.invalidate()
    }

    @MainActor
    func start() {
        guard !manager.isDeviceMotionActive else { return }
        guard manager.isDeviceMotionAvailable else {
            publish(status: "Unavailable")
            return
        }
        manager.deviceMotionUpdateInterval = 1.0 / Double(Self.requestedHz)
        startUpdates()
        publish(status: "Sampling")
        refreshTimer?.invalidate()
        refreshTimer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish(status: "Sampling") }
        }
    }

    // Core Motion invokes this closure on callbackQueue. Constructing it in a
    // nonisolated method prevents Swift 6 from inheriting the main-actor
    // executor from start(), which otherwise traps on physical devices.
    private nonisolated func startUpdates() {
        manager.startDeviceMotionUpdates(
            using: Self.referenceFrame,
            to: callbackQueue
        ) { [weak self] motion, error in
            guard let self else { return }
            if error != nil { return }
            guard let motion else { return }
            self.consume(motion)
        }
    }

    @MainActor
    func stop(reason: String = "Stopped") {
        manager.stopDeviceMotionUpdates()
        refreshTimer?.invalidate()
        refreshTimer = nil
        buffer.removeAll()
        publish(status: reason)
    }

    private func consume(_ motion: CMDeviceMotion) {
        let timestamp = UInt64((motion.timestamp * 1_000_000_000.0).rounded())
        let acceleration = SIMD3<Float>(
            Float(motion.userAcceleration.x * Self.gravityMetersPerSecondSquared),
            Float(motion.userAcceleration.y * Self.gravityMetersPerSecondSquared),
            Float(motion.userAcceleration.z * Self.gravityMetersPerSecondSquared)
        )
        let sample = MotionSample(
            monotonicNanoseconds: timestamp,
            acceleration: acceleration,
            angularVelocity: SIMD3<Float>(
                Float(motion.rotationRate.x),
                Float(motion.rotationRate.y),
                Float(motion.rotationRate.z)
            ),
            orientation: MotionCoordinateAdapter.deviceToReferenceQuaternion(SIMD4<Float>(
                Float(motion.attitude.quaternion.x),
                Float(motion.attitude.quaternion.y),
                Float(motion.attitude.quaternion.z),
                Float(motion.attitude.quaternion.w)
            )),
            accuracy: Self.protocolAccuracy(motion.magneticField.accuracy, referenceFrame: Self.referenceFrame),
            sensorFlags: 0x07
        )
        guard buffer.offer(sample) else { return }
        rateLock.lock()
        recentTimestamps.append(timestamp)
        let cutoff = timestamp > 1_000_000_000 ? timestamp - 1_000_000_000 : 0
        while recentTimestamps.first.map({ $0 < cutoff }) == true {
            recentTimestamps.removeFirst()
        }
        rateLock.unlock()
    }

    @MainActor
    private func publish(status: String) {
        rateLock.lock()
        let actualHz = recentTimestamps.count
        rateLock.unlock()
        snapshot = MotionSamplerSnapshot(
            requestedHz: Self.requestedHz,
            actualHz: actualHz,
            status: status,
            buffer: buffer.snapshot()
        )
    }

    /// Attitude without the magnetometer (gyro + accelerometer fusion only).
    nonisolated static let referenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical

    /// Maps Core Motion accuracy to protocol `accuracy`. Magnetic calibration
    /// accuracy only describes magnetometer-based frames; in other frames it
    /// stays `.uncalibrated`, so report `255` (unknown), not `0` (unreliable).
    nonisolated static func protocolAccuracy(
        _ accuracy: CMMagneticFieldCalibrationAccuracy,
        referenceFrame: CMAttitudeReferenceFrame
    ) -> UInt8 {
        guard referenceFrame == .xMagneticNorthZVertical || referenceFrame == .xTrueNorthZVertical else {
            return 255
        }
        return switch accuracy {
        case .uncalibrated: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        @unknown default: 255
        }
    }
}
