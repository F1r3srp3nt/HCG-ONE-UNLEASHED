import AppKit
import HCGDesignSystem
import SwiftUI

/// Image names for HCG ONE UNLEASHED branding in `Resources/Assets.xcassets`.
///
/// The approved futuristic UNLEASHED artwork is **not in the repository yet**.
/// When it is installed under these names (docs/M1_AUDIT.md §5), every brand
/// view picks it up automatically; until then the existing Hakmi Capital Group
/// logo and the text wordmark are shown. Nothing here invents new artwork.
enum BrandAsset {
    /// Approved UNLEASHED symbol: square, transparent background, light/dark variants.
    static let unleashedMark = "HCGUnleashedMark"
    /// Approved UNLEASHED wordmark: horizontal, transparent background, light/dark variants.
    static let unleashedWordmark = "HCGUnleashedWordmark"
    /// Existing Hakmi Capital Group logo carried over from HCG ONE (silver on black, square).
    static let companyLogo = "HCGLogo"

    static func isInstalled(_ name: String) -> Bool {
        NSImage(named: name) != nil
    }
}

/// Square brand symbol: the approved UNLEASHED mark when installed, otherwise
/// the HCG company logo on its black tile.
struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        if BrandAsset.isInstalled(BrandAsset.unleashedMark) {
            Image(BrandAsset.unleashedMark)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("HCG ONE UNLEASHED")
        } else {
            Image(BrandAsset.companyLogo)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.21, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                        .strokeBorder(HCGColor.separator, lineWidth: 1)
                )
                .accessibilityLabel("Hakmi Capital Group logo")
        }
    }
}

/// Horizontal wordmark: the approved UNLEASHED wordmark image when installed,
/// otherwise the typeset `HCGWordmark`.
struct BrandWordmark: View {
    let size: CGFloat

    var body: some View {
        if BrandAsset.isInstalled(BrandAsset.unleashedWordmark) {
            Image(BrandAsset.unleashedWordmark)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: size * 1.2)
                .accessibilityLabel("HCG ONE UNLEASHED")
        } else {
            HCGWordmark(size: size)
        }
    }
}
