import Foundation

struct MotionSample: Equatable, Sendable {
    let monotonicNanoseconds: UInt64
    let acceleration: SIMD3<Float>
    let angularVelocity: SIMD3<Float>
    let orientation: SIMD4<Float>
    let accuracy: UInt8
    let sensorFlags: UInt8
}

struct MotionBufferSnapshot: Equatable, Sendable {
    let queued: Int
    let accepted: UInt64
    let droppedForCapacity: UInt64
    let rejectedNonMonotonic: UInt64
    let lastTimestampNanoseconds: UInt64?
}

/// A small lock-protected handoff between the real-time-ish sensor callback and
/// the networking worker. When full, the oldest sample is dropped so the newest
/// motion is always retained and the Core Motion callback never waits for I/O.
final class MotionSampleBuffer: @unchecked Sendable {
    let capacity: Int

    private let lock = NSLock()
    private var samples: [MotionSample] = []
    private var accepted: UInt64 = 0
    private var droppedForCapacity: UInt64 = 0
    private var rejectedNonMonotonic: UInt64 = 0
    private var lastTimestamp: UInt64?

    init(capacity: Int = 256) {
        precondition(capacity > 0)
        self.capacity = capacity
        samples.reserveCapacity(capacity)
    }

    @discardableResult
    func offer(_ sample: MotionSample) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let lastTimestamp, sample.monotonicNanoseconds <= lastTimestamp {
            rejectedNonMonotonic += 1
            return false
        }
        lastTimestamp = sample.monotonicNanoseconds
        accepted += 1
        if samples.count == capacity {
            samples.removeFirst()
            droppedForCapacity += 1
        }
        samples.append(sample)
        return true
    }

    func takeOne() -> MotionSample? {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return nil }
        return samples.removeFirst()
    }

    func removeAll() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func snapshot() -> MotionBufferSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return MotionBufferSnapshot(
            queued: samples.count,
            accepted: accepted,
            droppedForCapacity: droppedForCapacity,
            rejectedNonMonotonic: rejectedNonMonotonic,
            lastTimestampNanoseconds: lastTimestamp
        )
    }
}

enum CalibrationHand: UInt8, CaseIterable, Identifiable, Sendable {
    case right = 1
    case left = 2

    var id: Self { self }
    var title: String { self == .right ? "Right" : "Left" }
}

struct CalibrationRecord: Equatable, Sendable {
    let sensorMonotonicNanoseconds: UInt64
    let neutralOrientation: SIMD4<Float>
    let accelerationBias: SIMD3<Float>
    let gyroscopeBias: SIMD3<Float>
    let quality: Float
    let hand: CalibrationHand
}

/// What the slow-swing capture measured, shown with swing failures so the
/// player (and physical test notes) can see how far off the attempt was.
struct SwingMetrics: Equatable, Sendable {
    let excursionDegrees: Float
    let peakRadiansPerSecond: Float

    var summary: String {
        String(
            format: "Measured arc %.0f° (need 20–140°), peak %.2f rad/s (need 0.6–5.0).",
            excursionDegrees, peakRadiansPerSecond
        )
    }
}

enum CalibrationFailure: String, Error, Equatable, Sendable {
    case confirmScreen = "Confirm that the screen faces you before capturing."
    case sensorsUnavailable = "Motion sensors are not ready. Keep the app open and try again."
    case tooShort = "Keep the phone still until neutral capture finishes."
    case sampleRate = "Sensor samples were interrupted. Keep the app in front and retry."
    case quaternion = "Orientation tracking is invalid. Hold the phone steady and retry."
    case unstable = "The phone moved during neutral capture. Hold it completely still."
    case invalidOrientation = "Hold the phone upright in portrait with its top edge pointing up."
    case excessiveBias = "Gyroscope drift is too high. Rest the phone briefly, then retry."
    case swingTooSmall = "Swing through a wider controlled arc, then retry."
    case swingTooFast = "That swing was too fast. Use a slow, controlled practice swing only."
    case swingTooLong = "Complete one controlled swing within three seconds."
}

enum CalibrationPhase: Equatable, Sendable {
    case idle
    case capturingNeutral
    case readyForSlowSwing
    case capturingSlowSwing
    case complete
    case failed(CalibrationFailure)

    /// What a (re)join does: a completed calibration is resent so reconnects
    /// resume streaming; anything else returns the player to calibration.
    var joinAction: JoinCalibrationAction {
        self == .complete ? .resendStoredCalibration : .calibrate
    }
}

