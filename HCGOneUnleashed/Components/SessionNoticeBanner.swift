import HCGDesignSystem
import HCGMarketSim
import SwiftUI

/// Shown above every screen after launch when the simulated session was
/// restored or could not be read, and whenever saving fails.
struct SessionNoticeBanner: View {
    @Environment(SimulationHost.self) private var simulation

    var body: some View {
        if let error = simulation.lastSaveError {
            banner(error, systemImage: "exclamationmark.triangle", tone: HCGColor.warning, dismiss: nil)
        } else if let notice = simulation.restoreNotice {
            banner(notice, systemImage: "clock.arrow.circlepath", tone: HCGColor.info) {
                simulation.dismissRestoreNotice()
            }
        }
    }

    private func banner(_ text: String, systemImage: String, tone: Color, dismiss: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tone)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(HCGColor.textPrimary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if let dismiss {
                Button("Dismiss", action: dismiss)
                    .buttonStyle(HCGButtonStyle(.quiet))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(HCGColor.surfaceRaised)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}
