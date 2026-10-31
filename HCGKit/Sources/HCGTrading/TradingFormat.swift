import Foundation
import HCGDomain

/// Formatting and price-entry helpers shared by the simulated trading screens.
public enum TradingFormat {
    /// All four simulated instruments are quoted in US dollars, so the
    /// simulated account is kept in US dollars too.
    public static let accountCurrency = "USD"

    /// Simulated time is shown in UTC: the simulated session opens at 14:30 UTC,
    /// which would read differently in every local time zone.
    private static let timeStyle = Date.FormatStyle(date: .omitted, time: .standard, timeZone: .gmt)
    private static let dateTimeStyle = Date.FormatStyle(date: .numeric, time: .standard, timeZone: .gmt)

    public static func time(_ date: Date) -> String { date.formatted(timeStyle) }
    public static func dateTime(_ date: Date) -> String { date.formatted(dateTimeStyle) + " UTC" }

    public static func money(_ value: Double, signed: Bool = false) -> String {
        PriceFormat.money(value, currency: accountCurrency, signed: signed)
    }

    public static func price(_ value: Double?, _ spec: InstrumentSpec) -> String {
        guard let value else { return "—" }
        return PriceFormat.price(value, decimals: spec.priceDecimals)
    }

    /// Average prices can fall between ticks, so they get one extra decimal.
    public static func averagePrice(_ value: Double?, _ spec: InstrumentSpec) -> String {
        guard let value else { return "—" }
        return PriceFormat.price(value, decimals: spec.priceDecimals + 1)
    }

    // MARK: Editable prices

    /// Accepts "2655.1" everywhere and the user's own format ("2655,1" in a
    /// comma-decimal locale, "2,655.1" with grouping). `nil` when empty or
    /// unreadable.
    public static func parsePrice(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed) { return value }
        return try? Double(trimmed, format: FloatingPointFormatStyle<Double>(locale: locale))
    }

    /// A price for an editable field: the instrument's decimals, no grouping.
    public static func priceText(_ value: Double, _ spec: InstrumentSpec, locale: Locale = .current) -> String {
        value.formatted(FloatingPointFormatStyle<Double>(locale: locale)
            .precision(.fractionLength(spec.priceDecimals)).grouping(.never))
    }

    /// Prices the tick conversion can handle; anything else is left for the
    /// engine to reject.
    public static func isSafe(_ price: Double) -> Bool {
        price.isFinite && price > 0 && price < 1e9
    }

    /// Nearest valid tick, for prices the tick conversion can handle.
    public static func snapped(_ price: Double, _ spec: InstrumentSpec) -> Double {
        isSafe(price) ? spec.roundedToTick(price) : price
    }

    /// "Limit", "Stop", "Market", or the role of a reduce-only order.
    public static func kind(_ order: Order) -> String {
        switch order.role {
        case .entry: order.type.label
        case .close: "Close (market)"
        case .takeProfit: "Take profit (limit)"
        case .stopLoss: "Stop loss (stop)"
        }
    }

    /// The order's limit or stop price, or "Market".
    public static func orderPrice(_ order: Order) -> String {
        let spec = order.symbol.spec
        if let stop = order.stopPrice(spec) { return price(stop, spec) }
        if let limit = order.limitPrice(spec) { return price(limit, spec) }
        return "Market"
    }

    public static func positionSide(_ position: Position) -> String {
        position.isLong ? "Long" : "Short"
    }

    public static func eventKind(_ kind: AccountEvent.Kind) -> String {
        switch kind {
        case .orderAccepted: "Accepted"
        case .orderWorking: "Working"
        case .orderPartiallyFilled: "Partial fill"
        case .orderFilled: "Filled"
        case .orderCancelled: "Cancelled"
        case .orderRejected: "Rejected"
        case .accountReset: "Account reset"
        case .configurationChanged: "Settings"
        case .liquidation: "Liquidation"
        case .tradingLocked: "Trading locked"
        case .tradingUnlocked: "Trading unlocked"
        }
    }
}
