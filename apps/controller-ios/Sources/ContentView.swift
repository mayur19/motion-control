import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controllerState: ControllerState = .notPaired
    @State private var debugHost = "127.0.0.1"
    @State private var debugPort = "7000"
    @State private var manualJoinURI = ""
    @State private var showingScanner = false
    @State private var processedLaunchJoin = false
    @State private var calibrationHand: CalibrationHand = .right
    @State private var screenFacingConfirmed = false
    @StateObject private var motion = MotionRuntime()
    @StateObject private var pairing = PairingClient()

    private let accent = Color(red: 0.33, green: 0.84, blue: 0.65)
    private let panel = Color(red: 0.10, green: 0.15, blue: 0.21)

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.086, blue: 0.125)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    stateCard
                    debugPanel
                    permissionSummary
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            updateIdleTimer(for: controllerState)
            updateMotionRuntime()
            #if DEBUG
            // Debug automation only (Xcode/devicectl launch arguments); release
            // builds join solely through a user-scanned code.
            if !processedLaunchJoin {
                processedLaunchJoin = true
                if let argument = ProcessInfo.processInfo.arguments.first(where: {
                    $0.hasPrefix("--join-uri=")
                }) {
                    beginJoin(String(argument.dropFirst("--join-uri=".count)))
                }
            }
            #endif
        }
        .onChange(of: controllerState) { _, newState in
            updateIdleTimer(for: newState)
            updateMotionRuntime()
        }
        .onChange(of: scenePhase) { _, newPhase in
            UIApplication.shared.isIdleTimerDisabled =
                newPhase == .active && controllerState.keepsScreenAwake
            if newPhase != .active && controllerState.keepsScreenAwake {
                pairing.updateStatus(
                    appActive: false,
                    sensorValid: motion.sampler.snapshot.status == "Sampling",
                    actualSampleHz: motion.sampler.snapshot.actualHz
                )
                motion.stopForBackground()
                controllerState = .paused
            } else {
                if newPhase == .active,
                   controllerState == .paused,
                   pairing.assignment != nil {
                    controllerState = motion.calibrationPhase == .complete ? .connected : .calibration
                }
                updateMotionRuntime()
                pairing.updateStatus(
                    appActive: newPhase == .active,
                    sensorValid: motion.sampler.snapshot.status == "Sampling",
                    actualSampleHz: motion.sampler.snapshot.actualHz
                )
            }
        }
		.onReceive(motion.sampler.$snapshot) { snapshot in
			pairing.updateStatus(
				appActive: scenePhase == .active,
				sensorValid: snapshot.status == "Sampling",
				actualSampleHz: snapshot.actualHz
			)
		}
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            motion.stopForBackground()
        }
        .sheet(isPresented: $showingScanner) {
            QRScannerView(
                onCode: { value in
                    showingScanner = false
                    beginJoin(value)
                },
                onError: { message in
                    showingScanner = false
                    manualJoinURI = ""
                    pairing.cancel()
                    // The manual entry remains visible in the debug panel.
                    print(message)
                }
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MOTION BADMINTON")
                    .font(.headline.weight(.bold))
                Text("iPhone controller")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("v\(appVersion)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var stateCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.14))
                    .frame(width: 94, height: 94)
                Image(systemName: stateSymbol)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(spacing: 8) {
                Text(controllerState.rawValue.uppercased())
                    .font(.title2.weight(.bold))
                Text(controllerState.guidance)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                controllerState = controllerState.next
            } label: {
                Label("Advance debug state", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .foregroundStyle(.black)
            .accessibilityIdentifier("advance-state")

            if controllerState == .notPaired || controllerState == .pairing {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan host QR", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(accent)
            }

            if controllerState == .calibration {
                calibrationControls
            }

            if controllerState == .connected {
                Button {
                    motion.resetCalibration()
                    controllerState = .calibration
                } label: {
                    Label("Recalibrate", systemImage: "gyroscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .accessibilityIdentifier("recalibrate")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var calibrationControls: some View {
        VStack(spacing: 12) {
            Picker("Hand", selection: $calibrationHand) {
                ForEach(CalibrationHand.allCases) { hand in Text(hand.title).tag(hand) }
            }
            .pickerStyle(.segmented)
            Toggle("Screen faces me", isOn: $screenFacingConfirmed)
            Text(motion.calibrationMessage)
                .font(.caption)
                .foregroundStyle(motion.calibrationPhase.isFailure ? .orange : .secondary)
                .multilineTextAlignment(.center)
            Text("Safety: use only a slow practice swing — never a full-force swing during calibration.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            Button(calibrationActionTitle) { performCalibrationAction() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .foregroundStyle(.black)
                .disabled(calibrationActionDisabled)
        }
        .padding(.top, 4)
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("DEBUG PANEL", systemImage: "wrench.and.screwdriver")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            debugRow("State", controllerState.rawValue)
            debugRow("Device", UIDevice.current.model)
            debugRow("System", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            debugRow("Build", "\(appVersion) (\(buildNumber))")
            debugRow("Keep awake", controllerState.keepsScreenAwake ? "Enabled" : "Disabled")
            debugRow("Pairing", pairing.status)
            if let assignment = pairing.assignment {
                debugRow("Assignment", "Player \(assignment.player) / \(String(assignment.controllerID, radix: 16))")
            }
            if let error = pairing.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            TextField("Paste join URI", text: $manualJoinURI)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button("Join pasted code") { beginJoin(manualJoinURI) }
                .buttonStyle(.bordered)
            Divider()
            Text("TEMPORARY UDP DESTINATION")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                TextField("Host", text: $debugHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $debugPort)
                    .keyboardType(.numberPad)
                    .frame(width: 84)
                    .textFieldStyle(.roundedBorder)
            }
            .onChange(of: debugHost) { _, _ in restartStreamingIfNeeded() }
            .onChange(of: debugPort) { _, _ in restartStreamingIfNeeded() }
            debugRow("Sensor", motion.sampler.snapshot.status)
            debugRow(
                "Requested / actual",
                "\(motion.sampler.snapshot.requestedHz) / \(motion.sampler.snapshot.actualHz) Hz"
            )
            debugRow("Queued", "\(motion.sampler.snapshot.buffer.queued) / 256")
            debugRow("Dropped local", "\(motion.sampler.snapshot.buffer.droppedForCapacity)")
            debugRow("Non-monotonic", "\(motion.sampler.snapshot.buffer.rejectedNonMonotonic)")
            debugRow("Network", motion.streamer.snapshot.status)
            debugRow("Sent / rate", "\(motion.streamer.snapshot.sent) / \(motion.streamer.snapshot.sentHz) Hz")
            debugRow("Network errors", "\(motion.streamer.snapshot.networkErrors)")
            debugRow("Last send", lastSendDescription)
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private var permissionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions are requested only when needed")
                .font(.subheadline.weight(.semibold))
            Label("Camera — scan the host session QR code", systemImage: "camera")
            Label("Motion — read swings during active play", systemImage: "gyroscope")
            Label("Local network — connect directly to the host", systemImage: "wifi")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func debugRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospaced())
                .multilineTextAlignment(.trailing)
        }
    }

    private func updateIdleTimer(for state: ControllerState) {
        UIApplication.shared.isIdleTimerDisabled =
            scenePhase == .active && state.keepsScreenAwake
    }

    private func updateMotionRuntime() {
        motion.update(
            foreground: scenePhase == .active,
            controllerState: controllerState,
            host: debugHost,
            port: UInt16(debugPort) ?? 7000
        )
    }

    private func restartStreamingIfNeeded() {
        guard controllerState == .connected, scenePhase == .active else { return }
        motion.streamer.stop()
        motion.streamer.start(host: debugHost, port: UInt16(debugPort) ?? 7000)
    }

    private func beginJoin(_ rawValue: String) {
        // Pairing and high-rate motion use separate UDP connections. Carry the
        // validated join destination into MotionRuntime before the assignment
        // transitions the controller to Connected and starts streaming.
        if let payload = try? JoinPayload.parse(rawValue) {
            debugHost = payload.host
            debugPort = String(payload.port)
        }
        controllerState = .pairing
        pairing.join(rawValue: rawValue, onHostLost: { loss in
            // Leaving Connected stops MotionRuntime streaming to a silent host.
            controllerState = loss == .ended ? .notPaired : .pairing
        }) { assignment in
            motion.configureIdentity(
                sessionID: assignment.sessionID,
                controllerID: assignment.controllerID
            )
            UIApplication.shared.isIdleTimerDisabled = true
            switch motion.calibrationPhase.joinAction {
            case .calibrate:
                controllerState = .calibration
            case .resendStoredCalibration:
                motion.resendCalibration(host: debugHost, port: UInt16(debugPort) ?? 7000) { sent in
                    controllerState = sent ? .connected : .calibration
                }
            }
        }
    }

    private func performCalibrationAction() {
        switch motion.calibrationPhase {
        case .idle, .failed:
            motion.beginNeutral(
                hand: calibrationHand,
                screenFacingPlayerConfirmed: screenFacingConfirmed
            )
        case .readyForSlowSwing:
            motion.beginSlowSwing(host: debugHost, port: UInt16(debugPort) ?? 7000) { sent in
                if sent { controllerState = .connected }
            }
        default:
            break
        }
    }

    private var calibrationActionTitle: String {
        switch motion.calibrationPhase {
        case .readyForSlowSwing: "Start slow swing"
        case .capturingNeutral: "Capturing neutral…"
        case .capturingSlowSwing: "Capturing slow swing…"
        case .complete: "Calibration complete"
        default: "Capture neutral pose"
        }
    }

    private var calibrationActionDisabled: Bool {
        switch motion.calibrationPhase {
        case .capturingNeutral, .capturingSlowSwing, .complete: true
        default: !screenFacingConfirmed
        }
    }

    private var lastSendDescription: String {
        guard let last = motion.streamer.snapshot.lastSuccessfulSendNanoseconds else { return "Never" }
        let now = DispatchTime.now().uptimeNanoseconds
        let ageMilliseconds = now >= last ? (now - last) / 1_000_000 : 0
        return "\(ageMilliseconds) ms ago"
    }

    private var stateSymbol: String {
        switch controllerState {
        case .notPaired: "iphone.slash"
        case .pairing: "qrcode.viewfinder"
        case .calibration: "gyroscope"
        case .connected: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }
}

private extension CalibrationPhase {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

#Preview {
    ContentView()
}
