import Foundation

/// Controller-side view of whether the host is still alive.
///
/// The host sends STATUS every heartbeat interval (protocol section 4.7). If no
/// valid host packet for this controller arrives within WELCOME
/// `disconnect_timeout_ms`, the host is treated as lost. Uses monotonic
/// nanoseconds (`DispatchTime.uptimeNanoseconds`).
struct HostLiveness: Equatable, Sendable {
    static let defaultTimeoutNanoseconds: UInt64 = 2_000_000_000
    private static let nanosecondsPerMillisecond: UInt64 = 1_000_000

    let timeoutNanoseconds: UInt64
    let lastHeardNanoseconds: UInt64

    init(timeoutMilliseconds: UInt16, now: UInt64) {
        let configured = UInt64(timeoutMilliseconds) * Self.nanosecondsPerMillisecond
        self.init(timeoutNanoseconds: configured > 0 ? configured : Self.defaultTimeoutNanoseconds, lastHeard: now)
    }

    private init(timeoutNanoseconds: UInt64, lastHeard: UInt64) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.lastHeardNanoseconds = lastHeard
    }

    func recording(_ now: UInt64) -> HostLiveness {
        HostLiveness(timeoutNanoseconds: timeoutNanoseconds, lastHeard: max(lastHeardNanoseconds, now))
    }

    func isExpired(at now: UInt64) -> Bool {
        now > lastHeardNanoseconds && now - lastHeardNanoseconds > timeoutNanoseconds
    }
}

/// What a decoded control-path packet means to a joined controller.
enum HostControlEvent: Equatable, Sendable {
    case ping(ProtocolV1.Ping)
    case alive
    case goodbye(reason: UInt8)
    case unrelated

    static func classify(_ message: ProtocolV1.Message, for assignment: PairingAssignment) -> HostControlEvent {
        guard message.header.sessionID == assignment.sessionID,
              message.header.controllerID == assignment.controllerID
        else { return .unrelated }
        switch message.payload {
        case let .ping(ping): return .ping(ping)
        case let .goodbye(goodbye): return .goodbye(reason: goodbye.reason)
        default: return .alive
        }
    }
}

/// Why a joined controller stopped treating the host as connected.
enum HostLoss: Equatable, Sendable {
    /// No host packet within the disconnect timeout; the client retries re-HELLO.
    case timedOut
    /// The host sent GOODBYE; the session is over and a new code is needed.
    case ended
}
