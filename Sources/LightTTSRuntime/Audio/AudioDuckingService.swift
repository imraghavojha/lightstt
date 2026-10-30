import Foundation

/// The driver serializes its native operations and invalidates a pending resume on begin.
@MainActor
public protocol AudioDuckingDriver: AnyObject {
    func begin(options: DuckingOptions, completion: @escaping @Sendable (String?) -> Void)
    func end()
    func waitForRestoration() async
}

@MainActor
public final class AudioDuckingService: AudioDucking {
    private let driver: any AudioDuckingDriver
    private var latestGeneration: UInt64?
    private var activeSession: SessionID?

    public init(driver: any AudioDuckingDriver) {
        self.driver = driver
    }

    public func begin(
        session: SessionID, options: DuckingOptions,
        onWarning: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        if let latestGeneration, session.generation <= latestGeneration { return }
        if activeSession != nil { driver.end() }
        latestGeneration = session.generation
        activeSession = session
        driver.begin(options: options) { [weak self] warning in
            Task { @MainActor [weak self] in
                guard let self, self.activeSession == session else { return }
                onWarning(warning)
            }
        }
    }

    public func end(session: SessionID) {
        if let latestGeneration, session.generation < latestGeneration { return }
        if latestGeneration.map({ session.generation > $0 }) ?? true {
            latestGeneration = session.generation
            if activeSession != nil {
                activeSession = nil
                driver.end()
            }
            return
        }
        guard activeSession == session else { return }
        activeSession = nil
        driver.end()
    }

    public func waitForRestoration() async {
        await driver.waitForRestoration()
    }
}
