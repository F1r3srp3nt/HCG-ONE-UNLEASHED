import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import SwiftUI

/// The native Settings window (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            SimulationSettingsTab()
                .tabItem { Label("Simulation", systemImage: "waveform.path.ecg") }
            AccountSettingsTab()
                .tabItem { Label("Account", systemImage: "banknote") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580)
    }
}

private struct SimulationSettingsTab: View {
    @Environment(SimulationHost.self) private var simulation
    @AppStorage(Preferences.defaultSpeed) private var defaultSpeed = SimulationSpeed.normal.rawValue
    @AppStorage(Preferences.startSimulationOnLaunch) private var startOnLaunch = true
    @AppStorage(Preferences.ladderLevels) private var ladderLevels = 12
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Picker("Default speed", selection: $defaultSpeed) {
                    ForEach(SimulationSpeed.allCases) { speed in
                        Text(speed.label).tag(speed.rawValue)
                    }
                }
                Toggle("Start the simulation when HCG ONE: UNLEASHED opens", isOn: $startOnLaunch)
                Stepper("Depth of market: up to \(ladderLevels) levels per side", value: $ladderLevels, in: 6...20)
            } footer: {
                Text("Speed and start-up settings apply the next time the app opens. All market data is simulated on this Mac.")
                    .foregroundStyle(HCGColor.textSecondary)
            }

            Section {
                Button("Reset Simulated Session…") { confirmReset = true }
                    .confirmationDialog(Confirmation.resetSessionTitle, isPresented: $confirmReset) {
                        Button("Reset Session", role: .destructive) {
                            Task { await simulation.reset() }
                        }
                    } message: {
                        Text(Confirmation.resetSessionMessage)
                    }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BrandMark(size: 40)
                BrandWordmark(size: 24)
            }
            Text(HCGEcosystem.companyName)
                .foregroundStyle(HCGColor.textSecondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow { label("Version"); value(AppInfo.versionDescription) }
                GridRow { label("Build"); value(AppInfo.developmentStage) }
                GridRow { label("Market data"); value("Simulated only. No exchange, broker or live feed.") }
                GridRow { label("Trading"); value("Simulated account only. No order ever leaves this Mac.") }
                GridRow { label("Network"); value("None. This build makes no network connections.") }
                GridRow { label("Account"); value("No sign-in in this build.") }
                GridRow { label("Bundle ID"); value(AppInfo.bundleIdentifier) }
            }
            .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(HCGColor.textSecondary)
    }

    private func value(_ text: String) -> some View {
        Text(text).foregroundStyle(HCGColor.textPrimary).textSelection(.enabled)
    }
}

/// Account → Settings inside the main window: points to the Settings window.
struct SettingsPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(HCGColor.textSecondary)
                .accessibilityHidden(true)
            Text("Settings")
                .font(HCGFont.screenTitle)
            Text("Simulation preferences, simulated account costs and limits, and build information live in the Settings window.")
                .font(.callout)
                .foregroundStyle(HCGColor.textSecondary)
            SettingsLink {
                Text("Open Settings…")
            }
            .buttonStyle(HCGButtonStyle(.primary))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
    }
}