enum JoinCalibrationAction: Equatable, Sendable {
    case calibrate
    case resendStoredCalibration
}

/// Deterministic TMB-027 calibration validator. UI code owns timing and feeds
/// the exact sensor samples used for both the decision and transmitted record.
final class SlowSwingCalibration {
    private(set) var phase: CalibrationPhase = .idle
    private(set) var record: CalibrationRecord?

    private(set) var lastSwingMetrics: SwingMetrics?

    /// The accepted record, only once neutral and slow swing both passed.
    var completedRecord: CalibrationRecord? { phase == .complete ? record : nil }
    private var hand: CalibrationHand = .right
    private var neutralSamples: [MotionSample] = []
    private var swingSamples: [MotionSample] = []

    func reset() {
        phase = .idle
        lastSwingMetrics = nil
        record = nil
        neutralSamples.removeAll(keepingCapacity: true)
        swingSamples.removeAll(keepingCapacity: true)
    }

    func beginNeutral(hand: CalibrationHand, screenFacingPlayerConfirmed: Bool) throws {
        reset()
        guard screenFacingPlayerConfirmed else { throw fail(.confirmScreen) }
        self.hand = hand
        phase = .capturingNeutral
    }

    func beginSlowSwing() {
        guard phase == .readyForSlowSwing else { return }
        swingSamples.removeAll(keepingCapacity: true)
        lastSwingMetrics = nil
        phase = .capturingSlowSwing
    }

    func append(_ sample: MotionSample) {
        switch phase {
        case .capturingNeutral: neutralSamples.append(sample)
        case .capturingSlowSwing: swingSamples.append(sample)
        default: break
        }
    }

    @discardableResult
    func finishNeutral() throws -> CalibrationRecord {
        try validateWindow(neutralSamples, minimumDuration: 0.5, maximumDuration: nil)
        guard neutralSamples.allSatisfy({ ($0.sensorFlags & 0x07) == 0x07 && $0.accuracy != 0 }) else {
            throw fail(.sensorsUnavailable)
        }
        guard neutralSamples.allSatisfy({ Self.quaternionNorm($0.orientation) >= 0.98 && Self.quaternionNorm($0.orientation) <= 1.02 }) else {
            throw fail(.quaternion)
        }
        let meanOrientation = Self.meanQuaternion(neutralSamples.map(\.orientation))
        let spread = neutralSamples.map { Self.angularDistance($0.orientation, meanOrientation) }.max() ?? .infinity
        guard spread <= Self.degrees(3) else { throw fail(.unstable) }

        let shaft = Self.rotate(meanOrientation, SIMD3<Float>(0, 1, 0))
        let screen = Self.rotate(meanOrientation, SIMD3<Float>(0, 0, 1))
        guard shaft.z >= cos(Self.degrees(35)), abs(screen.z) <= sin(Self.degrees(25)) else {
            throw fail(.invalidOrientation)
        }

        let accel = neutralSamples.map(\.acceleration)
        let gyro = neutralSamples.map(\.angularVelocity)
        let accelMean = Self.mean(accel)
        let gyroMean = Self.mean(gyro)
        let accelStd = Self.standardDeviation(accel, mean: accelMean)
        let gyroRms = Self.rms(gyro)
        let gyroPeak = gyro.map(Self.length).max() ?? .infinity
        guard Self.components(accelStd).allSatisfy({ $0 <= 0.35 }),
              Self.components(gyroRms).allSatisfy({ $0 <= 0.15 }),
              gyroPeak <= 0.35 else { throw fail(.unstable) }
        guard Self.components(gyroMean).allSatisfy({ abs($0) <= 0.20 }) else {
            throw fail(.excessiveBias)
        }

        let stability = max(0, 1 - spread / Self.degrees(3))
        let quality = min(1, max(0, 0.6 + 0.4 * stability))
        let result = CalibrationRecord(
            sensorMonotonicNanoseconds: neutralSamples.last!.monotonicNanoseconds,
            neutralOrientation: meanOrientation,
            accelerationBias: accelMean,
            gyroscopeBias: gyroMean,
            quality: quality,
            hand: hand
        )
        record = result
        phase = .readyForSlowSwing
        return result
    }

