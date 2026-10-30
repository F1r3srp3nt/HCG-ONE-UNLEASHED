import HCGMarketSim
import SwiftUI

/// HCG ONE UNLEASHED — native macOS application entry point.
///
/// M1 development build: no sign-in, no network access, simulated market data only.
@main
struct HCGOneUnleashedApp: App {
    /// The single simulation clock shared by every window and panel.
    @State private var simulation: SimulationHost

    init() {
        let defaults = UserDefaults.standard
        let speed = SimulationSpeed(rawValue: defaults.double(forKey: Preferences.defaultSpeed)) ?? .normal
        let host = SimulationHost(speed: speed)
        if defaults.object(forKey: Preferences.startSimulationOnLaunch) as? Bool ?? true {
            host.play()
        }
        _simulation = State(initialValue: host)
    }

    var body: some Scene {
        WindowGroup("HCG ONE UNLEASHED", id: "main") {
            MainWindow()
                .environment(simulation)
        }
        .defaultSize(width: 1320, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(simulation: simulation)
        }

        Settings {
            SettingsView()
                .environment(simulation)
        }
    }
}
