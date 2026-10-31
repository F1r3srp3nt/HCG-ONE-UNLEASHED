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

            RiskRulesView(status: frame.riskStatus, equity: frame.equity)

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

/// The account's risk rules: daily loss limit, trailing drawdown and any lock.
private struct RiskRulesView: View {
    let status: RiskStatus
    let equity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Risk rules")
            if let lock = status.lock {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Trading locked: \(lock.title)", systemImage: "lock.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(HCGColor.loss)
                    Text("\(lock.message) \(lock.unlockText)")
                        .font(.caption)
                        .foregroundStyle(HCGColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HCGColor.loss.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if let limit = status.dailyLossLimit {
                meter("Session P&L", value: TradingFormat.money(status.sessionPnL, signed: true),
                      detail: "limit \(TradingFormat.money(-limit))",
                      used: max(0, -status.sessionPnL) / limit, tone: HCGColor.tone(for: status.sessionPnL))
            }
            if let floor = status.drawdownFloor {
                let room = max(0, equity - floor)
                meter("Drawdown room", value: TradingFormat.money(room),
                      detail: "floor \(TradingFormat.money(floor)) · high \(TradingFormat.money(status.peakEquity))",
                      used: 1 - min(1, room / max(1, status.peakEquity - floor)), tone: HCGColor.textPrimary)
            }
            if status.dailyLossLimit == nil && status.drawdownFloor == nil {
                Text("No loss limits are set (Settings → Account).")
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
            }
        }
    }

    /// One rule: value, detail, and how much of the allowance is used.
    private func meter(_ title: String, value: String, detail: String, used: Double, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption).foregroundStyle(HCGColor.textSecondary)
                Spacer(minLength: 6)
                Text(value).font(HCGFont.value(12)).foregroundStyle(tone).monospacedDigit()
            }
            ProgressView(value: min(1, max(0, used)))
                .tint(used >= 0.8 ? HCGColor.loss : (used >= 0.5 ? HCGColor.warning : HCGColor.accent))
                .accessibilityLabel("\(title): \(Int((min(1, max(0, used)) * 100).rounded())) percent of the allowance used")
            Text(detail).font(.caption2).foregroundStyle(HCGColor.textSecondary)
        }
    }
}
