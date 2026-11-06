import CoreMotion
import XCTest
@testable import MotionControllerIOS

final class MotionSamplerAccuracyTests: XCTestCase {
    func testFrameWithoutMagnetometerReportsUnknownNotUnreliable() {
        // .xArbitraryZVertical never calibrates the magnetometer, so its
        // magnetic accuracy is always .uncalibrated; that must not read as 0.
        XCTAssertEqual(
            MotionSampler.protocolAccuracy(.uncalibrated, referenceFrame: .xArbitraryZVertical),
            255
        )
        XCTAssertEqual(
            MotionSampler.protocolAccuracy(.high, referenceFrame: .xArbitraryZVertical),
            255
        )
    }

    func testMagnetometerFrameMapsCalibrationAccuracy() {
        XCTAssertEqual(MotionSampler.protocolAccuracy(.uncalibrated, referenceFrame: .xMagneticNorthZVertical), 0)
        XCTAssertEqual(MotionSampler.protocolAccuracy(.low, referenceFrame: .xMagneticNorthZVertical), 1)
        XCTAssertEqual(MotionSampler.protocolAccuracy(.medium, referenceFrame: .xMagneticNorthZVertical), 2)
        XCTAssertEqual(MotionSampler.protocolAccuracy(.high, referenceFrame: .xMagneticNorthZVertical), 3)
    }

    func testSamplerUsesNonMagneticReferenceFrame() {
        XCTAssertEqual(MotionSampler.referenceFrame, .xArbitraryZVertical)
    }
}
