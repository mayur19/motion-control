import XCTest
@testable import MotionControllerIOS

final class RejoinScheduleTests: XCTestCase {
    func testRejoinCoversTheLargestHostReservation() {
        XCTAssertEqual(PairingClient.rejoinWindowSeconds, 60)
    }

    func testRetryDelaysAreQuickFirstThenSteadyAndEndInsideTheWindow() {
        let delays = PairingClient.rejoinRetryDelays
        XCTAssertEqual(Array(delays.prefix(4)), [0.0, 0.25, 0.75, 1.5])
        XCTAssertEqual(delays, delays.sorted(), "delays must be increasing")
        XCTAssertLessThan(delays.last ?? 0, PairingClient.rejoinWindowSeconds)
        XCTAssertGreaterThanOrEqual(delays.last ?? 0, PairingClient.rejoinWindowSeconds - 3)
        let gaps = zip(delays.dropFirst(), delays).map { $0 - $1 }
        XCTAssertLessThanOrEqual(gaps.max() ?? 0, 2.5, "a returning host must be retried at least every 2.5 s")
    }
}
