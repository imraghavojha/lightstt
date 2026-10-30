import AppKit
import CoreAudio
import AudioToolbox

final class AudioSettings: @unchecked Sendable {
    private let gate = MediaGate()
    private let sessionQueue = DispatchQueue(label: "com.lighttts.audio-session")
    private var volumeSession: OutputVolumeSession?
    private let pauseSession: MediaPauseSession
    init(media: (any MediaControlling)? = nil) {
        pauseSession = MediaPauseSession(controller: (ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty ? (media ?? SystemMediaController(gate: gate)) : NoopMediaController())
    }
    private let volumeQueue = DispatchQueue(label: "com.lighttts.volume")

    static func device(for uid: String, scope: AudioObjectPropertyScope) -> AudioDeviceID? {
        if uid.isEmpty { return defaultDevice(scope: scope) }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return nil }
        for device in devices {
            var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var value: CFString = "" as CFString
            var length = UInt32(MemoryLayout<CFString>.size)
            let status = withUnsafeMutablePointer(to: &value) { pointer in AudioObjectGetPropertyData(device, &property, 0, nil, &length, pointer) }
            if status == noErr, value as String == uid { return device }
        }
        return nil
    }
    private static func defaultDevice(scope: AudioObjectPropertyScope) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: scope == kAudioDevicePropertyScopeInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr ? device : nil
    }
    private static func volume(_ device: AudioDeviceID, scope: AudioObjectPropertyScope, set: Float32? = nil) -> Float32? {
        for element: AudioObjectPropertyElement in [0, 1] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value = set ?? 0; var size = UInt32(MemoryLayout<Float32>.size)
            let status = set == nil ? AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) : AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
            if status == noErr { return value }
        }
        return nil
    }
    fileprivate static func outputVolumes(_ device: AudioDeviceID) -> [(AudioObjectPropertyElement, Float32)] {
        func read(_ element: AudioObjectPropertyElement) -> Float32? {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address), AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return nil }
            var value: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        if let master = read(0) { return [(0, master)] }
        return [1, 2].compactMap { element in read(element).map { (element, $0) } }
    }
    fileprivate static func setOutputVolume(_ device: AudioDeviceID, element: AudioObjectPropertyElement, value: Float32) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        var value = value
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
    func begin(completion: @escaping @Sendable (String?) -> Void) {
        let token = gate.start()
        sessionQueue.async { [self] in
            guard gate.isCurrent(token) else { return }
            gate.setOperation(token)
            let warning = beginSession()
            if !gate.isCurrent(token) { endSession() } else { completion(warning) }
        }
    }
    private func beginSession() -> String? {
        let defaults = UserDefaults.standard
        let testAudio = !(ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty
        if !testAudio, defaults.bool(forKey: "increaseMicVolume"), let input = Self.device(for: defaults.string(forKey: "inputDeviceUID") ?? "", scope: kAudioDevicePropertyScopeInput) { _ = Self.volume(input, scope: kAudioDevicePropertyScopeInput, set: 1) }
        let mode = defaults.string(forKey: "recordingSound") ?? "Pause"
        if mode == "Pause" {
            do { try pauseSession.begin() }
            catch { return "Couldn't pause media: \(error.localizedDescription)" }
        }
        if ["Mute", "Lower"].contains(mode), !testAudio {
            volumeQueue.async { [self] in
                guard let device = Self.defaultDevice(scope: kAudioDevicePropertyScopeOutput) else { return }
                let session = OutputVolumeSession(controller: SystemOutputVolume(device: device)); self.volumeSession = session
                session.begin(factor: mode == "Mute" ? 0 : 0.3)
            }
        }
        return nil
    }
    func end() {
        gate.stop()
        sessionQueue.async { [self] in endSession() }
    }
    private func endSession() {
        volumeQueue.async { [self] in
            self.volumeSession?.end(); self.volumeSession = nil
        }
        pauseSession.end()
    }
    func waitForRestoration() async { await withCheckedContinuation { continuation in sessionQueue.async { [self] in volumeQueue.async { continuation.resume() } } } }
    static func cue(start: Bool) {
        guard (ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty else { return }
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: "soundEffects") ?? "Classic"
        guard style != "Off", let sound = NSSound(named: NSSound.Name(style == "Simple" ? "Tink" : (start ? "Glass" : "Pop"))) else { return }
        sound.volume = Float(defaults.object(forKey: "soundVolume") as? Double ?? 0.8); sound.play()
    }
}

