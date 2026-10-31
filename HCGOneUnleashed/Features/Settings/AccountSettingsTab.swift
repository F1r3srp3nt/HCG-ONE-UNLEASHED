import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// Settings → Account: simulated costs, margins, slippage and risk limits.
///
/// Edits are kept in a draft and applied together, so a half-typed value
/// never reaches the engine. Every figure here is simulated.
struct AccountSettingsTab: View {
    @Environment(SimulationHost.self) private var simulation
    @State private var draft = AccountConfiguration.standard
    @State private var errors: [String] = []
    @State private var confirmReset = false
    @State private var applied = false

    var body: some View {
        let current = simulation.account.configuration
        Form {
            Section {
                TextField("Starting balance (USD)", value: $draft.startingBalance,
                          format: .number.precision(.fractionLength(0...2)))
                Stepper("Slippage: \(PriceFormat.ticks(draft.slippageTicks)) on market and stop fills",
                        value: $draft.slippageTicks, in: 0...20)
            } header: {
                Text("Account")
            } footer: {
                Text("The starting balance applies when the simulated account is reset. Current starting balance: \(TradingFormat.money(simulation.account.startingBalance)).")
                    .foregroundStyle(HCGColor.textSecondary)
            }

            Section {
                Stepper("Maximum order size: \(draft.risk.maxOrderQuantity) contracts",
                        value: $draft.risk.maxOrderQuantity, in: 1...1_000)
                Stepper("Maximum position per market: \(draft.risk.maxPositionPerSymbol) contracts",
                        value: $draft.risk.maxPositionPerSymbol, in: 1...1_000)
                Toggle("Reject orders that need more margin than the account's equity", isOn: $draft.risk.enforceBuyingPower)
                optionalAmount("Daily loss limit", value: $draft.risk.dailyLossLimit, fallback: 1_000)
                optionalAmount("Trailing drawdown", value: $draft.risk.trailingDrawdown, fallback: 2_000)
                Toggle("Liquidate positions when equity falls below their margin", isOn: $draft.risk.liquidateOnMarginShortfall)
                Button("Use Evaluation Account Rules") { draft.risk = .evaluation }
            } header: {
                Text("Risk rules")
            } footer: {
                Text("The daily loss limit counts realized and unrealized P&L since the session began (22:00 UTC); reaching it closes everything and locks trading until the next session. The trailing drawdown follows the equity high and stops trailing at the starting balance; reaching it locks trading until the account is reset. The defaults model a $50,000 evaluation-style account.")
                    .foregroundStyle(HCGColor.textSecondary)
            }

            Section {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Market").gridColumnAlignment(.leading)
                        Text("Commission")
                        Text("Fees")
                        Text("Margin")
                    }
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    ForEach(MarketSymbol.allCases) { symbol in
                        GridRow {
                            Text(symbol.ticker).fontWeight(.semibold).gridColumnAlignment(.leading)
                            costField(symbol, \.commissionPerContract)
                            costField(symbol, \.feesPerContract)
                            costField(symbol, \.initialMarginPerContract)
                        }
                    }
                }
            } header: {
                Text("Per-contract costs (USD)")
            } footer: {
                Text("Commission and fees are charged on every simulated fill. Margin is held for open positions and working entry orders. These are simulated values, not exchange or broker figures.")
                    .foregroundStyle(HCGColor.textSecondary)
            }

            if !errors.isEmpty {
                Section {
                    ForEach(errors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(HCGColor.loss)
                    }
                }
            }

            Section {
                HStack {
                    Button("Revert") {
                        draft = current
                        errors = []
                    }
                    .disabled(draft == current)
                    Button("Restore Defaults") { draft = .standard }
                    Spacer()
                    if applied && draft == current {
                        Text("Applied").font(.caption).foregroundStyle(HCGColor.textSecondary)
                    }
                    Button("Apply") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft == current)
                }
                Button("Reset Account with These Settings…") { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear {
            draft = current
            applied = false
        }
        .confirmationDialog(Confirmation.resetAccountTitle, isPresented: $confirmReset) {
            Button("Reset Account", role: .destructive) { resetWithDraft() }
        } message: {
            Text(Confirmation.resetAccountMessage)
        }
    }

    /// A toggle plus a USD amount for a rule that can be switched off.
    private func optionalAmount(_ title: String, value: Binding<Double?>, fallback: Double) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? (value.wrappedValue ?? fallback) : nil }
            ))
            Spacer()
            TextField(title, value: Binding(
                get: { value.wrappedValue ?? fallback },
                set: { value.wrappedValue = $0 }
            ), format: .number.precision(.fractionLength(0...2)))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
            .disabled(value.wrappedValue == nil)
        }
    }

    private func costField(_ symbol: MarketSymbol, _ keyPath: WritableKeyPath<InstrumentCosts, Double>) -> some View {
        TextField(symbol.ticker, value: Binding(
            get: { draft.costs(for: symbol)[keyPath: keyPath] },
            set: { value in
                var costs = draft.costs(for: symbol)
                costs[keyPath: keyPath] = value
                draft.costs[symbol] = costs
            }
        ), format: .number.precision(.fractionLength(0...2)))
        .labelsHidden()
        .multilineTextAlignment(.trailing)
        .frame(width: 90)
    }

    private func apply() {
        Task {
            errors = await simulation.updateConfiguration(draft)
            applied = errors.isEmpty
        }
    }

    private func resetWithDraft() {
        let problems = draft.validationErrors()
        guard problems.isEmpty else {
            errors = problems
            return
        }
        let configuration = draft
        Task {
            await simulation.resetAccount(configuration: configuration)
            errors = []
            applied = true
        }
    }
}
