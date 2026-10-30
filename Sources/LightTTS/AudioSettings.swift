import AppKit
import CoreAudio
import AudioToolbox
import CoreAudioTapKit
import IOKit.hidsystem

/// Applies input and output settings for the lifetime of one recording.
final class AudioSettings {
    private var output: AudioDeviceID = 0
    private var previousVolume: Float32?
    private var changedVolume: Float32?
    private let pauseSession: MediaPauseSession
    init(media: any MediaControlling = SystemMediaController()) {
        pauseSession = MediaPauseSession(controller: (ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty ? media : NoopMediaController())
    }
    private let muffleQueue = DispatchQueue(label: "com.lighttts.muffle")
    private var muffleSession: AnyObject?

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
    func begin() -> String? {
        let defaults = UserDefaults.standard
        let testAudio = !(ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty
        if !testAudio, defaults.bool(forKey: "increaseMicVolume"), let input = Self.device(for: defaults.string(forKey: "inputDevice") ?? "", scope: kAudioDevicePropertyScopeInput) { _ = Self.volume(input, scope: kAudioDevicePropertyScopeInput, set: 1) }
        let mode = defaults.string(forKey: "recordingSound") ?? "Pause"
        if mode == "Pause" {
            do { try pauseSession.begin() }
            catch { return "Couldn't pause media: \(error.localizedDescription)" }
        }
        if ["Muffle", "Mute", "Lower"].contains(mode) {
            muffleQueue.async { [self] in
                if mode == "Muffle", !testAudio, #available(macOS 14.2, *) {
                    do {
                        let session = MuffleSession(); try session.start(); self.muffleSession = session
                        if CommandLine.arguments.contains("--ui-fixture") { UserDefaults.standard.set("active", forKey: "muffleTestStatus") }
                        return
                    } catch {
                        if CommandLine.arguments.contains("--ui-fixture") { UserDefaults.standard.set("fallback: \(error.localizedDescription)", forKey: "muffleTestStatus") }
                    }
                }
                if let device = Self.defaultDevice(scope: kAudioDevicePropertyScopeOutput), let volume = Self.volume(device, scope: kAudioDevicePropertyScopeOutput) {
                    self.output = device; self.previousVolume = volume; self.changedVolume = mode == "Mute" ? 0 : volume * 0.3
                    _ = Self.volume(device, scope: kAudioDevicePropertyScopeOutput, set: self.changedVolume)
                }
            }
        }
        return nil
    }
    func end() {
        muffleQueue.async { [self] in
            if #available(macOS 14.2, *), let session = self.muffleSession as? MuffleSession { session.stop() }
            self.muffleSession = nil
            if CommandLine.arguments.contains("--ui-fixture") { UserDefaults.standard.set("stopped", forKey: "muffleTestStatus") }
            if let previousVolume = self.previousVolume, let changedVolume = self.changedVolume, let current = Self.volume(self.output, scope: kAudioDevicePropertyScopeOutput), abs(current - changedVolume) < 0.01 { _ = Self.volume(self.output, scope: kAudioDevicePropertyScopeOutput, set: previousVolume) }
            self.previousVolume = nil; self.changedVolume = nil
        }
        pauseSession.end()
    }
    func waitForRestoration() async { await withCheckedContinuation { continuation in muffleQueue.async { continuation.resume() } } }
    static func cue(start: Bool) {
        guard (ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty else { return }
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: "soundEffects") ?? "Classic"
        guard style != "Off", let sound = NSSound(named: NSSound.Name(style == "Simple" ? "Tink" : (start ? "Glass" : "Pop"))) else { return }
        sound.volume = Float(defaults.object(forKey: "soundVolume") as? Double ?? 0.8); sound.play()
    }
}

@available(macOS 14.2, *)
private final class MuffleSession {
    private let processor = LowPassProcessor()
    private lazy var engine = SystemAudioTapEngine(processor: processor)
    func start() throws {
        guard let device = try AudioDevices.defaultOutput() else { throw NSError(domain: "LightTTS.Audio", code: 1) }
        try engine.start(outputUID: device.uid)
    }
    func stop() { engine.stop() }
}
@available(macOS 14.2, *)
private final class LowPassProcessor: AudioProcessor {
    private var filter = StereoLowPass()
    func prepare(sampleRate: Double) { filter.prepare(sampleRate: sampleRate) }
    func process(_ samples: UnsafeMutablePointer<Float>, frameCount: Int, channelCount: Int) { filter.process(samples, frameCount: frameCount, channelCount: channelCount) }
}

private struct SystemMediaController: MediaControlling {
    func pausePlaying() throws -> [String] { try ActivityGatedMediaController(isOutputRunning: outputIsRunning, toggle: sendMediaKey).pausePlaying() }
    func resume(_ players: [String]) { ActivityGatedMediaController(isOutputRunning: outputIsRunning, toggle: sendMediaKey).resume(players) }
    private func outputIsRunning() -> Bool {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr else { return false }
        property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &property, 0, nil, &size, &running) == noErr && running != 0
    }
    private func sendMediaKey() {
        for state in [0xA, 0xB] {
            let data = (Int(NX_KEYTYPE_PLAY) << 16) | (state << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
