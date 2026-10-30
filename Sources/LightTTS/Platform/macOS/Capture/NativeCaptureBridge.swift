import LightTTSRuntime

@MainActor
final class NativeCaptureDriverFactory: CaptureDriverFactory {
    func makeDriver() -> any CaptureDriver {
        NativeCaptureDriver()
    }
}

@MainActor
private final class NativeCaptureDriver: CaptureDriver {
    private var capture: AudioCapture?

    func start(deviceUID: String, onLevel: @escaping @Sendable (Float) -> Void) throws {
        let capture = AudioCapture(onLevel: onLevel)
        try capture.start(deviceUID: deviceUID)
        self.capture = capture
    }

    func stop() -> PCM16k {
        PCM16k(samples: capture?.stop() ?? [])
    }
}

@MainActor
final class NativeInputDevicesProvider: InputDevicesProviding {
    func devices() async -> [InputDeviceDescriptor] {
        InputDevice.available.map { InputDeviceDescriptor(id: $0.id, name: $0.name) }
    }
}
