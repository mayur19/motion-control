import XCTest
@testable import MotionControllerIOS

final class MotionCoordinateAdapterTests: XCTestCase {
    func testCoreMotionQuaternionIsInvertedForProtocol() {
        let halfSqrt = Float(0.5).squareRoot()
        XCTAssertEqual(
            MotionCoordinateAdapter.deviceToReferenceQuaternion(
                SIMD4<Float>(halfSqrt, 0, 0, halfSqrt)
            ),
            SIMD4<Float>(-halfSqrt, 0, 0, halfSqrt)
        )
    }

    func testIdentityIsUnchanged() {
        XCTAssertEqual(
            MotionCoordinateAdapter.deviceToReferenceQuaternion(SIMD4<Float>(0, 0, 0, 1)),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}

