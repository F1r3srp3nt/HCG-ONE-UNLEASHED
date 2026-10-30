#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

/// HCG semantic colors for macOS.
///
/// The brand identity from HCG ONE (obsidian surfaces, silver accent) is kept
/// for dark appearance. Light appearance uses ivory/white surfaces with a
/// graphite accent so text and values stay readable. Increased-contrast
/// variants are provided for separators and secondary text.
public enum HCGColor {
    // Surfaces
    public static let canvas = dynamic(light: 0xF4F4F2, dark: 0x08090B)
    public static let surface = dynamic(light: 0xFFFFFF, dark: 0x111215)
    public static let surfaceRaised = dynamic(light: 0xEFEFED, dark: 0x1C1D21)
    public static let separator = dynamic(light: 0xDADBDD, dark: 0x2A2C31,
                                          highContrastLight: 0x8E9096, highContrastDark: 0x6A6D74)

    // Text
    public static let textPrimary = dynamic(light: 0x16171A, dark: 0xF5F5F3)
    public static let textSecondary = dynamic(light: 0x5F626A, dark: 0x9A9DA3,
                                              highContrastLight: 0x3E4046, highContrastDark: 0xC5C7CB)

    // Brand accent: silver in dark appearance, graphite in light.
    public static let accent = dynamic(light: 0x3E4148, dark: 0xC5C7CB)
    /// Text drawn on top of `accent`.
    public static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x08090B)

    // Status
    public static let gain = dynamic(light: 0x2D7A4E, dark: 0x5E9C76)
    public static let loss = dynamic(light: 0xB23A36, dark: 0xD0605C)
    public static let warning = dynamic(light: 0x8F6220, dark: 0xC49A5C)
    public static let info = dynamic(light: 0x2F64A3, dark: 0x6F9BD1)

    // Trading roles
    public static let bid = gain
    public static let ask = loss
    public static let lastTrade = dynamic(light: 0x16171A, dark: 0xF5F5F3)
    public static let vwap = warning

    /// Tone for a signed value: gain above zero, loss below, primary at zero.
    public static func tone(for value: Double) -> Color {
        if value > 0 { return gain }
        if value < 0 { return loss }
        return textPrimary
    }

    private static func dynamic(light: UInt32, dark: UInt32,
                                highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            switch match {
            case .darkAqua?: return NSColor(hcgHex: dark)
            case .accessibilityHighContrastDarkAqua?: return NSColor(hcgHex: highContrastDark ?? dark)
            case .accessibilityHighContrastAqua?: return NSColor(hcgHex: highContrastLight ?? light)
            default: return NSColor(hcgHex: light)
            }
        })
    }
}

extension NSColor {
    convenience init(hcgHex hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif
