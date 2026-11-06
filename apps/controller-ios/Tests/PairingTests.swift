import XCTest
@testable import MotionControllerIOS

final class PairingTests: XCTestCase {
    private let valid = "motion-badminton://join?v=1&host=192.168.50.12&port=7000&session=0102030405060708&secret=00112233445566778899aabbccddeeff&expires=1800000120"

    func testValidJoinPayloadParsesExactly() throws {
        let result = try JoinPayload.parse(valid, nowUnixSeconds: 1_800_000_000)
        XCTAssertEqual(result.host, "192.168.50.12")
        XCTAssertEqual(result.port, 7000)
        XCTAssertEqual(result.sessionID, 0x0102030405060708)
        XCTAssertEqual(result.pairingSecret.map { String(format: "%02x", $0) }.joined(),
                       "00112233445566778899aabbccddeeff")
        XCTAssertEqual(result.expiresUnixSeconds, 1_800_000_120)
    }

    func testExpiredAlteredAndWrongVersionCodesHaveSpecificErrors() {
        XCTAssertThrowsError(try JoinPayload.parse(valid, nowUnixSeconds: 1_800_000_120)) {
            XCTAssertEqual($0 as? JoinPayload.ValidationError, .expired)
        }
        XCTAssertThrowsError(
            try JoinPayload.parse(valid.replacingOccurrences(of: "secret=00", with: "secret=zz"),
                                  nowUnixSeconds: 1_800_000_000)
        ) { XCTAssertEqual($0 as? JoinPayload.ValidationError, .invalidCredential) }
        XCTAssertThrowsError(
            try JoinPayload.parse(valid.replacingOccurrences(of: "v=1", with: "v=2"),
                                  nowUnixSeconds: 1_800_000_000)
        ) { XCTAssertEqual($0 as? JoinPayload.ValidationError, .unsupportedVersion) }
    }

    func testWelcomeRejectionStatesDecode() throws {
        for state: UInt8 in 2...5 {
            let data = try ProtocolV1.encode(ProtocolV1.Message(
                header: ProtocolV1.Header(
                    protocolVersion: 1, messageType: .welcome, flags: 0,
                    sessionID: 1, controllerID: 2, sequence: UInt32(state)
                ),
                payload: .welcome(ProtocolV1.Welcome(
                    player: 0, sessionState: state, heartbeatIntervalMs: 500,
                    disconnectTimeoutMs: 2000, reorderWindowPackets: 8,
                    hostMonotonicNs: 1, sessionExpiresUnixS: 2
                ))
            ))
            guard case let .welcome(welcome) = try ProtocolV1.decode(data).payload else {
                return XCTFail("Expected WELCOME")
            }
            XCTAssertEqual(welcome.sessionState, state)
            XCTAssertEqual(welcome.player, 0)
        }
    }

    func testDuplicateQueryParametersAreRejectedNotCrashing() {
        let duplicated = valid + "&secret=ffeeddccbbaa99887766554433221100"
        XCTAssertThrowsError(try JoinPayload.parse(duplicated, nowUnixSeconds: 1_800_000_000)) {
            XCTAssertEqual($0 as? JoinPayload.ValidationError, .invalidCode)
        }
    }
}
