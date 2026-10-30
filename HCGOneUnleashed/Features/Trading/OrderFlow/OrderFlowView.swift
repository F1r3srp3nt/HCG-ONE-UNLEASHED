import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import SwiftUI

/// Trading → Order Flow: the first working workstation screen.
///
/// Chart, DOM, header and ticket all render from the same `MarketSnapshot`
/// of the same simulation frame, read once per update in `body`.
struct OrderFlowView: View {
    @Environment(SimulationHost.self) private var simulation
    @Environment(NavigationModel.self) private var navigation
    @AppStorage(Preferences.ladderLevels) private var ladderLevels = 12

    var body: some View {
        @Bindable var navigation = navigation
        let snapshot = simulation.frame[navigation.orderFlowSymbol]

        VStack(spacing: 0) {
            MarketHeaderBar(snapshot: snapshot, isPlaying: simulation.isPlaying, speed: simulation.speed)
            Divider()
            HSplitView {
                PriceChartPanel(series: PriceSeries(snapshot: snapshot), spec: snapshot.spec)
                    .frame(minWidth: 380, idealWidth: 720, maxWidth: .infinity, maxHeight: .infinity)
                DepthLadderPanel(snapshot: snapshot, maxLevelsPerSide: ladderLevels)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 520, maxHeight: .infinity)
            }
            Divider()
            SimulatedTicketBar(snapshot: snapshot, account: simulation.frame.account,
                               message: simulation.lastOrderMessage)
        }
        .background(HCGColor.canvas)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            simulation.togglePlayback()
            return .handled
        }
        .toolbar { toolbarItems(symbol: $navigation.orderFlowSymbol) }
        .navigationTitle("Order Flow")
        .navigationSubtitle("\(snapshot.symbol.ticker) · \(snapshot.spec.name) · Simulated")
    }

    @ToolbarContentBuilder
    private func toolbarItems(symbol: Binding<MarketSymbol>) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Market", selection: symbol) {
                ForEach(MarketSymbol.allCases) { market in
                    Text(market.ticker).tag(market)
                }
            }
            .pickerStyle(.segmented)
            .help("Simulated market (⌥⌘1–⌥⌘4)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                simulation.togglePlayback()
            } label: {
                Label(simulation.isPlaying ? "Pause" : "Play",
                      systemImage: simulation.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(simulation.isPlaying ? "Pause the simulation (⇧⌘P or Space)" : "Play the simulation (⇧⌘P or Space)")

            Button {
                Task { await simulation.step() }
            } label: {
                Label("Step", systemImage: "forward.frame")
            }
            .disabled(simulation.isPlaying)
            .help("Advance one simulated update (⌥⌘.)")

            Picker("Speed", selection: Binding(
                get: { simulation.speed },
                set: { simulation.setSpeed($0) }
            )) {
                ForEach(SimulationSpeed.allCases) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .pickerStyle(.menu)
            .help("Simulation speed (⌘[ and ⌘])")
        }
    }
}
