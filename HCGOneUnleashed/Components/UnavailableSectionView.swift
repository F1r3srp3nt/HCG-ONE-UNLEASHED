import HCGDesignSystem
import SwiftUI

/// Honest placeholder for a destination that is not implemented in this
/// development build. It names what is missing and what it depends on —
/// it never shows sample or invented content.
struct UnavailableSectionView: View {
    let item: SidebarItem
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        let copy = UnavailableCopy(item: item)
        VStack(spacing: 18) {
            Image(systemName: item.systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(HCGColor.textSecondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(item.title)
                    .font(HCGFont.screenTitle)
                    .foregroundStyle(HCGColor.textPrimary)
                StatusBadge("Not available in this development build", tone: .unavailable, systemImage: "hammer")
            }

            Text(copy.summary)
                .font(.callout)
                .foregroundStyle(HCGColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(copy.details, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").accessibilityHidden(true)
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(HCGColor.textSecondary)
            .frame(maxWidth: 460, alignment: .leading)
            .hcgPanel()

            if item.area == .trading {
                Button("Open Order Flow") { navigation.selection = .orderFlow }
                    .buttonStyle(HCGButtonStyle(.primary))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(item.title)
    }
}

/// What each unavailable destination will contain, and what it waits on.
/// Milestones refer to docs/DEVELOPMENT_ROADMAP.md.
private struct UnavailableCopy {
    let summary: String
    let details: [String]

    init(item: SidebarItem) {
        switch item {
        case .learn:
            summary = "Structured trading lessons from HCG ONE's Trading Lab curriculum."
            details = ["Planned for milestone M2 (trading workstation).",
                       "Lesson content exists in HCG ONE and will be ported deliberately."]
        case .simulate:
            summary = "A full simulated order ticket with positions, orders and history."
            details = ["Planned for milestone M2.",
                       "A basic simulated ticket (market orders only) is already available at the bottom of Order Flow."]
        case .marketLab:
            summary = "Scripted market scenarios — sweeps, absorption, breakouts — with debriefs."
            details = ["Planned for milestone M2.",
                       "The ten HCG ONE scenarios already run in the simulation engine of this build."]
        case .progress:
            summary = "Lesson, quiz and scenario progress for the simulated Trading Lab."
            details = ["Planned for milestone M2.",
                       "Progress will be stored only on this Mac."]
        case .explore:
            summary = "HCG applications, services and product discovery."
            details = ["Planned for milestone M5.",
                       "Service requests are not offered until HCG provides a server endpoint to receive them."]
        case .projects:
            summary = "Your authorized HCG project information."
            details = ["Requires sign-in (milestone M3) and an HCG projects service, which does not exist yet.",
                       "No project data is stored or shown in this build."]
        case .connect:
            summary = "HCG Connect inbox and messages with the HCG team."
            details = ["Requires sign-in (milestone M3); messaging arrives in milestone M5.",
                       "This build makes no network connections."]
        case .profile:
            summary = "Your HCG account profile."
            details = ["Requires sign-in with your HCG account (milestone M3, subject to approval).",
                       "The Executive Workspace appears only after HCG's servers verify access. It is never shown from local data."]
        case .clientWorkspace:
            summary = "The HCG Client Workspace, opened securely from your HCG account."
            details = ["Requires sign-in (milestone M3) and server-authorized workspace access (milestone M4).",
                       "Access is always decided by HCG's servers, never by this app."]
        case .home, .orderFlow, .settings:
            summary = ""
            details = []
        }
    }
}
