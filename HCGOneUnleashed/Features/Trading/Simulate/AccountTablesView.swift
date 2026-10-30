import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// The simulated blotter: positions, working orders and history.
///
/// Reads `simulation.account`, which changes only when the account does, so
/// these tables are not rebuilt on every market update. The positions table
/// is the exception: it shows unrealized P&L and reads the frame.
struct AccountTablesView: View {
    let selectedSymbol: MarketSymbol
    @Environment(SimulationHost.self) private var simulation
    @State private var tab: BlotterTab = .positions

    var body: some View {
        let account = simulation.account

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Blotter", selection: $tab) {
                    ForEach(BlotterTab.allCases) { item in
                        Text(item.title(account)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 8)
                trailingActions(account)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            switch tab {
            case .positions:
                PositionsTable()
            case .working:
                WorkingOrdersTable(account: account)
            case .orders:
                OrderHistoryTable(orders: Array(account.orderHistory.reversed()))
            case .fills:
                FillsTable(fills: Array(account.fills.reversed()))
            case .trades:
                TradesTable(trades: Array(account.trades.reversed()))
            case .activity:
                ActivityTable(events: Array(account.events.reversed()))
            }
        }
        .background(HCGColor.surface)
    }

    @ViewBuilder
    private func trailingActions(_ account: TradingAccount) -> some View {
        switch tab {
        case .working:
            Button("Cancel \(selectedSymbol.ticker)") { Task { await simulation.cancelAll(symbol: selectedSymbol) } }
                .buttonStyle(HCGButtonStyle(.quiet))
                .disabled(!account.hasOpenOrders(selectedSymbol))
            Button("Cancel All") { Task { await simulation.cancelAll() } }
                .buttonStyle(HCGButtonStyle(.secondary))
                .disabled(account.openOrders.isEmpty)
        case .positions:
            Button("Flatten All") { Task { await simulation.flattenAll() } }
                .buttonStyle(HCGButtonStyle(.secondary))
                .disabled(account.positions.isEmpty && account.openOrders.isEmpty)
        case .orders, .fills, .trades, .activity:
            Text(historyNote(account))
                .font(.caption)
                .foregroundStyle(HCGColor.textSecondary)
        }
    }

    private func historyNote(_ account: TradingAccount) -> String {
        switch tab {
        case .orders: "Newest first · last \(TradingAccount.orderHistoryLimit.formatted()) kept"
        case .fills: "Newest first · last \(TradingAccount.fillLimit.formatted()) kept"
        case .trades: "Newest first · last \(TradingAccount.tradeLimit.formatted()) kept"
        default: "Newest first · last \(TradingAccount.eventLimit) kept"
        }
    }
}

enum BlotterTab: String, CaseIterable, Identifiable {
    case positions, working, orders, fills, trades, activity

    var id: String { rawValue }

    func title(_ account: TradingAccount) -> String {
        switch self {
        case .positions: "Positions (\(account.positions.count))"
        case .working: "Working (\(account.openOrders.count))"
        case .orders: "Orders"
        case .fills: "Fills"
        case .trades: "Trades"
        case .activity: "Activity"
        }
    }
}

// MARK: - Tables

private struct PositionsTable: View {
    @Environment(SimulationHost.self) private var simulation
    @State private var protecting: MarketSymbol?

