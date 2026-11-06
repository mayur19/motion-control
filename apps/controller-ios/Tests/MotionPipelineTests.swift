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

    func testSlowSwingCalibrationAcceptsBothHandsAndIsRepeatable() throws {
        for hand in CalibrationHand.allCases {
            let first = try completedCalibration(hand: hand, accelerationBias: SIMD3<Float>(0.02, -0.01, 0.03))
            let second = try completedCalibration(hand: hand, accelerationBias: SIMD3<Float>(0.03, -0.01, 0.03))
            XCTAssertEqual(first.hand, hand)
            XCTAssertLessThan(abs(first.accelerationBias.x - second.accelerationBias.x), 0.02)
            XCTAssertGreaterThanOrEqual(first.quality, 0.6)
        }
    }

    func testCalibrationRejectsInvalidPhoneOrientation() throws {
        let calibration = SlowSwingCalibration()
        try calibration.beginNeutral(hand: .right, screenFacingPlayerConfirmed: true)
        for index in 0...120 {
            calibration.append(calibrationSample(index: index, orientation: SIMD4<Float>(0, 0, 0, 1)))
        }
        XCTAssertThrowsError(try calibration.finishNeutral()) { error in
            XCTAssertEqual(error as? CalibrationFailure, .invalidOrientation)
        }
    }

    func testCalibrationRecordEncodesHandedness() throws {
        let record = try completedCalibration(hand: .left, accelerationBias: .zero)
        let packet = try CalibrationPacketFactory.encode(
            record: record,
            sessionID: 1,
            controllerID: 2,
            sequence: 0
        )
        guard case let .calibration(payload) = try ProtocolV1.decode(packet).payload else {
            return XCTFail("Expected CALIBRATION")
        }
        XCTAssertEqual(payload.handedness, CalibrationHand.left.rawValue)
    }

    func testSmallSwingReportsMeasuredArcAndSpeed() throws {
        let calibration = SlowSwingCalibration()
        try calibration.beginNeutral(hand: .right, screenFacingPlayerConfirmed: true)
        let upright = SIMD4<Float>(sin(.pi / 4), 0, 0, cos(.pi / 4))
        for index in 0...120 {
            calibration.append(calibrationSample(index: index, orientation: upright, acceleration: .zero))
        }
        _ = try calibration.finishNeutral()
        calibration.beginSlowSwing()
        for index in 0...120 {
            let angle = Float.pi / 2 + (Float(index) / 120) * (Float.pi / 18) // 10° arc
            calibration.append(calibrationSample(
                index: index,
                orientation: SIMD4<Float>(sin(angle / 2), 0, 0, cos(angle / 2)),
                acceleration: .zero,
                angularVelocity: SIMD3<Float>(0.3, 0, 0)
            ))
        }
        XCTAssertThrowsError(try calibration.finishSlowSwing()) { error in
            XCTAssertEqual(error as? CalibrationFailure, .swingTooSmall)
        }
        let metrics = try XCTUnwrap(calibration.lastSwingMetrics)
        XCTAssertEqual(metrics.excursionDegrees, 10, accuracy: 0.5)
        XCTAssertEqual(metrics.peakRadiansPerSecond, 0.3, accuracy: 0.01)
        XCTAssertEqual(
            metrics.summary,
            "Measured arc 10° (need 20–140°), peak 0.30 rad/s (need 0.6–5.0)."
        )
    }

    func testStoredRecordIsAvailableOnlyAfterCompletedCalibration() throws {
        let calibration = SlowSwingCalibration()
        try calibration.beginNeutral(hand: .left, screenFacingPlayerConfirmed: true)
        XCTAssertNil(calibration.completedRecord)
        let upright = SIMD4<Float>(sin(.pi / 4), 0, 0, cos(.pi / 4))
        for index in 0...120 {
            calibration.append(calibrationSample(index: index, orientation: upright, acceleration: .zero))
        }
        _ = try calibration.finishNeutral()
        XCTAssertNil(calibration.completedRecord, "neutral alone must not be resent")

        let completed = try completedCalibrator(hand: .left, accelerationBias: .zero)
        XCTAssertEqual(completed.completedRecord?.hand, .left)
        completed.reset()
        XCTAssertNil(completed.completedRecord)
        XCTAssertEqual(completed.phase, .idle)
    }

    private func completedCalibration(
        hand: CalibrationHand, accelerationBias: SIMD3<Float>
    ) throws -> CalibrationRecord {
        let calibration = try completedCalibrator(hand: hand, accelerationBias: accelerationBias)
        return try XCTUnwrap(calibration.completedRecord)
    }

    private func completedCalibrator(
        hand: CalibrationHand, accelerationBias: SIMD3<Float>
    ) throws -> SlowSwingCalibration {
        let calibration = SlowSwingCalibration()
        try calibration.beginNeutral(hand: hand, screenFacingPlayerConfirmed: true)
        let upright = SIMD4<Float>(sin(.pi / 4), 0, 0, cos(.pi / 4))
        for index in 0...120 {
            calibration.append(calibrationSample(index: index, orientation: upright, acceleration: accelerationBias))
        }
        _ = try calibration.finishNeutral()
        calibration.beginSlowSwing()
        for index in 0...120 {
            let angle = Float.pi / 2 + (Float(index) / 120) * (.pi / 6)
            let orientation = SIMD4<Float>(sin(angle / 2), 0, 0, cos(angle / 2))
            calibration.append(calibrationSample(
                index: index,
                orientation: orientation,
                acceleration: accelerationBias,
                angularVelocity: SIMD3<Float>(1, 0, 0)
            ))
        }
        try calibration.finishSlowSwing()
        return calibration
    }

    private func calibrationSample(
        index: Int,
        orientation: SIMD4<Float>,
        acceleration: SIMD3<Float> = .zero,
        angularVelocity: SIMD3<Float> = .zero
    ) -> MotionSample {
        MotionSample(
            monotonicNanoseconds: 1_000_000_000 + UInt64(index) * 5_000_000,
            acceleration: acceleration,
            angularVelocity: angularVelocity,
            orientation: orientation,
            accuracy: 3,
            sensorFlags: 0x07
        )
    }
}
