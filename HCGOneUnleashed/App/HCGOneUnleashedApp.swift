import HCGMarketSim
import SwiftUI

/// HCG ONE: UNLEASHED — native macOS application entry point.
///
/// Development build: no sign-in, no network access, simulated market data
/// and a simulated trading account only.
@main
struct HCGOneUnleashedApp: App {
    /// Owns the single simulation clock shared by every window and panel.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("HCG ONE: UNLEASHED", id: "main") {
            MainWindow()
                .environment(appDelegate.simulation)
        }
        .defaultSize(width: 1320, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(simulation: appDelegate.simulation)
        }

        Settings {
            SettingsView()
                .environment(appDelegate.simulation)
        }
    }
}