    var body: some View {
        let frame = simulation.frame
        let account = frame.account
        let rows = MarketSymbol.allCases.compactMap { account.position($0) }

        Table(rows) {
            TableColumn("Market") { p in
                Text(p.symbol.ticker).fontWeight(.semibold)
            }
            .width(min: 50, ideal: 60)
            TableColumn("Side") { p in
                Text(TradingFormat.positionSide(p)).foregroundStyle(p.isLong ? HCGColor.bid : HCGColor.ask)
            }
            .width(min: 44, ideal: 52)
            TableColumn("Qty") { p in
                Text("\(abs(p.quantity))").monospacedDigit()
            }
            .width(min: 34, ideal: 40)
            TableColumn("Avg price") { p in
                Text(TradingFormat.averagePrice(p.averagePrice, p.symbol.spec)).monospacedDigit()
            }
            TableColumn("Mark") { p in
                let snapshot = frame[p.symbol]
                Text(TradingFormat.price(p.isLong ? snapshot.bid : snapshot.ask, p.symbol.spec)).monospacedDigit()
            }
            TableColumn("Unrealized") { p in
                let pnl = frame.unrealizedPnL(p.symbol)
                Text(TradingFormat.money(pnl, signed: true))
                    .monospacedDigit()
                    .foregroundStyle(HCGColor.tone(for: pnl))
            }
            TableColumn("Protection") { p in
                Text(protection(p.symbol, account: account))
                    .foregroundStyle(HCGColor.textSecondary)
            }
            TableColumn("Opened (UTC)") { p in
                Text(TradingFormat.time(p.openedAt)).monospacedDigit()
            }
            TableColumn("") { p in
                HStack(spacing: 6) {
                    Button("Protect…") { protecting = p.symbol }
                    Button("Close") { Task { await simulation.closePosition(p.symbol) } }
                }
                .controlSize(.small)
            }
            .width(min: 130, ideal: 140)
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No open simulated positions", systemImage: "tray",
                                       description: Text("Positions opened from the ticket appear here."))
            }
        }
        .sheet(item: $protecting) { symbol in
            ProtectionSheet(symbol: symbol)
        }
    }

    private func protection(_ symbol: MarketSymbol, account: TradingAccount) -> String {
        let spec = symbol.spec
        let working = account.openOrders(for: symbol).filter { $0.status != .accepted }
        var parts: [String] = []
        if let stop = working.first(where: { $0.role == .stopLoss })?.stopPrice(spec) {
            parts.append("SL \(TradingFormat.price(stop, spec))")
        }
        if let target = working.first(where: { $0.role == .takeProfit })?.limitPrice(spec) {
            parts.append("TP \(TradingFormat.price(target, spec))")
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }
}

private struct WorkingOrdersTable: View {
    let account: TradingAccount
    @Environment(SimulationHost.self) private var simulation

    var body: some View {
        Table(account.openOrders) {
            TableColumn("Order") { o in Text("#\(o.id)").monospacedDigit() }
                .width(min: 40, ideal: 50)
            TableColumn("Market") { o in Text(o.symbol.ticker).fontWeight(.semibold) }
                .width(min: 44, ideal: 54)
            TableColumn("Side") { o in
                Text(o.side.label).foregroundStyle(o.side == .buy ? HCGColor.bid : HCGColor.ask)
            }
            .width(min: 34, ideal: 40)
            TableColumn("Type") { o in Text(TradingFormat.kind(o)) }
            TableColumn("Qty") { o in Text("\(o.quantity)").monospacedDigit() }
                .width(min: 30, ideal: 36)
            TableColumn("Filled") { o in Text("\(o.filledQuantity)").monospacedDigit() }
                .width(min: 34, ideal: 40)
            TableColumn("Price") { o in Text(TradingFormat.orderPrice(o)).monospacedDigit() }
            TableColumn("Status") { o in
                Text(o.status == .accepted ? "Waiting for entry fill" : o.status.label)
                    .foregroundStyle(HCGColor.textSecondary)
            }
            TableColumn("Placed (UTC)") { o in Text(TradingFormat.time(o.createdAt)).monospacedDigit() }
            TableColumn("") { o in
                Button("Cancel") { Task { await simulation.cancel(orderID: o.id) } }
                    .controlSize(.small)
            }
            .width(min: 64, ideal: 70)
        }
        .overlay {
            if account.openOrders.isEmpty {
                ContentUnavailableView("No working simulated orders", systemImage: "tray",
                                       description: Text("Limit, stop and bracket orders wait here until they fill or are cancelled."))
            }
        }
    }
}

private struct OrderHistoryTable: View {
    let orders: [Order]

    var body: some View {
        Table(orders) {
            TableColumn("Order") { o in Text("#\(o.id)").monospacedDigit() }
                .width(min: 40, ideal: 50)
            TableColumn("Market") { o in Text(o.symbol.ticker).fontWeight(.semibold) }
                .width(min: 44, ideal: 54)
            TableColumn("Side") { o in Text(o.side.label) }
                .width(min: 34, ideal: 40)
            TableColumn("Type") { o in Text(TradingFormat.kind(o)) }
            TableColumn("Qty") { o in Text("\(o.filledQuantity)/\(o.quantity)").monospacedDigit() }
                .width(min: 40, ideal: 48)
            TableColumn("Price") { o in Text(TradingFormat.orderPrice(o)).monospacedDigit() }
            TableColumn("Avg fill") { o in
                Text(TradingFormat.averagePrice(o.averageFillPrice, o.symbol.spec)).monospacedDigit()
            }
            TableColumn("Status") { o in
                Text(o.status.label).foregroundStyle(o.status == .rejected ? HCGColor.loss : HCGColor.textPrimary)
            }
            TableColumn("Reason") { o in
                Text(o.statusReason ?? "").foregroundStyle(HCGColor.textSecondary).help(o.statusReason ?? "")
            }
            TableColumn("Updated (UTC)") { o in Text(TradingFormat.time(o.updatedAt)).monospacedDigit() }
        }
        .overlay {
            if orders.isEmpty {
                ContentUnavailableView("No finished simulated orders", systemImage: "clock")
            }
        }
    }
}

