import simd
import XCTest
@testable import MotionControllerIOS

final class MotionCoordinateAdapterTests: XCTestCase {
    /// Physical ground truth: an upright portrait phone reports Core Motion
    /// pitch +90°, i.e. attitude (sin 45°, 0, 0, cos 45°). In the protocol's
    /// device-to-reference convention its top edge (+Y_D) must point up (+Z).
    func testUprightPortraitAttitudePointsShaftUp() {
        let halfSqrt = Float(0.5).squareRoot()
        let protocolQuaternion = MotionCoordinateAdapter.deviceToReferenceQuaternion(
            SIMD4<Float>(halfSqrt, 0, 0, halfSqrt)
        )
        let shaft = rotate(protocolQuaternion, SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(shaft.x, 0, accuracy: 1e-5)
        XCTAssertEqual(shaft.y, 0, accuracy: 1e-5)
        XCTAssertEqual(shaft.z, 1, accuracy: 1e-5)
    }

    func testIdentityIsUnchanged() {
        XCTAssertEqual(
            MotionCoordinateAdapter.deviceToReferenceQuaternion(SIMD4<Float>(0, 0, 0, 1)),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    private func rotate(_ q: SIMD4<Float>, _ v: SIMD3<Float>) -> SIMD3<Float> {
        simd_quatf(ix: q.x, iy: q.y, iz: q.z, r: q.w).act(v)
    }
}
