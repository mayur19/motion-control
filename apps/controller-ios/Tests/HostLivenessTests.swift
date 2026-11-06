import XCTest
@testable import MotionControllerIOS

final class HostLivenessTests: XCTestCase {
    private let assignment = PairingAssignment(sessionID: 0x0102030405060708, controllerID: 0x0A0B0C0D, player: 1)
    private let second: UInt64 = 1_000_000_000

    func testHostIsLostOnlyAfterTheWelcomeTimeoutWithoutHostPackets() {
        let liveness = HostLiveness(timeoutMilliseconds: 2000, now: 10 * second)
        XCTAssertFalse(liveness.isExpired(at: 12 * second))
        XCTAssertTrue(liveness.isExpired(at: 12 * second + 1))

        let heard = liveness.recording(11 * second)
        XCTAssertFalse(heard.isExpired(at: 13 * second))
        XCTAssertTrue(heard.isExpired(at: 13 * second + 1))
        XCTAssertFalse(liveness.isExpired(at: 12 * second), "recording must not mutate the original")
    }

    func testZeroTimeoutFallsBackToProtocolDefault() {
        let liveness = HostLiveness(timeoutMilliseconds: 0, now: 0)
        XCTAssertEqual(liveness.timeoutNanoseconds, HostLiveness.defaultTimeoutNanoseconds)
    }

    func testClockGoingBackwardsIsNotTreatedAsExpiry() {
        let liveness = HostLiveness(timeoutMilliseconds: 2000, now: 10 * second)
        XCTAssertFalse(liveness.isExpired(at: 5 * second))
    }

    func testClassifiesHostControlPacketsForThisController() {
        let ping = ProtocolV1.Ping(pingID: 7, senderMonotonicNs: 99)
        XCTAssertEqual(HostControlEvent.classify(message(.ping, .ping(ping)), for: assignment), .ping(ping))
        XCTAssertEqual(HostControlEvent.classify(message(.status, .status(hostStatus)), for: assignment), .alive)
        XCTAssertEqual(
            HostControlEvent.classify(message(.goodbye, .goodbye(.init(reason: 3, lastSequence: 4, senderMonotonicNs: 5))), for: assignment),
            .goodbye(reason: 3)
        )
    }

    func testIgnoresPacketsForAnotherSessionOrController() {
        let otherSession = message(.status, .status(hostStatus), sessionID: 1)
        let otherController = message(.status, .status(hostStatus), controllerID: 1)
        XCTAssertEqual(HostControlEvent.classify(otherSession, for: assignment), .unrelated)
        XCTAssertEqual(HostControlEvent.classify(otherController, for: assignment), .unrelated)
    }

    private var hostStatus: ProtocolV1.Status {
        .init(senderMonotonicNs: 1, batteryPercent: 255, sensorState: 0, appState: 0,
              pauseReason: 0, actualSampleHz: 0, lastMotionSequence: 0)
    }

    private func message(
        _ type: ProtocolV1.MessageType,
        _ payload: ProtocolV1.Payload,
        sessionID: UInt64? = nil,
        controllerID: UInt32? = nil
    ) -> ProtocolV1.Message {
        ProtocolV1.Message(
            header: ProtocolV1.Header(
                protocolVersion: ProtocolV1.version,
                messageType: type,
                flags: 0,
                sessionID: sessionID ?? assignment.sessionID,
                controllerID: controllerID ?? assignment.controllerID,
                sequence: 1
            ),
            payload: payload
        )
    }
}
