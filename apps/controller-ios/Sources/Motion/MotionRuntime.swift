import Combine
import Foundation

@MainActor
final class MotionRuntime: ObservableObject {
    let sampler: MotionSampler
    let streamer: MotionStreamer

    private var cancellables: Set<AnyCancellable> = []
    private var sampling = false
    private var streaming = false

    init() {
        let buffer = MotionSampleBuffer(capacity: 256)
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
        if streaming { streamer.stop() }
        if sampling { sampler.stop(reason: "Background") }
        streaming = false
        sampling = false
    }

    func configureIdentity(sessionID: UInt64, controllerID: UInt32) {
        streamer.configure(sessionID: sessionID, controllerID: controllerID)
    }
}
