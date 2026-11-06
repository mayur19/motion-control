import XCTest
@testable import MotionControllerIOS

final class MotionPipelineTests: XCTestCase {
    private func sample(_ timestamp: UInt64) -> MotionSample {
        MotionSample(
            monotonicNanoseconds: timestamp,
            acceleration: SIMD3<Float>(1, 2, 3),
            angularVelocity: SIMD3<Float>(0.1, 0.2, 0.3),
            orientation: SIMD4<Float>(0, 0, 0, 1),
            accuracy: 3,
            sensorFlags: 0x07
        )
    }

    func testBoundedBufferDropsOldestAndRetainsNewest() {
        let buffer = MotionSampleBuffer(capacity: 3)
        for timestamp in 1...5 {
            XCTAssertTrue(buffer.offer(sample(UInt64(timestamp))))
        }

        XCTAssertEqual(buffer.snapshot().queued, 3)
        XCTAssertEqual(buffer.snapshot().accepted, 5)
        XCTAssertEqual(buffer.snapshot().droppedForCapacity, 2)
        XCTAssertEqual(
            [buffer.takeOne(), buffer.takeOne(), buffer.takeOne()].compactMap(\.self)
                .map(\.monotonicNanoseconds),
            [3, 4, 5]
        )
    }

    func testBufferRejectsDuplicateAndBackwardTimestamps() {
        let buffer = MotionSampleBuffer(capacity: 4)
        XCTAssertTrue(buffer.offer(sample(100)))
        XCTAssertFalse(buffer.offer(sample(100)))
        XCTAssertFalse(buffer.offer(sample(99)))
        XCTAssertTrue(buffer.offer(sample(101)))
        XCTAssertEqual(buffer.snapshot().accepted, 2)
        XCTAssertEqual(buffer.snapshot().rejectedNonMonotonic, 2)
    }

    func testEverySampleEncodesAsOneMotionDatagram() throws {
        for sequence: UInt32 in 0..<20 {
            let source = sample(1_000_000 + UInt64(sequence))
            let packet = try MotionPacketFactory.encode(
                sample: source,
                sessionID: 0x0102030405060708,
                controllerID: 0x0A0B0C0D,
                sequence: sequence
            )
            let decoded = try ProtocolV1.decode(packet)
            XCTAssertEqual(decoded.header.sequence, sequence)
            guard case let .motion(motion) = decoded.payload else {
                return XCTFail("Expected a MOTION payload")
            }
            XCTAssertEqual(motion.sensorMonotonicNs, source.monotonicNanoseconds)
            XCTAssertEqual(motion.acceleration, source.acceleration)
            XCTAssertEqual(motion.angularVelocity, source.angularVelocity)
            XCTAssertEqual(motion.orientation, source.orientation)
            XCTAssertEqual(packet.count, ProtocolV1.headerSize + 52)
        }
    }
}
