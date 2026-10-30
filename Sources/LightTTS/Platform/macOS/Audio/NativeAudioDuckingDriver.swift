import LightTTSRuntime

/// Adapts the existing audio queues, media gate and volume restoration to the runtime service.
@MainActor
final class NativeAudioDuckingDriver: AudioDuckingDriver {
    private let settings: AudioSettings

    init(settings: AudioSettings = AudioSettings()) {
        self.settings = settings
    }

    func begin(options: DuckingOptions, completion: @escaping @Sendable (String?) -> Void) {
        settings.begin(options: options, completion: completion)
    }

    func end() {
        settings.end()
    }

    func waitForRestoration() async {
        await settings.waitForRestoration()
    }
}
