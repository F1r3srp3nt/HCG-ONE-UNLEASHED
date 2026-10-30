import AppKit
import HCGMarketSim

/// Owns the app's single simulation clock and saves the simulated session
/// before the app quits.
///
/// The host lives here rather than in `App` state so that
/// `applicationShouldTerminate` can reach it. It is created lazily, on the
/// main actor, the first time SwiftUI or AppKit asks for it (overriding
/// `NSObject.init()` with a main-actor initializer is not allowed in Swift 6).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var simulation: SimulationHost = {
        let speed = SimulationSpeed(rawValue: UserDefaults.standard.double(forKey: Preferences.defaultSpeed)) ?? .normal
        // The session (markets and simulated account) is stored in the app's
        // sandbox container: ~/Library/Containers/<bundle id>/Data/Library/Application Support.
        let persistence = SessionPersistence(directory: SessionPersistence.applicationSupportDirectory())
        return SimulationHost(speed: speed, persistence: persistence)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.object(forKey: Preferences.startSimulationOnLaunch) as? Bool ?? true {
            simulation.play()
        }
    }

    /// Defers quitting until the session is written. Saving is a single local
    /// file write, so this does not noticeably delay quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await simulation.pauseAndWait()
            await simulation.saveNow()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
