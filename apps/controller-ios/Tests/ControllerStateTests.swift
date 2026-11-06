import XCTest
@testable import MotionControllerIOS

final class ControllerStateTests: XCTestCase {
    func testStateNamesAndOrderMatchProtocolFlow() {
        XCTAssertEqual(
            ControllerState.allCases.map(\.rawValue),
            ["Not Paired", "Pairing", "Calibration", "Connected", "Paused"]
        )
    }

    func testDebugAdvanceCyclesThroughEveryState() {
        var state = ControllerState.notPaired
        for expected in ControllerState.allCases.dropFirst() {
            state = state.next
            XCTAssertEqual(state, expected)
        }
        XCTAssertEqual(state.next, .notPaired)
    }

    func testKeepAwakeIsLimitedToActiveSessionStates() {
        XCTAssertFalse(ControllerState.notPaired.keepsScreenAwake)
        XCTAssertFalse(ControllerState.pairing.keepsScreenAwake)
        XCTAssertTrue(ControllerState.calibration.keepsScreenAwake)
        XCTAssertTrue(ControllerState.connected.keepsScreenAwake)
        XCTAssertFalse(ControllerState.paused.keepsScreenAwake)
    }

    func testJoinWithoutCompletedCalibrationEntersCalibration() {
        let phases: [CalibrationPhase] = [
            .idle, .capturingNeutral, .readyForSlowSwing, .capturingSlowSwing, .failed(.tooShort),
        ]
        for phase in phases {
            XCTAssertEqual(phase.joinAction, .calibrate, "\(phase)")
        }
    }

    func testRejoinAfterCompletedCalibrationResendsStoredCalibration() {
        XCTAssertEqual(CalibrationPhase.complete.joinAction, .resendStoredCalibration)
    }
}
