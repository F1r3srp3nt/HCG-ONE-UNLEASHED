import HCGAppModel
import HCGDomain
import HCGMarketSim
import SwiftUI

/// Native menu commands: Go (⌘1…⌘6) and Simulation.
struct AppCommands: Commands {
    let simulation: SimulationHost
    @FocusedValue(\.navigation) private var navigation

    var body: some Commands {
        SidebarCommands()

        // The app has nothing to print. Removing the default Page Setup… (⇧⌘P)
        // and Print… items also frees ⇧⌘P for Play/Pause Simulation.
        CommandGroup(replacing: .printItem) {}

        CommandMenu("Go") {
            ForEach(PrimaryArea.allCases) { area in
                Button(area.title) { navigation?.open(area) }
                    .keyboardShortcut(area.shortcut, modifiers: .command)
                    .disabled(navigation == nil)
            }
        }

        CommandMenu("Simulation") {
            Button(simulation.isPlaying ? "Pause Simulation" : "Play Simulation") {
                simulation.togglePlayback()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Step One Update") {
                Task { await simulation.step() }
            }
            .keyboardShortcut(".", modifiers: [.command, .option])
            .disabled(simulation.isPlaying)

            Divider()

            Button("Faster") { simulation.faster() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(simulation.speed.faster == nil)
            Button("Slower") { simulation.slower() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(simulation.speed.slower == nil)

            Picker("Speed", selection: Binding(
                get: { simulation.speed },
                set: { simulation.setSpeed($0) }
            )) {
                ForEach(SimulationSpeed.allCases) { speed in
                    Text(speed.label).tag(speed)
                }
            }

            Divider()

            Menu("Market") {
                ForEach(MarketSymbol.allCases) { symbol in
                    Button("\(symbol.ticker) — \(symbol.spec.name)") {
                        navigation?.showOrderFlow(symbol)
                    }
                    .keyboardShortcut(Self.shortcut(for: symbol), modifiers: [.command, .option])
                    .disabled(navigation == nil)
                }
            }

            Divider()

            Button("Reset Simulated Session") {
                Task { await simulation.reset() }
            }
        }
    }

    /// ⌥⌘1…⌥⌘4 in workstation order (GC, NQ, ES, CL).
    private static func shortcut(for symbol: MarketSymbol) -> KeyEquivalent {
        let position = (MarketSymbol.allCases.firstIndex(of: symbol) ?? 0) + 1
        return KeyEquivalent(Character(String(position)))
    }
}
