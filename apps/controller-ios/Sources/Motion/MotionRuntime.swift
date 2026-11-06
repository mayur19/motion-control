import Combine
import Foundation

@MainActor
final class MotionRuntime: ObservableObject {
    let sampler: MotionSampler
    let streamer: MotionStreamer

    @Published private(set) var calibrationPhase: CalibrationPhase = .idle
    @Published private(set) var calibrationMessage = MotionRuntime.initialCalibrationMessage

    private static let initialCalibrationMessage =
        "Select your hand, confirm the screen faces you, then capture neutral."

    private let buffer: MotionSampleBuffer
    private let calibration = SlowSwingCalibration()
    private var cancellables: Set<AnyCancellable> = []
    private var sampling = false
    private var streaming = false
    private var calibrationTask: Task<Void, Never>?
    private var calibrationStartedAt: Date?

    init() {
        let buffer = MotionSampleBuffer(capacity: 256)
        self.buffer = buffer
        sampler = MotionSampler(buffer: buffer)
        streamer = MotionStreamer(buffer: buffer)
        sampler.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        streamer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func update(
        foreground: Bool,
        controllerState: ControllerState,
        host: String,
        port: UInt16
    ) {
        let shouldSample = foreground && controllerState.keepsScreenAwake
        let shouldStream = foreground && controllerState == .connected

        if shouldSample && !sampling {
            sampler.start()
            sampling = true
        } else if !shouldSample && sampling {
            if streaming {
                streamer.stop()
                streaming = false
            }
            sampler.stop(reason: foreground ? "Inactive session" : "Background")
            sampling = false
        }

        if shouldStream && !streaming {
            streamer.start(host: host, port: port)
            streaming = true
        } else if !shouldStream && streaming {
            streamer.stop()
            streaming = false
        }
    }

    func stopForBackground() {
        calibrationTask?.cancel()
        calibrationTask = nil
        if streaming { streamer.stop() }
        if sampling { sampler.stop(reason: "Background") }
        streaming = false
        sampling = false
    }

    func configureIdentity(sessionID: UInt64, controllerID: UInt32) {
        streamer.configure(sessionID: sessionID, controllerID: controllerID)
    }

    /// Clears the active calibration so the player can capture a new one.
    func resetCalibration() {
        calibrationTask?.cancel()
        calibrationTask = nil
        calibration.reset()
        calibrationPhase = calibration.phase
        calibrationMessage = Self.initialCalibrationMessage
    }

    /// Resends the accepted calibration after a rejoin; the host may be a new
    /// process or session that never received it.
    func resendCalibration(
        host: String,
        port: UInt16,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let record = calibration.completedRecord else {
            resetCalibration()
            completion(false)
            return
        }
        streamer.sendCalibration(record, host: host, port: port) { [weak self] sent in
            if !sent {
                self?.calibration.reset()
                self?.publishCalibrationFailure(.sensorsUnavailable)
            }
            completion(sent)
        }
    }

    func beginNeutral(hand: CalibrationHand, screenFacingPlayerConfirmed: Bool) {
        do {
            try calibration.beginNeutral(
                hand: hand,
                screenFacingPlayerConfirmed: screenFacingPlayerConfirmed
            )
            buffer.removeAll()
            calibrationPhase = calibration.phase
            calibrationMessage = "Hold completely still in the neutral grip…"
            startCalibrationTimer(duration: 0.75) { [weak self] in self?.finishNeutral() }
        } catch let failure as CalibrationFailure {
            publishCalibrationFailure(failure)
        } catch {
            publishCalibrationFailure(.sensorsUnavailable)
        }
    }

    func beginSlowSwing(
        host: String,
        port: UInt16,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        calibration.beginSlowSwing()
        guard calibration.phase == .capturingSlowSwing else { return }
        buffer.removeAll()
        calibrationPhase = calibration.phase
        calibrationMessage = "One slow, controlled swing. Do not use full force."
        startCalibrationTimer(duration: 1.5) { [weak self] in
            self?.finishSlowSwing(host: host, port: port, completion: completion)
        }
    }

    private func startCalibrationTimer(
        duration: TimeInterval,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        calibrationTask?.cancel()
        calibrationStartedAt = Date()
        calibrationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                while let sample = self.buffer.takeOne() { self.calibration.append(sample) }
                if Date().timeIntervalSince(self.calibrationStartedAt ?? Date()) >= duration {
                    self.calibrationTask = nil
                    completion()
                    return
                }
            }
        }
    }

    private func finishNeutral() {
        do {
            _ = try calibration.finishNeutral()
            calibrationPhase = calibration.phase
            calibrationMessage = "Neutral accepted. Make one slow practice swing through a comfortable arc."
        } catch let failure as CalibrationFailure {
            publishCalibrationFailure(failure)
        } catch {
            publishCalibrationFailure(.sensorsUnavailable)
        }
    }

    private func finishSlowSwing(
        host: String,
        port: UInt16,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        do {
            let record = try calibration.finishSlowSwing()
            calibrationMessage = "Calibration accepted. Sending to host…"
            streamer.sendCalibration(record, host: host, port: port) { [weak self] sent in
                guard let self else { return }
                if sent {
                    self.calibrationPhase = .complete
                    self.calibrationMessage = "Calibration complete."
                } else {
                    self.publishCalibrationFailure(.sensorsUnavailable)
                }
                completion(sent)
            }
        } catch let failure as CalibrationFailure {
            publishCalibrationFailure(failure)
            completion(false)
        } catch {
            publishCalibrationFailure(.sensorsUnavailable)
            completion(false)
        }
    }

    private func publishCalibrationFailure(_ failure: CalibrationFailure) {
        calibrationPhase = .failed(failure)
        calibrationMessage = failure.rawValue
    }
}
