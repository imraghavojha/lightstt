import Foundation

@MainActor
public final class RecordingTriggerRouter {
    private let recording: any RecordingControlling
    private let scheduler: any RuntimeScheduling
    private var pushSession: SessionID?
    private var mouseSession: SessionID?
    private var mouseDownTime: TimeInterval?

    public init(recording: any RecordingControlling, scheduler: any RuntimeScheduling) {
        self.recording = recording
        self.scheduler = scheduler
    }

    public func handle(_ event: ShortcutEvent) {
        switch event {
        case .toggle:
            switch recording.snapshot.phase {
            case .idle: recording.start(trigger: .toggle)
            case .starting: recording.cancel()
            case .recording: recording.stop()
            case .error:
                recording.cancel()
                if case .idle = recording.snapshot.phase { recording.start(trigger: .toggle) }
            default: break
            }
        case .pushDown:
            if case .error = recording.snapshot.phase { recording.cancel() }
            if case .idle = recording.snapshot.phase {
                recording.start(trigger: .pushToTalk)
                pushSession = recording.snapshot.sessionID
            }
        case .pushUp:
            finishOwned(pushSession)
            pushSession = nil
        case .mouseDown:
            mouseDownTime = scheduler.monotonicTime
            if case .idle = recording.snapshot.phase {
                recording.start(trigger: .mouse)
                mouseSession = recording.snapshot.sessionID
            } else if case .recording = recording.snapshot.phase {
                mouseSession = nil
                recording.stop()
            }
        case .mouseUp:
            if let down = mouseDownTime, scheduler.monotonicTime - down >= 0.3 {
                finishOwned(mouseSession)
                mouseSession = nil
            }
            mouseDownTime = nil
        case .cancel:
            switch recording.snapshot.phase {
            case .starting, .recording: recording.cancel()
            default: break
            }
        }
    }

    private func finishOwned(_ session: SessionID?) {
        guard let session, recording.snapshot.sessionID == session else { return }
        switch recording.snapshot.phase {
        case .starting: recording.cancel()
        case .recording: recording.stop()
        default: break
        }
    }
}
