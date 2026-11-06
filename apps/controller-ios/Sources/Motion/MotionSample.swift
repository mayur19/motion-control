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
