import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// Quick simulated ticket: market orders against the simulated book, plus
/// the position and P&L of the simulated account. Limit, stop and bracket
/// orders are on the Simulate screen. Nothing leaves this Mac.
///
/// One row on wide windows, two rows (controls, then account figures) when
/// narrower; a single fixed row clipped at smaller widths (docs/M1_AUDIT.md, OF-2).
struct SimulatedTicketBar: View {
    let snapshot: MarketSnapshot
    let account: TradingAccount
    let unrealizedPnL: Double
    let equity: Double
    let message: String?

    @Environment(SimulationHost.self) private var simulation
    @State private var quantity = 1

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                controls
                Divider().frame(height: 30)
                figures
                Spacer(minLength: 8)
                messageText
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    controls
                    Spacer(minLength: 8)
                }
                HStack(spacing: 18) {
                    figures
                    Spacer(minLength: 8)
                    messageText
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HCGColor.surface)
    }

    private var controls: some View {
        let position = account.position(snapshot.symbol)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Simulated ticket")
                Text("Market orders · no real orders")
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    .fixedSize()
            }

            Stepper(value: $quantity, in: 1...max(1, account.configuration.risk.maxOrderQuantity)) {
                Text("Qty \(quantity)").font(HCGFont.value(12)).frame(minWidth: 46, alignment: .leading)
            }
            .fixedSize()

            Button("Buy") { submit(.buy) }
                .buttonStyle(HCGButtonStyle(.secondary))
                .help("Simulated market buy of \(quantity) \(snapshot.symbol.ticker) at the ask")
            Button("Sell") { submit(.sell) }
                .buttonStyle(HCGButtonStyle(.secondary))
                .help("Simulated market sell of \(quantity) \(snapshot.symbol.ticker) at the bid")
            Button("Flatten") { Task { await simulation.flatten(snapshot.symbol) } }
                .buttonStyle(HCGButtonStyle(.quiet))
                .disabled(position == nil)
                .help("Close the simulated \(snapshot.symbol.ticker) position")
        }
    }

    private var figures: some View {
        let currency = snapshot.spec.currency
        let unrealized = unrealizedPnL
        return HStack(spacing: 14) {
            TradingStat("Position", value: positionText(account.position(snapshot.symbol)), size: 13)
            TradingStat("Unrealized", value: PriceFormat.money(unrealized, currency: currency, signed: true),
                        color: HCGColor.tone(for: unrealized), size: 13)
            TradingStat("Realized (all)", value: PriceFormat.money(account.realizedPnL, currency: currency, signed: true),
                        color: HCGColor.tone(for: account.realizedPnL), size: 13)
            TradingStat("Equity", value: PriceFormat.money(equity, currency: currency), size: 13)
        }
    }

    @ViewBuilder
    private var messageText: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(HCGColor.textSecondary)
                .lineLimit(2)
                .frame(minWidth: 80, maxWidth: 240, alignment: .trailing)
                .help(message)
        }
    }

    private func submit(_ side: OrderSide) {
        let request = OrderRequest.market(side, quantity, snapshot.symbol)
        Task { await simulation.submit(request) }
    }

    private func positionText(_ position: Position?) -> String {
        guard let position else { return "Flat" }
        let side = position.isLong ? "Long" : "Short"
        let price = TradingFormat.averagePrice(position.averagePrice, snapshot.spec)
        return "\(side) \(abs(position.quantity)) @ \(price)"
    }
}