    @discardableResult
    func finishSlowSwing() throws -> CalibrationRecord {
        try validateWindow(swingSamples, minimumDuration: 0.6, maximumDuration: 3.0)
        guard swingSamples.allSatisfy({ ($0.sensorFlags & 0x07) == 0x07 && $0.accuracy != 0 }) else {
            throw fail(.sensorsUnavailable)
        }
        let first = swingSamples.first!.orientation
        let excursion = swingSamples.map { Self.angularDistance(first, $0.orientation) }.max() ?? 0
        let peak = swingSamples.map { Self.length($0.angularVelocity) }.max() ?? 0
        lastSwingMetrics = SwingMetrics(excursionDegrees: excursion * 180 / .pi, peakRadiansPerSecond: peak)
        guard excursion >= Self.degrees(20), peak >= 0.6 else { throw fail(.swingTooSmall) }
        guard excursion <= Self.degrees(140), peak <= 5.0 else { throw fail(.swingTooFast) }
        guard let record else { throw fail(.sensorsUnavailable) }
        phase = .complete
        return record
    }

    private func validateWindow(
        _ samples: [MotionSample], minimumDuration: Double, maximumDuration: Double?
    ) throws {
        guard samples.count >= 2 else { throw fail(.tooShort) }
        let duration = Double(samples.last!.monotonicNanoseconds - samples.first!.monotonicNanoseconds) / 1e9
        if let maximumDuration, duration > maximumDuration { throw fail(.swingTooLong) }
        guard duration >= minimumDuration else { throw fail(.tooShort) }
        guard samples.count >= 50, Double(samples.count - 1) / duration >= 100 else {
            throw fail(.sampleRate)
        }
    }

    private func fail(_ reason: CalibrationFailure) -> CalibrationFailure {
        phase = .failed(reason)
        record = nil
        return reason
    }

    private static func components(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }
    private static func length(_ value: SIMD3<Float>) -> Float { sqrt(value.x * value.x + value.y * value.y + value.z * value.z) }
    private static func quaternionNorm(_ q: SIMD4<Float>) -> Float { sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w) }
    private static func degrees(_ value: Float) -> Float { value * .pi / 180 }

    private static func mean(_ values: [SIMD3<Float>]) -> SIMD3<Float> {
        values.reduce(SIMD3<Float>(repeating: 0), +) / Float(values.count)
    }

    private static func standardDeviation(_ values: [SIMD3<Float>], mean: SIMD3<Float>) -> SIMD3<Float> {
        let variance = values.reduce(SIMD3<Float>(repeating: 0)) { partial, value in
            let d = value - mean
            return partial + d * d
        } / Float(values.count)
        return SIMD3<Float>(sqrt(variance.x), sqrt(variance.y), sqrt(variance.z))
    }

    private static func rms(_ values: [SIMD3<Float>]) -> SIMD3<Float> {
        let squares = values.reduce(SIMD3<Float>(repeating: 0)) { $0 + $1 * $1 } / Float(values.count)
        return SIMD3<Float>(sqrt(squares.x), sqrt(squares.y), sqrt(squares.z))
    }

    private static func meanQuaternion(_ values: [SIMD4<Float>]) -> SIMD4<Float> {
        let anchor = values[0]
        var sum = SIMD4<Float>(repeating: 0)
        for value in values {
            sum += dot(value, anchor) < 0 ? -value : value
        }
        let norm = quaternionNorm(sum)
        return sum / norm
    }

    private static func angularDistance(_ lhs: SIMD4<Float>, _ rhs: SIMD4<Float>) -> Float {
        let normalizedDot = abs(dot(lhs, rhs) / (quaternionNorm(lhs) * quaternionNorm(rhs)))
        return 2 * acos(min(1, max(-1, normalizedDot)))
    }

    private static func dot(_ lhs: SIMD4<Float>, _ rhs: SIMD4<Float>) -> Float {
        lhs.x*rhs.x + lhs.y*rhs.y + lhs.z*rhs.z + lhs.w*rhs.w
    }

    private static func rotate(_ qValue: SIMD4<Float>, _ v: SIMD3<Float>) -> SIMD3<Float> {
        let q = qValue / quaternionNorm(qValue)
        let u = SIMD3<Float>(q.x, q.y, q.z)
        let uv = cross(u, v)
        let uuv = cross(u, uv)
        return v + 2 * (q.w * uv + uuv)
    }

    private static func cross(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(lhs.y*rhs.z - lhs.z*rhs.y, lhs.z*rhs.x - lhs.x*rhs.z, lhs.x*rhs.y - lhs.y*rhs.x)
    }
}
