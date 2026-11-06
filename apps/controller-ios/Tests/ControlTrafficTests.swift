import Network
import XCTest
@testable import MotionControllerIOS

final class ControlTrafficTests: XCTestCase {
    func testHelloRetriesOnlySendOnAReadyPath() {
        XCTAssertTrue(PairingClient.shouldSendHelloRetry(on: .ready))
        XCTAssertFalse(PairingClient.shouldSendHelloRetry(on: .preparing))
        XCTAssertFalse(PairingClient.shouldSendHelloRetry(on: .setup))
        XCTAssertFalse(PairingClient.shouldSendHelloRetry(on: .cancelled))
        XCTAssertFalse(
            PairingClient.shouldSendHelloRetry(on: .waiting(.posix(.ENETDOWN))),
            "queued sends while waiting are flushed as a burst when the path returns"
        )
    }

    func testStatusIsSentImmediatelyOnlyForMeaningfulChanges() {
        let active = PairingClient.StatusFlags(appActive: true, sensorValid: true)
        XCTAssertFalse(PairingClient.needsImmediateStatus(from: active, to: active),
                       "sample-rate updates ride on the 500 ms heartbeat")
        XCTAssertTrue(PairingClient.needsImmediateStatus(
            from: active, to: .init(appActive: false, sensorValid: true)))
        XCTAssertTrue(PairingClient.needsImmediateStatus(
            from: active, to: .init(appActive: true, sensorValid: false)))
    }
}
