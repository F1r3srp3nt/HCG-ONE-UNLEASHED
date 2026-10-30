import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import SwiftUI

/// Basic simulated ticket: market orders against the simulated book, plus
/// the position and P&L of the simulated account. Nothing leaves this Mac.
struct SimulatedTicketBar: View {
    let snapshot: MarketSnapshot
    let account: SimulatedAccount
    let message: String?

    @Environment(SimulationHost.self) private var simulation
    @State private var quantity = 1

    var body: some View {
        let position = account.position(snapshot.symbol)
        let currency = snapshot.spec.currency
        let unrealized = account.unrealizedPnL(snapshot)

        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Simulated ticket")
                Text("Market orders · no real orders")
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
            }

            Stepper(value: $quantity, in: 1...MarketOrder.maximumQuantity) {
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

            Divider().frame(height: 30)

            TradingStat("Position", value: positionText(position), size: 13)
            TradingStat("Unrealized", value: PriceFormat.money(unrealized, currency: currency, signed: true),
                        color: HCGColor.tone(for: unrealized), size: 13)
            TradingStat("Realized", value: PriceFormat.money(account.realizedPnL, currency: currency, signed: true),
                        color: HCGColor.tone(for: account.realizedPnL), size: 13)
            TradingStat("Equity", value: PriceFormat.money(account.equity(simulation.frame.markets), currency: currency), size: 13)

            Spacer(minLength: 8)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
                    .help(message)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(HCGColor.surface)
    }

    private func submit(_ side: OrderSide) {
        let order = MarketOrder(symbol: snapshot.symbol, side: side, quantity: quantity)
        Task { await simulation.submit(order) }
    }

    private func positionText(_ position: Position?) -> String {
        guard let position else { return "Flat" }
        let side = position.isLong ? "Long" : "Short"
        let price = PriceFormat.price(position.averagePrice, decimals: snapshot.spec.priceDecimals + 1)
        return "\(side) \(abs(position.quantity)) @ \(price)"
    }
}
