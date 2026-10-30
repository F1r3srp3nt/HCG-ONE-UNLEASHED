import Foundation

/// Display formatting for trading values. Never used for calculations.
public enum PriceFormat {
    /// A price with fixed decimals, e.g. `2,655.10`.
    public static func price(_ value: Double, decimals: Int, locale: Locale = .current) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(
            .number
                .precision(.fractionLength(decimals))
                .grouping(.automatic)
                .locale(locale)
        )
    }

    /// A price change with an explicit sign, e.g. `+1.20` / `−0.75`.
    /// Uses the typographic minus sign for negative values.
    public static func change(_ value: Double, decimals: Int, locale: Locale = .current) -> String {
        guard value.isFinite else { return "—" }
        let body = price(abs(value), decimals: decimals, locale: locale)
        if value > 0 { return "+" + body }
        if value < 0 { return "\u{2212}" + body }
        return body
    }

    /// An amount of money, e.g. `$1,250.00` / `−$40.00`.
    public static func money(_ value: Double, currency: String, signed: Bool = false, locale: Locale = .current) -> String {
        guard value.isFinite else { return "—" }
        let body = abs(value).formatted(.currency(code: currency).precision(.fractionLength(2)).locale(locale))
        if value < 0 { return "\u{2212}" + body }
        if signed && value > 0 { return "+" + body }
        return body
    }

    /// A tick count with unit, e.g. `1 tick` / `3 ticks`.
    public static func ticks(_ count: Int) -> String {
        count == 1 ? "1 tick" : "\(count) ticks"
    }
}