private struct FillsTable: View {
    let fills: [Fill]

    var body: some View {
        Table(fills) {
            TableColumn("Fill") { f in Text("\(f.id)").monospacedDigit() }
                .width(min: 36, ideal: 44)
            TableColumn("Order") { f in Text("#\(f.orderID)").monospacedDigit() }
                .width(min: 40, ideal: 50)
            TableColumn("Market") { f in Text(f.symbol.ticker).fontWeight(.semibold) }
                .width(min: 44, ideal: 54)
            TableColumn("Side") { f in Text(f.side.label) }
                .width(min: 34, ideal: 40)
            TableColumn("Qty") { f in Text("\(f.quantity)").monospacedDigit() }
                .width(min: 30, ideal: 36)
            TableColumn("Price") { f in Text(TradingFormat.averagePrice(f.price, f.symbol.spec)).monospacedDigit() }
            TableColumn("Liquidity") { f in Text(f.liquidity == .maker ? "Resting" : "Taker") }
            TableColumn("Costs") { f in Text(TradingFormat.money(f.commission + f.fees)).monospacedDigit() }
            TableColumn("Realized") { f in
                Text(f.realizedPnL == 0 ? "—" : TradingFormat.money(f.realizedPnL, signed: true))
                    .monospacedDigit()
                    .foregroundStyle(HCGColor.tone(for: f.realizedPnL))
            }
            TableColumn("Time (UTC)") { f in Text(TradingFormat.time(f.time)).monospacedDigit() }
        }
        .overlay {
            if fills.isEmpty {
                ContentUnavailableView("No simulated fills yet", systemImage: "clock")
            }
        }
    }
}

private struct TradesTable: View {
    let trades: [TradeRecord]

    var body: some View {
        Table(trades) {
            TableColumn("Trade") { t in Text("\(t.id)").monospacedDigit() }
                .width(min: 36, ideal: 44)
            TableColumn("Market") { t in Text(t.symbol.ticker).fontWeight(.semibold) }
                .width(min: 44, ideal: 54)
            TableColumn("Direction") { t in Text(t.direction == .long ? "Long" : "Short") }
            TableColumn("Qty") { t in Text("\(t.quantity)").monospacedDigit() }
                .width(min: 30, ideal: 36)
            TableColumn("Entry") { t in Text(TradingFormat.averagePrice(t.entryPrice, t.symbol.spec)).monospacedDigit() }
            TableColumn("Exit") { t in Text(TradingFormat.averagePrice(t.exitPrice, t.symbol.spec)).monospacedDigit() }
            TableColumn("Gross") { t in
                Text(TradingFormat.money(t.grossPnL, signed: true)).monospacedDigit().foregroundStyle(HCGColor.tone(for: t.grossPnL))
            }
            TableColumn("Net") { t in
                Text(TradingFormat.money(t.netPnL, signed: true)).monospacedDigit().foregroundStyle(HCGColor.tone(for: t.netPnL))
            }
            TableColumn("Opened (UTC)") { t in Text(TradingFormat.time(t.entryTime)).monospacedDigit() }
            TableColumn("Closed (UTC)") { t in Text(TradingFormat.time(t.exitTime)).monospacedDigit() }
        }
        .overlay {
            if trades.isEmpty {
                ContentUnavailableView("No completed simulated trades", systemImage: "clock",
                                       description: Text("A trade is recorded when a position, or part of one, is closed."))
            }
        }
    }
}

private struct ActivityTable: View {
    let events: [AccountEvent]

    var body: some View {
        Table(events) {
            TableColumn("Time (UTC)") { e in Text(TradingFormat.time(e.time)).monospacedDigit() }
                .width(min: 70, ideal: 80)
            TableColumn("Event") { e in
                Text(TradingFormat.eventKind(e.kind))
                    .foregroundStyle(e.kind == .orderRejected ? HCGColor.loss : HCGColor.textPrimary)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Details") { e in Text(e.message).help(e.message) }
        }
        .overlay {
            if events.isEmpty {
                ContentUnavailableView("No simulated activity yet", systemImage: "clock")
            }
        }
    }
}
