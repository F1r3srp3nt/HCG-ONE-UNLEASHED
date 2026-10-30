import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// Sets the stop loss and take profit on an open simulated position.
struct ProtectionSheet: View {
    let symbol: MarketSymbol
    @Environment(SimulationHost.self) private var simulation
    @Environment(\.dismiss) private var dismiss

    @State private var useStopLoss = true
    // Text-backed for the same reason as the order ticket: Return applies
    // what is on screen, even before the field commits.
    @State private var stopLossText = ""
    @State private var useTakeProfit = true
    @State private var takeProfitText = ""
    @State private var problem: String?
    @State private var isApplying = false

    var body: some View {
        let spec = symbol.spec
        let position = simulation.account.position(symbol)

        VStack(alignment: .leading, spacing: 14) {
            Text("Protect simulated \(symbol.ticker) position")
                .font(.headline)

            if let position {
                Text("\(TradingFormat.positionSide(position)) \(abs(position.quantity)) @ \(TradingFormat.averagePrice(position.averagePrice, spec))")
                    .font(HCGFont.value(13))
                priceRow("Stop loss", isOn: $useStopLoss, text: $stopLossText)
                priceRow("Take profit", isOn: $useTakeProfit, text: $takeProfitText)
                Text("Both orders are reduce-only and cancel each other when one fills. They replace any stop loss or take profit already working on this position, including bracket orders. If either price is invalid, nothing changes.")
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !useStopLoss && !useTakeProfit {
                    Text("With both off, the existing protection is removed.")
                        .font(.caption)
                        .foregroundStyle(HCGColor.warning)
                }
            } else {
                Text("There is no open simulated \(symbol.ticker) position.")
                    .foregroundStyle(HCGColor.textSecondary)
            }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(HCGColor.loss)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(position == nil || isApplying
                              || (useStopLoss && stopLoss == nil) || (useTakeProfit && takeProfit == nil))
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear(perform: prefill)
    }

    private var stopLoss: Double? { TradingFormat.parsePrice(stopLossText) }
    private var takeProfit: Double? { TradingFormat.parsePrice(takeProfitText) }

    private func priceRow(_ title: String, isOn: Binding<Bool>, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Toggle(title, isOn: isOn)
                .frame(width: 120, alignment: .leading)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .labelsHidden()
                .disabled(!isOn.wrappedValue)
        }
    }

    /// Existing protection if there is any, otherwise 20 ticks beyond the market.
    private func prefill() {
        let account = simulation.account
        let snapshot = simulation.frame[symbol]
        let spec = symbol.spec
        guard let position = account.position(symbol) else { return }
        let working = account.openOrders(for: symbol).filter { $0.status != .accepted }
        let existingStop = working.first { $0.role == .stopLoss }?.stopPrice(spec)
        let existingTarget = working.first { $0.role == .takeProfit }?.limitPrice(spec)
        let stop: Double
        let target: Double
        if position.isLong {
            stop = existingStop ?? spec.price(ticks: snapshot.bidTicks - 20)
            target = existingTarget ?? spec.price(ticks: snapshot.bidTicks + 20)
        } else {
            stop = existingStop ?? spec.price(ticks: snapshot.askTicks + 20)
            target = existingTarget ?? spec.price(ticks: snapshot.askTicks - 20)
        }
        stopLossText = TradingFormat.priceText(stop, spec)
        takeProfitText = TradingFormat.priceText(target, spec)
    }

    private func apply() {
        let spec = symbol.spec
        let stop = useStopLoss ? stopLoss.map { TradingFormat.snapped($0, spec) } : nil
        let target = useTakeProfit ? takeProfit.map { TradingFormat.snapped($0, spec) } : nil
        isApplying = true
        Task {
            let results = await simulation.setProtection(symbol, stopLoss: stop, takeProfit: target)
            isApplying = false
            let reasons = results.filter { !$0.isAccepted }.compactMap(\.order.statusReason)
            if reasons.isEmpty {
                dismiss()
            } else {
                problem = reasons.joined(separator: " ")
            }
        }
    }
}
