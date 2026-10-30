import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// Simulated account values, marked to the current simulated market.
struct AccountSummaryView: View {
    @Environment(SimulationHost.self) private var simulation
    @State private var confirmReset = false

    var body: some View {
        let frame = simulation.frame
        let account = frame.account
        let unrealized = frame.unrealizedPnL
        let buyingPower = frame.buyingPower

        VStack(alignment: .leading, spacing: 12) {
            PanelHeader("Simulated account", detail: TradingFormat.accountCurrency)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    TradingStat("Equity", value: TradingFormat.money(frame.equity), size: 14)
                    TradingStat("Buying power", value: TradingFormat.money(buyingPower),
                                color: buyingPower < 0 ? HCGColor.loss : HCGColor.textPrimary, size: 14)
                }
                GridRow {
                    TradingStat("Balance", value: TradingFormat.money(account.cash), size: 14)
                    TradingStat("Margin in use", value: TradingFormat.money(account.marginRequirement()), size: 14)
                }
                GridRow {
                    TradingStat("Unrealized P&L", value: TradingFormat.money(unrealized, signed: true),
                                color: HCGColor.tone(for: unrealized), size: 14)
                    TradingStat("Realized P&L", value: TradingFormat.money(account.realizedPnL, signed: true),
                                color: HCGColor.tone(for: account.realizedPnL), size: 14)
                }
                GridRow {
                    TradingStat("Commissions + fees", value: TradingFormat.money(account.commissionsPaid + account.feesPaid), size: 14)
                    TradingStat("Starting balance", value: TradingFormat.money(account.startingBalance), size: 14)
                }
            }

            HStack(spacing: 8) {
                Button("Flatten All") { Task { await simulation.flattenAll() } }
                    .buttonStyle(HCGButtonStyle(.secondary))
                    .disabled(account.positions.isEmpty && account.openOrders.isEmpty)
                    .help("Cancel every simulated order and close every simulated position at market (⌥⇧⌘F)")
                Spacer(minLength: 8)
                Button("Reset Account…") { confirmReset = true }
                    .buttonStyle(HCGButtonStyle(.quiet))
            }

            Text("Balance is the starting balance plus realized P&L, less commissions and fees. Equity adds unrealized P&L (longs marked at the bid, shorts at the ask). Margins and costs are simulated and set in Settings → Account; they are not exchange or broker figures.")
                .font(.caption)
                .foregroundStyle(HCGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hcgPanel()
        .confirmationDialog(Confirmation.resetAccountTitle, isPresented: $confirmReset) {
            Button("Reset Account", role: .destructive) {
                Task { await simulation.resetAccount() }
            }
        } message: {
            Text(Confirmation.resetAccountMessage)
        }
    }
}
