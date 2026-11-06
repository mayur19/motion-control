import Foundation

enum ControllerState: String, CaseIterable, Identifiable {
    case notPaired = "Not Paired"
    case pairing = "Pairing"
    case calibration = "Calibration"
    case connected = "Connected"
    case paused = "Paused"

    var id: Self { self }

    var next: Self {
        let states = Self.allCases
        let currentIndex = states.firstIndex(of: self) ?? states.startIndex
        return states[states.index(after: currentIndex) % states.count]
    }

    var keepsScreenAwake: Bool {
        self == .calibration || self == .connected
    }

    var guidance: String {
        switch self {
        case .notPaired:
            "Scan the host QR code to begin."
        case .pairing:
            "Contacting the host and requesting a player slot."
        case .calibration:
            "Hold the phone securely and follow the slow-swing guide."
        case .connected:
            "Controller is active. Keep the phone secured with a wrist strap."
        case .paused:
            "Motion streaming is paused until the session resumes."
        }
    }
}
