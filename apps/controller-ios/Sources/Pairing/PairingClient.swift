import Combine
import Foundation
import Network
import UIKit

struct PairingAssignment: Equatable, Sendable {
    let sessionID: UInt64
    let controllerID: UInt32
    let player: UInt8
}

final class PairingClient: ObservableObject, @unchecked Sendable {
    private typealias JoinedHandler = @MainActor @Sendable (PairingAssignment) -> Void
    private typealias HostLostHandler = @MainActor @Sendable (HostLoss) -> Void

    struct StatusFlags: Equatable, Sendable {
        let appActive: Bool
        let sensorValid: Bool
    }

    /// Retry HELLOs go out only on a ready path. Sends issued while the
    /// connection is waiting are queued by Network.framework and flushed as a
    /// burst when the path returns; the `.ready` handler sends one HELLO then.
    static func shouldSendHelloRetry(on state: NWConnection.State) -> Bool {
        if case .ready = state { return true }
        return false
    }

    /// Foreground/background and sensor validity changes are reported at once
    /// (they gate host input); sample-rate updates ride the 500 ms heartbeat.
    static func needsImmediateStatus(from previous: StatusFlags, to next: StatusFlags) -> Bool {
        previous != next
    }

    /// Rejoin covers the largest host reservation (game-configurable, 5-60 s,
    /// default 30 s); the host's reservation decides whether the same player is
    /// restored.
    static let rejoinWindowSeconds: TimeInterval = 60
    private static let rejoinSteadyIntervalSeconds: TimeInterval = 2.5
    /// Quick retries for a brief blip, then steady retries until the window ends.
    static let rejoinRetryDelays: [TimeInterval] = {
        let quick: [TimeInterval] = [0.0, 0.25, 0.75, 1.5]
        let steady = stride(
            from: 1.5 + rejoinSteadyIntervalSeconds,
            to: rejoinWindowSeconds,
            by: rejoinSteadyIntervalSeconds
        )
        return quick + Array(steady)
    }()

    @Published private(set) var status = "Not paired"
    @Published private(set) var errorMessage: String?
    @Published private(set) var assignment: PairingAssignment?

    private let worker = DispatchQueue(label: "MotionBadminton.Pairing")
    private var connection: NWConnection?
    private var attemptToken = UUID()
    private var joinedToken: UUID?
    private var interruptedToken: UUID?
    private var latestPayload: JoinPayload?
    private var joinedHandler: JoinedHandler?
    private var hostLostHandler: HostLostHandler?
    private var hostLiveness: HostLiveness?
    private var sequence: UInt32 = 0
    private var appActive = true
    private var sensorValid = true
    private var actualSampleHz: UInt16 = 0
    private let installationID: String = {
        let defaults = UserDefaults.standard
        let key = "motionBadmintonInstallationID"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        defaults.set(created, forKey: key)
        return created
    }()

    @MainActor
    func join(
        rawValue: String,
        onHostLost: @escaping @MainActor @Sendable (HostLoss) -> Void = { _ in },
        onJoined: @escaping @MainActor @Sendable (PairingAssignment) -> Void
    ) {
        let payload: JoinPayload
        do {
            payload = try JoinPayload.parse(rawValue)
        } catch let error as JoinPayload.ValidationError {
            errorMessage = error.rawValue
            status = "Join failed"
            return
        } catch {
            errorMessage = JoinPayload.ValidationError.invalidCode.rawValue
            status = "Join failed"
            return
        }
        status = "Contacting host"
        errorMessage = nil
        assignment = nil
        latestPayload = payload
        joinedHandler = onJoined
        hostLostHandler = onHostLost
        let token = UUID()
        attemptToken = token
        joinedToken = nil
        worker.async { [weak self] in
            self?.begin(payload: payload, token: token, onJoined: onJoined)
        }
    }

    @MainActor
    func cancel() {
        attemptToken = UUID()
        joinedToken = nil
        interruptedToken = nil
        latestPayload = nil
        joinedHandler = nil
        hostLostHandler = nil
        worker.async { [weak self] in
            self?.connection?.cancel()
            self?.connection = nil
        }
        status = "Not paired"
    }

    func updateStatus(appActive: Bool, sensorValid: Bool, actualSampleHz: Int) {
        worker.async { [weak self] in
            guard let self else { return }
            let returnedToForeground = !self.appActive && appActive
            let previousFlags = StatusFlags(appActive: self.appActive, sensorValid: self.sensorValid)
            self.appActive = appActive
            self.sensorValid = sensorValid
            self.actualSampleHz = UInt16(clamping: actualSampleHz)
            if returnedToForeground,
               self.assignment != nil,
               let payload = self.latestPayload,
               let onJoined = self.joinedHandler {
                self.restartAfterPathChange(payload: payload, onJoined: onJoined)
                return
            }
            let nextFlags = StatusFlags(appActive: appActive, sensorValid: sensorValid)
            if Self.needsImmediateStatus(from: previousFlags, to: nextFlags),
               let connection = self.connection,
               let assignment = self.assignment,
               let token = self.joinedToken {
                self.sendStatus(connection: connection, assignment: assignment, token: token)
            }
        }
    }

