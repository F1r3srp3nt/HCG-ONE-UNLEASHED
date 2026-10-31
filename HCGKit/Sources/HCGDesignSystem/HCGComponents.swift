#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Panel surfaces

/// Rounded surface with a hairline border, used for every content panel.
public struct HCGPanelSurface: ViewModifier {
    var padding: CGFloat

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(HCGColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(HCGColor.separator, lineWidth: 1)
            )
    }
}

public extension View {
    func hcgPanel(padding: CGFloat = 14) -> some View {
        modifier(HCGPanelSurface(padding: padding))
    }
}

/// Uppercase, tracked label for sections and values.
public struct Eyebrow: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(HCGFont.eyebrow)
            .tracking(HCGTracking.eyebrow)
            .foregroundStyle(HCGColor.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Header row of a panel: eyebrow title, optional detail and trailing content.
public struct PanelHeader<Trailing: View>: View {
    let title: String
    let detail: String?
    let trailing: Trailing

    public init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Eyebrow(title)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

public extension PanelHeader where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

// MARK: - Buttons

/// HCG button style with hover and pressed feedback.
public struct HCGButtonStyle: ButtonStyle {
    public enum Kind: Sendable {
        /// Filled accent — the single most important action on a surface.
        case primary
        /// Bordered — secondary actions.
        case secondary
        /// Borderless until hovered — toolbars and dense rows.
        case quiet
    }

    let kind: Kind

    public init(_ kind: Kind = .secondary) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        HCGButtonBody(configuration: configuration, kind: kind)
    }
}

private struct HCGButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: HCGButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(border, lineWidth: kind == .secondary ? 1 : 0)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var foreground: Color {
        kind == .primary ? HCGColor.onAccent : HCGColor.textPrimary
    }

    private var background: Color {
        switch kind {
        case .primary:
            HCGColor.accent.opacity(configuration.isPressed ? 0.8 : (isHovered ? 0.92 : 1))
        case .secondary:
            HCGColor.surfaceRaised.opacity(configuration.isPressed ? 1 : (isHovered ? 0.9 : 0.6))
        case .quiet:
            HCGColor.surfaceRaised.opacity(configuration.isPressed ? 1 : (isHovered ? 0.8 : 0))
        }
    }

    private var border: Color {
        HCGColor.separator.opacity(isHovered ? 1 : 0.8)
    }
}

// MARK: - Status

/// Compact capsule label for state: simulated data, unavailable sections, etc.
public struct StatusBadge: View {
    public enum Tone: Sendable {
        case neutral, simulated, unavailable, positive, negative, warning
    }

    let text: String
    let tone: Tone
    let systemImage: String?

    public init(_ text: String, tone: Tone = .neutral, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            }
            Text(text.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.8)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .fixedSize()
    }

    private var color: Color {
        switch tone {
        case .neutral: HCGColor.textSecondary
        case .simulated: HCGColor.info
        case .unavailable: HCGColor.textSecondary
        case .positive: HCGColor.gain
        case .negative: HCGColor.loss
        case .warning: HCGColor.warning
        }
    }
}

/// The badge shown wherever market data appears.
public struct SimulatedDataBadge: View {
    public init() {}

    public var body: some View {
        StatusBadge("Simulated data", tone: .simulated, systemImage: "waveform.path.ecg")
            .help("All market data in HCG ONE: UNLEASHED is simulated. No exchange, broker or live feed is connected.")
            .accessibilityLabel("Simulated data. No live market feed is connected.")
    }
}

/// Small colored dot for live/idle states.
public struct StatusDot: View {
    let color: Color

    public init(_ color: Color) { self.color = color }

    public var body: some View {
        Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
    }
}

// MARK: - Trading values

/// A price rendered with tabular digits.
public struct PriceText: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let color: Color

    public init(_ text: String, size: CGFloat = 13, weight: Font.Weight = .medium, color: Color = HCGColor.textPrimary) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(HCGFont.value(size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Labelled trading value (eyebrow above a tabular figure).
public struct TradingStat: View {
    let label: String
    let value: String
    let color: Color
    let size: CGFloat

    public init(_ label: String, value: String, color: Color = HCGColor.textPrimary, size: CGFloat = 15) {
        self.label = label
        self.value = value
        self.color = color
        self.size = size
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(label)
            PriceText(value, size: size, weight: .medium, color: color)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Navigation & brand

/// Sidebar row: icon and title, with a subdued look for sections that are not
/// available in the current build.
public struct HCGSidebarLabel: View {
    let title: String
    let systemImage: String
    let isAvailable: Bool

    public init(_ title: String, systemImage: String, isAvailable: Bool = true) {
        self.title = title
        self.systemImage = systemImage
        self.isAvailable = isAvailable
    }

    public var body: some View {
        Label {
            Text(title)
                .foregroundStyle(isAvailable ? HCGColor.textPrimary : HCGColor.textSecondary)
        } icon: {
            Image(systemName: systemImage)
        }
        .help(isAvailable ? title : "\(title) — not available in this development build")
    }
}

/// "HCG ONE: UNLEASHED" set in the brand display face.
public struct HCGWordmark: View {
    let size: CGFloat

    public init(size: CGFloat = 20) { self.size = size }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.35) {
            Text("HCG ONE:")
                .font(HCGFont.display(size, weight: .medium))
                .tracking(size * 0.04)
                .foregroundStyle(HCGColor.textPrimary)
            Text("UNLEASHED")
                .font(.system(size: size * 0.48, weight: .semibold))
                .tracking(HCGTracking.wordmark)
                .foregroundStyle(HCGColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HCG ONE: UNLEASHED")
    }
}
#endif
