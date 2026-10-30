#if canImport(SwiftUI) && os(macOS)
import SwiftUI

/// HCG typography: a serif display face for brand moments (as in HCG ONE),
/// the system face for interface text, and tabular digits for every number.
public enum HCGFont {
    /// Brand display text (titles, wordmark).
    public static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Screen titles.
    public static let screenTitle = Font.system(size: 22, weight: .medium, design: .serif)

    /// Small uppercase labels above values and sections.
    public static let eyebrow = Font.system(size: 10, weight: .semibold)

    /// Trading values: monospaced digits so columns never jitter.
    public static func value(_ size: CGFloat = 13, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// Letter spacing used by eyebrow labels.
public enum HCGTracking {
    public static let eyebrow: CGFloat = 1.1
    public static let wordmark: CGFloat = 2.4
}
#endif
