import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// Simulated order ticket: market, limit and stop orders, with an optional
/// take-profit / stop-loss bracket. The engine validates every order; the
/// preview below the form only explains what will happen.
struct OrderTicketView: View {
    let symbol: MarketSymbol
    @Environment(SimulationHost.self) private var simulation

    @State private var side: OrderSide = .buy
    @State private var type: OrderType = .market
    // Text-backed so the preview and the submitted order always use what is
    // on screen: a value-bound field only updates when it commits, so ⌘↩
    // right after typing would otherwise send the previous price.
    @State private var quantityText = "1"
    @State private var priceText = ""
    @State private var attachBracket = false
    @State private var useTakeProfit = true
    @State private var takeProfitTicks = 20
    @State private var useStopLoss = true
    @State private var stopLossTicks = 20
    @State private var isSubmitting = false
    @State private var outcome: Outcome?

    private struct Outcome: Equatable {
        let message: String
        let rejected: Bool
    }

    var body: some View {
        let spec = symbol.spec
        let maxQuantity = max(1, simulation.account.configuration.risk.maxOrderQuantity)

        VStack(alignment: .leading, spacing: 12) {
            PanelHeader("Order ticket") {
                StatusBadge("Simulated", tone: .warning)
            }

            Picker("Side", selection: $side) {
                ForEach(OrderSide.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Order type", selection: $type) {
                ForEach(OrderType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                fieldLabel("Quantity")
                TextField("Quantity", text: $quantityText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .labelsHidden()
                Stepper("Quantity", value: Binding(get: { quantity }, set: { quantityText = String($0) }),
                        in: 1...maxQuantity)
                    .labelsHidden()
                Text(quantity == 1 ? "contract" : "contracts")
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
            }

            if type != .market {
                HStack(spacing: 6) {
                    fieldLabel(type == .limit ? "Limit price" : "Stop price")
                    TextField("Price", text: $priceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 104)
                        .labelsHidden()
                        .onSubmit { if let price { setPrice(TradingFormat.snapped(price, spec)) } }
                    Button { nudge(-1) } label: { Image(systemName: "minus") }
                        .help("One tick lower")
                        .accessibilityLabel("One tick lower")
                    Button { nudge(1) } label: { Image(systemName: "plus") }
                        .help("One tick higher")
                        .accessibilityLabel("One tick higher")
                }
                HStack(spacing: 6) {
                    fieldLabel("")
                    Button("Use bid") { setPrice(simulation.frame[symbol].bid) }
                        .buttonStyle(HCGButtonStyle(.quiet))
                    Button("Use ask") { setPrice(simulation.frame[symbol].ask) }
                        .buttonStyle(HCGButtonStyle(.quiet))
                }
            }

            if let lock = simulation.account.tradingLock {
                Label("Trading locked: \(lock.title). \(lock.unlockText)", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(HCGColor.loss)
                    .fixedSize(horizontal: false, vertical: true)
            }

            bracketSection(spec)

            TicketPreview(symbol: symbol, side: side, type: type, quantity: quantity,
                          price: type == .market ? nil : price, bracket: bracketSpec)

            Button(action: submit) {
                Text(isSubmitting ? "Placing…" : "Place simulated \(side.rawValue) order")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HCGButtonStyle(.primary))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isSubmitting || simulation.account.tradingLock != nil
                      || (type != .market && price == nil) || (attachBracket && bracketSpec == nil))
            .help("Places a simulated order (⌘↩). Nothing is sent outside this Mac.")

            if let outcome {
                Text(outcome.message)
                    .font(.caption)
                    .foregroundStyle(outcome.rejected ? HCGColor.loss : HCGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .hcgPanel()
        .onAppear { if price == nil { setPrice(defaultPrice()) } }
        .onChange(of: symbol) {
            setPrice(defaultPrice())
            outcome = nil
        }
        .onChange(of: type) { setPrice(defaultPrice()) }
    }

    @ViewBuilder
    private func bracketSection(_ spec: InstrumentSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Attach take profit / stop loss", isOn: $attachBracket)
            if attachBracket {
                bracketRow("Take profit", isOn: $useTakeProfit, ticks: $takeProfitTicks, spec: spec)
                bracketRow("Stop loss", isOn: $useStopLoss, ticks: $stopLossTicks, spec: spec)
                Text("Distances in ticks from the entry's average fill. Both orders are reduce-only and cancel each other when one fills.")
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bracketRow(_ title: String, isOn: Binding<Bool>, ticks: Binding<Int>, spec: InstrumentSpec) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: isOn)
                .frame(width: 110, alignment: .leading)
            Stepper(value: ticks, in: 1...2_000) {
                Text("\(PriceFormat.ticks(ticks.wrappedValue)) · \(TradingFormat.money(Double(ticks.wrappedValue) * spec.tickValue))/contract")
                    .font(HCGFont.value(12, weight: .regular))
                    .monospacedDigit()
            }
            .disabled(!isOn.wrappedValue)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(HCGColor.textSecondary)
            .frame(width: 84, alignment: .leading)
    }

    private var quantity: Int { Int(quantityText.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var price: Double? { TradingFormat.parsePrice(priceText) }

    private func setPrice(_ value: Double?) {
        priceText = value.map { TradingFormat.priceText($0, symbol.spec) } ?? ""
    }

    private var bracketSpec: BracketSpec? {
        guard attachBracket, useTakeProfit || useStopLoss else { return nil }
        return BracketSpec(takeProfitTicks: useTakeProfit ? takeProfitTicks : nil,
                           stopLossTicks: useStopLoss ? stopLossTicks : nil)
    }

    // MARK: Actions

    private func submit() {
        guard !isSubmitting else { return }
        let spec = symbol.spec
        let entered = type == .market ? nil : price.map { TradingFormat.snapped($0, spec) }
        if let entered { setPrice(entered) }
        // Each submission gets a new client order ID; the button stays
        // disabled until the engine answers, so one click is one order.
        let request = OrderRequest(symbol: symbol, side: side, type: type, quantity: quantity,
                                   limitPrice: type == .limit ? entered : nil,
                                   stopPrice: type == .stop ? entered : nil,
                                   bracket: bracketSpec)
        isSubmitting = true
        Task {
            let result = await simulation.submit(request)
            outcome = Outcome(message: simulation.lastOrderMessage ?? "", rejected: !result.isAccepted)
            isSubmitting = false
        }
    }

    private func nudge(_ ticks: Int64) {
        let spec = symbol.spec
        guard let base = price ?? defaultPrice(), TradingFormat.isSafe(base) else { return }
        setPrice(spec.price(ticks: spec.ticks(price: base) + ticks))
    }

    /// Joins the best price for limits; places stops four ticks beyond the
    /// market, the nearest side they are valid on.
    private func defaultPrice() -> Double? {
        let snapshot = simulation.frame[symbol]
        let spec = snapshot.spec
        switch (type, side) {
        case (.market, _): return nil
        case (.limit, .buy): return snapshot.bid
        case (.limit, .sell): return snapshot.ask
        case (.stop, .buy): return spec.price(ticks: snapshot.askTicks + 4)
        case (.stop, .sell): return spec.price(ticks: snapshot.bidTicks - 4)
        }
    }
}

/// What the order will do, from the current simulated market and account.
/// The only part of the ticket that reads the frame.
private struct TicketPreview: View {
    let symbol: MarketSymbol
    let side: OrderSide
    let type: OrderType
    let quantity: Int
    let price: Double?
    let bracket: BracketSpec?
    @Environment(SimulationHost.self) private var simulation

    var body: some View {
        let frame = simulation.frame
        let account = frame.account
        let snapshot = frame[symbol]
        let spec = snapshot.spec
        let configuration = account.configuration
        let costs = configuration.costs(for: symbol)
        let margin = account.marginRequirement(adding: side, quantity: max(0, quantity), symbol: symbol)
        let reference = referencePrice(snapshot, slippage: configuration.slippageTicks)
        let warnings = checks(snapshot, account: account, margin: margin, equity: frame.equity)

        VStack(alignment: .leading, spacing: 5) {
            row("Execution", executionText(snapshot, slippage: configuration.slippageTicks))
            row("Commission + fees", TradingFormat.money(Double(max(0, quantity)) * (costs.commissionPerContract + costs.feesPerContract)))
            row("Margin after order", "\(TradingFormat.money(margin)) of \(TradingFormat.money(frame.equity)) equity")
            if let bracket, let reference {
                row("Bracket", bracketText(bracket, entry: reference, spec: spec))
            }
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(HCGColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HCGColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(HCGColor.textSecondary)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .foregroundStyle(HCGColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }

    /// Expected entry price: best opposite price plus slippage for market
    /// orders, the entered price otherwise.
    private func referencePrice(_ snapshot: MarketSnapshot, slippage: Int) -> Double? {
        let spec = snapshot.spec
        switch type {
        case .market:
            let ticks = side == .buy ? snapshot.askTicks + Int64(slippage) : snapshot.bidTicks - Int64(slippage)
            return spec.price(ticks: ticks)
        case .limit, .stop:
            guard let price, TradingFormat.isSafe(price) else { return nil }
            return spec.roundedToTick(price)
        }
    }

    private func executionText(_ snapshot: MarketSnapshot, slippage: Int) -> String {
        let spec = snapshot.spec
        let slip = slippage > 0 ? " + \(PriceFormat.ticks(slippage)) slippage" : ""
        switch type {
        case .market:
            let best = side == .buy ? snapshot.ask : snapshot.bid
            let shown = (side == .buy ? snapshot.asks.first?.size : snapshot.bids.first?.size) ?? 0
            let depth = quantity > shown ? "; more than the \(shown) shown there, so the rest fills deeper in the book" : ""
            return "Now, from \(TradingFormat.price(best, spec)) (best \(side == .buy ? "ask" : "bid"))\(slip)\(depth)."
        case .limit:
            guard let price, TradingFormat.isSafe(price) else { return "Enter a limit price." }
            let limit = spec.roundedToTick(price)
            let marketable = side == .buy ? limit >= snapshot.ask : limit <= snapshot.bid
            if marketable {
                return "Marketable: fills now at up to \(TradingFormat.price(limit, spec)); any rest works at the limit."
            }
            let queue = simulation.frame.account.estimatedQueue(side: side, limitTicks: spec.ticks(price: limit),
                                                                 market: simulation.frame.marketView(symbol))
            let place = queue.map { $0 == 0 ? "at the front of the queue" : "behind about \($0) contracts" }
                ?? "beyond the visible book; it joins the back of the queue when that price comes into view"
            return "Rests at \(TradingFormat.price(limit, spec)), \(place). It fills as trades print there, or when the market reaches through it."
        case .stop:
            guard let price, TradingFormat.isSafe(price) else { return "Enter a stop price." }
            let stop = TradingFormat.price(spec.roundedToTick(price), spec)
            return side == .buy
                ? "Triggers when the ask reaches \(stop), then fills at market\(slip)."
                : "Triggers when the bid falls to \(stop), then fills at market\(slip)."
        }
    }

    private func bracketText(_ bracket: BracketSpec, entry: Double, spec: InstrumentSpec) -> String {
        let entryTicks = spec.ticks(price: entry)
        let direction: Int64 = side == .buy ? 1 : -1
        var parts: [String] = []
        if let tp = bracket.takeProfitTicks {
            parts.append("TP ≈ \(TradingFormat.price(spec.price(ticks: entryTicks + direction * Int64(tp)), spec))")
        }
        if let sl = bracket.stopLossTicks {
            parts.append("SL ≈ \(TradingFormat.price(spec.price(ticks: entryTicks - direction * Int64(sl)), spec))")
        }
        return parts.joined(separator: " · ") + " (final prices follow the average fill)"
    }

    /// Mirrors the engine's main checks so problems are visible before
    /// placing. The engine still validates every order.
    private func checks(_ snapshot: MarketSnapshot, account: TradingAccount, margin: Double, equity: Double) -> [String] {
        let spec = snapshot.spec
        let risk = account.configuration.risk
        var list: [String] = []
        if quantity < 1 { list.append("Quantity must be at least 1.") }
        if quantity > risk.maxOrderQuantity { list.append("Above the \(risk.maxOrderQuantity)-contract order limit.") }
        if type != .market, let price {
            if !TradingFormat.isSafe(price) {
                list.append("Enter a positive price.")
            } else {
                let snapped = spec.roundedToTick(price)
                if abs(snapped - price) > spec.tickSize / 1_000 {
                    list.append("Not on the \(TradingFormat.price(spec.tickSize, spec)) tick; it will be placed at \(TradingFormat.price(snapped, spec)).")
                }
                if type == .stop {
                    if side == .buy, snapped <= snapshot.ask { list.append("A buy stop must be above the ask.") }
                    if side == .sell, snapped >= snapshot.bid { list.append("A sell stop must be below the bid.") }
                }
            }
        }
        if risk.enforceBuyingPower, margin > equity {
            list.append("Margin would exceed equity, so the order will be rejected.")
        }
        return list
    }
}