private struct SystemOutputVolume: OutputVolumeControlling {
    let device: AudioDeviceID
    func volumes() -> [(UInt32, Float)] { AudioSettings.outputVolumes(device) }
    func setVolume(_ value: Float, channel: UInt32) { AudioSettings.setOutputVolume(device, element: channel, value: value) }
}
// MediaRemote provides the system media-key target without Apple Events.
private final class SystemMediaController: MediaControlling {
    let gate: MediaGate
    private let intent = MediaIntentTracker()
    private var observers: [NSObjectProtocol] = []
    private static let framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    private typealias IsPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias GetClient = @convention(c) (DispatchQueue, @escaping @convention(block) (UnsafeRawPointer?) -> Void) -> Void
    private typealias GetBundle = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias RegisterNotifications = @convention(c) (DispatchQueue) -> Void
    init(gate: MediaGate) {
        self.gate = gate
        guard let handle = Self.framework, let symbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"), object: nil, queue: nil) { [intent] notification in
            if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1" { NSLog("LIGHTTTS_TRACE media playback notification %@", String(describing: notification.userInfo)) }
            intent.playbackChanged(notification.userInfo?["kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey"] as? Bool)
        })
        observers.append(center.addObserver(forName: Notification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"), object: nil, queue: nil) { [intent] _ in
            if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1" { NSLog("LIGHTTTS_TRACE media player notification") }
            intent.playerChanged()
        })
        unsafeBitCast(symbol, to: RegisterNotifications.self)(DispatchQueue.global())
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func trace(_ message: String) {
        if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1" { NSLog("LIGHTTTS_TRACE media %@", message) }
    }

    private func target() -> String? {
        guard let handle = Self.framework,
              let querySymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingClient"),
              let bundleSymbol = dlsym(handle, "MRNowPlayingClientGetBundleIdentifier") else { return nil }
        let query = unsafeBitCast(querySymbol, to: GetClient.self)
        let bundle = unsafeBitCast(bundleSymbol, to: GetBundle.self)
        let semaphore = DispatchSemaphore(value: 0), lock = NSLock()
        var identity: String?
        query(DispatchQueue.global()) { client in
            if let client, let identifier = bundle(client)?.takeUnretainedValue() as String?, !identifier.isEmpty {
                lock.lock(); identity = identifier; lock.unlock()
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 1) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }; return identity
    }
    private func isPlaying() -> Bool? {
        guard let handle = Self.framework, let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else { return nil }
        let query = unsafeBitCast(symbol, to: IsPlaying.self)
        let semaphore = DispatchSemaphore(value: 0), lock = NSLock()
        var playing = false
        query(DispatchQueue.global()) { value in lock.lock(); playing = value; lock.unlock(); semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 1) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }; return playing
    }
    private func send(_ command: UInt32) -> Bool {
        guard let handle = Self.framework, let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return false }
        return unsafeBitCast(symbol, to: SendCommand.self)(command, nil)
    }
    private func processIdentity(_ bundle: String) -> [String]? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
        guard apps.count == 1, let app = apps.first, let launch = app.launchDate else { return nil }
        return [bundle, String(app.processIdentifier), String(launch.timeIntervalSince1970)]
    }
    func pausePlaying() throws -> [String] {
        let bundle = target(), playing = isPlaying()
        let identity = bundle.flatMap { processIdentity($0) }
        trace("pause target=\(bundle ?? "nil") identity=\(identity?.joined(separator: "/") ?? "nil") playing=\(String(describing: playing))")
        guard let bundle, let identity, playing == true,
              target() == bundle, processIdentity(bundle) == identity else { trace("pause skipped"); return [] }
        intent.begin()
        guard gate.ifActive({ send(1) }) else { intent.cancel(); trace("pause skipped"); return [] }
        trace("pause sent")
        return identity
    }
    func resume(_ players: [String]) {
        guard players.count == 3, let identity = players.first else { intent.cancel(); return }
        // MediaRemote may report the old playing state briefly after a pause.
        Thread.sleep(forTimeInterval: 0.2)
        let stopped = gate.ifStopped { true }, bundle = target(), process = processIdentity(identity), playing = isPlaying()
        trace("resume stopped=\(stopped) target=\(bundle ?? "nil") identity=\(process?.joined(separator: "/") ?? "nil") playing=\(String(describing: playing))")
        guard stopped, bundle == identity, process == players, playing == false, target() == identity, processIdentity(identity) == players else { intent.cancel(); trace("resume skipped"); return }
        trace("resume sent=\(intent.finish { gate.ifStopped { send(0) } })")
    }
}
