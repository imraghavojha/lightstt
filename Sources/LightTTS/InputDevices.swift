import AVFoundation
import AudioToolbox
import CoreAudio

struct InputDevice: Identifiable {
    let id: String
    let name: String
    static var available: [InputDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
    static func applySelection(to engine: AVAudioEngine) throws {
        guard let uid = UserDefaults.standard.string(forKey: "inputDeviceUID"), !uid.isEmpty else { return }
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
