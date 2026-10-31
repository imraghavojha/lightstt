import AVFoundation
import AudioToolbox
import CoreAudio

struct InputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    /// Physical and user-facing virtual inputs, without the private aggregate devices
    /// Core Audio creates for voice processing or default-device routing.
    static var available: [InputDevice] {
        var seen = Set<String>()
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.compactMap { device in
            guard !isHiddenSystemDevice(uid: device.uniqueID, name: device.localizedName), seen.insert(device.uniqueID).inserted else { return nil }
            return InputDevice(id: device.uniqueID, name: device.localizedName)
        }
    }
    static func isHiddenSystemDevice(uid: String, name: String) -> Bool {
        let prefixes = ["CADefaultDeviceAggregate", "VPAUAggregateAudioDevice", "CAVoiceProcessing"]
        return prefixes.contains { uid.hasPrefix($0) || name.hasPrefix($0) }
    }
    /// The current system default input, used to label the "follow default" choice.
    static var systemDefault: InputDevice? {
        guard let device = AVCaptureDevice.default(for: .audio), !isHiddenSystemDevice(uid: device.uniqueID, name: device.localizedName) else { return nil }
        return InputDevice(id: device.uniqueID, name: device.localizedName)
    }
    /// One entry per microphone: the system default appears once, as the "follow default"
    /// choice (empty ID), followed by every other input.
    static func choices(available: [InputDevice], systemDefault: InputDevice?) -> [InputDevice] {
        let followDefault = InputDevice(id: "", name: systemDefault?.name ?? "System Default")
        return [followDefault] + available.filter { $0.id != systemDefault?.id }
    }
    static func applySelection(to engine: AVAudioEngine, deviceUID: String? = nil) throws {
        guard let uid = deviceUID ?? UserDefaults.standard.string(forKey: "inputDeviceUID"), !uid.isEmpty else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = uid as CFString
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let result = withUnsafePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        guard result == noErr, device != kAudioObjectUnknown, let unit = engine.inputNode.audioUnit else {
            throw NSError(domain: "LightTTS", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "The selected microphone is unavailable."])
        }
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not select the microphone."]) }
    }
}