    private func begin(
        payload: JoinPayload,
        token: UUID,
        onJoined: @escaping JoinedHandler,
        retryDelays: [TimeInterval] = [0.0, 0.25, 0.75, 1.5, 2.5],
        timeoutSeconds: TimeInterval = 3.5
    ) {
        connection?.cancel()
        guard let port = NWEndpoint.Port(rawValue: payload.port) else {
            publishError("The pairing code contains an invalid network port.")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(payload.host), port: port, using: .udp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.attemptToken == token else { return }
            switch state {
            case .waiting:
                if self.joinedToken == token {
                    self.interruptedToken = token
                }
            case .ready:
                if self.joinedToken != token {
                    self.sendHello(connection: connection, payload: payload)
                } else if self.interruptedToken == token, self.appActive {
                    self.restartAfterPathChange(payload: payload, onJoined: onJoined)
                }
            case .failed:
                if self.joinedToken == token, self.appActive {
                    self.restartAfterPathChange(payload: payload, onJoined: onJoined)
                }
            default:
                break
            }
        }
        connection.start(queue: worker)
        receiveWelcome(connection: connection, payload: payload, token: token, onJoined: onJoined)

        for delay in retryDelays {
            worker.asyncAfter(deadline: .now() + delay) { [weak self, weak connection] in
                guard let self, let connection, self.attemptToken == token,
                      self.joinedToken != token,
                      Self.shouldSendHelloRetry(on: connection.state) else { return }
                self.sendHello(connection: connection, payload: payload)
            }
        }
        worker.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
            guard let self, self.attemptToken == token, self.joinedToken != token else { return }
            self.attemptToken = UUID()
            connection.cancel()
            self.publishError("The host is unreachable. Check Wi-Fi and ask for a new code.")
        }
    }

    private func restartAfterPathChange(payload: JoinPayload, onJoined: @escaping JoinedHandler) {
        let token = UUID()
        attemptToken = token
        joinedToken = nil
        interruptedToken = nil
        connection?.cancel()
        connection = nil
        Task { @MainActor in
            status = "Reconnecting"
            errorMessage = nil
        }
        begin(
            payload: payload,
            token: token,
            onJoined: onJoined,
            retryDelays: Self.rejoinRetryDelays,
            timeoutSeconds: Self.rejoinWindowSeconds
        )
    }

    private func sendHello(connection: NWConnection, payload: JoinPayload) {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "unknown"
        let hello = ProtocolV1.Hello(
            pairingSecret: payload.pairingSecret,
            platform: 1,
            capabilities: 0x000F,
            maxSampleHz: UInt16(MotionSampler.requestedHz),
            deviceModel: "iOS Controller#\(installationID)",
            appVersion: appVersion,
            osVersion: String(ProcessInfo.processInfo.operatingSystemVersionString.prefix(31))
        )
        do {
            let data = try ProtocolV1.encode(ProtocolV1.Message(
                header: ProtocolV1.Header(
                    protocolVersion: ProtocolV1.version,
                    messageType: .hello,
                    flags: 0,
                    sessionID: payload.sessionID,
                    controllerID: 0,
                    sequence: sequence
                ),
                payload: .hello(hello)
            ))
            sequence &+= 1
            connection.send(content: data, completion: .contentProcessed { _ in })
        } catch {
            publishError("The controller could not encode its join request.")
        }
    }

    private func receiveWelcome(
        connection: NWConnection,
        payload: JoinPayload,
        token: UUID,
        onJoined: @escaping JoinedHandler
    ) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection, self.attemptToken == token else { return }
            guard error == nil, let data else {
                self.receiveWelcome(
                    connection: connection, payload: payload, token: token, onJoined: onJoined
                )
                return
            }
            do {
                let decoded = try ProtocolV1.decode(data)
                guard decoded.header.messageType == .welcome,
                      decoded.header.sessionID == payload.sessionID,
                      case let .welcome(welcome) = decoded.payload
                else {
                    self.receiveWelcome(
                        connection: connection, payload: payload, token: token, onJoined: onJoined
                    )
                    return
                }
                if welcome.sessionState == 1 {
                    let assignment = PairingAssignment(
                        sessionID: payload.sessionID,
                        controllerID: decoded.header.controllerID,
                        player: welcome.player
                    )
                    self.joinedToken = token
                    self.hostLiveness = HostLiveness(
                        timeoutMilliseconds: welcome.disconnectTimeoutMs,
                        now: DispatchTime.now().uptimeNanoseconds
                    )
                    self.receiveControl(
                        connection: connection,
                        assignment: assignment,
                        token: token
                    )
                    self.scheduleHeartbeat(
                        connection: connection,
                        assignment: assignment,
                        token: token
                    )
                    Task { @MainActor in
                        self.assignment = assignment
                        self.status = "Player \(assignment.player) connected"
                        self.errorMessage = nil
                        onJoined(assignment)
                    }
                } else {
                    self.attemptToken = UUID()
                    connection.cancel()
                    self.publishError(Self.message(for: welcome.sessionState))
                }
            } catch {
                self.receiveWelcome(
                    connection: connection, payload: payload, token: token, onJoined: onJoined
                )
            }
        }
    }

    private func scheduleHeartbeat(
        connection: NWConnection,
        assignment: PairingAssignment,
        token: UUID
    ) {
        worker.asyncAfter(deadline: .now() + 0.5) { [weak self, weak connection] in
            guard let self, let connection, self.joinedToken == token else { return }
            if self.appActive,
               let liveness = self.hostLiveness,
               liveness.isExpired(at: DispatchTime.now().uptimeNanoseconds) {
                self.handleHostLoss(.timedOut, token: token)
                return
            }
            self.sendStatus(connection: connection, assignment: assignment, token: token)
            self.scheduleHeartbeat(connection: connection, assignment: assignment, token: token)
        }
    }

    private func sendStatus(
        connection: NWConnection,
        assignment: PairingAssignment,
        token: UUID
    ) {
        guard joinedToken == token else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let message = ProtocolV1.Message(
            header: ProtocolV1.Header(
                protocolVersion: ProtocolV1.version,
                messageType: .status,
                flags: 0,
                sessionID: assignment.sessionID,
                controllerID: assignment.controllerID,
                sequence: sequence
            ),
            payload: .status(ProtocolV1.Status(
                senderMonotonicNs: now,
                batteryPercent: 255,
                sensorState: sensorValid ? 2 : 3,
                appState: appActive ? 0 : 1,
                pauseReason: appActive ? 0 : 1,
                actualSampleHz: actualSampleHz,
                lastMotionSequence: 0
            ))
        )
        sequence &+= 1
        if let data = try? ProtocolV1.encode(message) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func receiveControl(
        connection: NWConnection,
        assignment: PairingAssignment,
        token: UUID
    ) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            let receiveTime = DispatchTime.now().uptimeNanoseconds
            guard let self, let connection, self.joinedToken == token, error == nil else { return }
            defer {
                self.receiveControl(connection: connection, assignment: assignment, token: token)
            }
            guard let data, let decoded = try? ProtocolV1.decode(data) else { return }
            let ping: ProtocolV1.Ping
            switch HostControlEvent.classify(decoded, for: assignment) {
            case .unrelated:
                return
            case .alive:
                self.hostLiveness = self.hostLiveness?.recording(receiveTime)
                return
            case .goodbye:
                self.handleHostLoss(.ended, token: token)
                return
            case let .ping(received):
                self.hostLiveness = self.hostLiveness?.recording(receiveTime)
                ping = received
            }
            let sendTime = DispatchTime.now().uptimeNanoseconds
            let pong = ProtocolV1.Message(
                header: ProtocolV1.Header(
                    protocolVersion: ProtocolV1.version,
                    messageType: .pong,
                    flags: 0,
                    sessionID: assignment.sessionID,
                    controllerID: assignment.controllerID,
                    sequence: self.sequence
                ),
                payload: .pong(ProtocolV1.Pong(
                    pingID: ping.pingID,
                    echoSenderMonotonicNs: ping.senderMonotonicNs,
                    receiverReceiveMonotonicNs: receiveTime,
                    receiverSendMonotonicNs: sendTime
                ))
            )
            self.sequence &+= 1
            if let response = try? ProtocolV1.encode(pong) {
                connection.send(content: response, completion: .contentProcessed { _ in })
            }
        }
    }

    /// Leaves Connected when the host stops answering or says GOODBYE. A
    /// timeout reuses the bounded re-HELLO loop so a brief host-side outage can
    /// reclaim the same reservation; GOODBYE ends the pairing.
    private func handleHostLoss(_ loss: HostLoss, token: UUID) {
        guard joinedToken == token else { return }
        hostLiveness = nil
        let handler = hostLostHandler
        Task { @MainActor in handler?(loss) }
        switch loss {
        case .timedOut:
            guard let payload = latestPayload, let onJoined = joinedHandler else { return }
            restartAfterPathChange(payload: payload, onJoined: onJoined)
        case .ended:
            attemptToken = UUID()
            joinedToken = nil
            connection?.cancel()
            connection = nil
            Task { @MainActor in assignment = nil }
            publishError("The host ended the session. Scan the new host code to join again.")
        }
    }

    private func publishError(_ message: String) {
        Task { @MainActor in
            errorMessage = message
            status = "Join failed"
        }
    }

    private static func message(for state: UInt8) -> String {
        switch state {
        case 2: "This pairing code has expired. Ask the host for a new code."
        case 3: "The pairing code was rejected. Scan the current host code again."
        case 4: "The host already has two controllers connected."
        case 5: "The host does not support this controller version."
        default: "The host rejected the join request."
        }
    }
}
