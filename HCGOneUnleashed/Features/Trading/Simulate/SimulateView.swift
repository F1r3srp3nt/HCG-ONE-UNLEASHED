import HCGAppModel
import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// Trading → Simulate: the simulated order ticket, account and blotter.
///
/// Every order here is simulated against the app's simulated markets. Nothing
/// is sent to an exchange, broker or HCG service.
///
/// Like Order Flow, this view owns the toolbar and does not read the frame;
/// only the quote strip, ticket preview, account summary and positions table
/// do, so working-order and history tables re-render only when the account
/// changes.
struct SimulateView: View {
    @Environment(SimulationHost.self) private var simulation
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        let symbol = navigation.orderFlowSymbol

        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    QuoteStrip(symbol: symbol)
                    OrderTicketView(symbol: symbol)
                    AccountSummaryView()
                }
                .padding(16)
            }
            .frame(minWidth: 330, idealWidth: 360, maxWidth: 440, maxHeight: .infinity)

            AccountTablesView(selectedSymbol: symbol)
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(HCGColor.canvas)
        .toolbar { toolbarItems(symbol: $navigation.orderFlowSymbol) }
        .navigationTitle("Simulate")
        .navigationSubtitle("Simulated account · no real orders")
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
            .help(simulation.isPlaying ? "Pause the simulation (⇧⌘P)" : "Play the simulation (⇧⌘P)")

            Button {
                Task { await simulation.step() }
            } label: {
                Label("Step", systemImage: "forward.frame")
            }
            .disabled(simulation.isPlaying)
            .help("Advance one simulated update (⌥⌘.)")
        }
    }
}

/// Bid, ask, last and simulated time for the selected market.
private struct QuoteStrip: View {
    let symbol: MarketSymbol
    @Environment(SimulationHost.self) private var simulation

    var body: some View {
        let frame = simulation.frame
        let snapshot = frame[symbol]
        let spec = snapshot.spec
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(symbol.ticker)
                    .font(.system(size: 15, weight: .semibold))
                Text(spec.name)
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                SimulatedDataBadge()
            }
            HStack(spacing: 16) {
                TradingStat("Bid", value: PriceFormat.price(snapshot.bid, decimals: spec.priceDecimals),
                            color: HCGColor.bid, size: 15)
                TradingStat("Ask", value: PriceFormat.price(snapshot.ask, decimals: spec.priceDecimals),
                            color: HCGColor.ask, size: 15)
                TradingStat("Last", value: PriceFormat.price(snapshot.last, decimals: spec.priceDecimals), size: 15)
                Spacer(minLength: 0)
            }
            Text("Simulated time \(TradingFormat.time(frame.time)) UTC · tick \(PriceFormat.price(spec.tickSize, decimals: spec.priceDecimals)) = \(TradingFormat.money(spec.tickValue))")
                .font(.caption)
                .foregroundStyle(HCGColor.textSecondary)
        }
        .hcgPanel()
    }
}
