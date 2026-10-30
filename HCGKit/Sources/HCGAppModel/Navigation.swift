import Foundation
import HCGDomain
import Observation

// App navigation model, kept free of SwiftUI so it is unit-testable on any
// platform. Moved here from the app target in M2.0 (docs/M1_AUDIT.md).

/// The six primary areas of HCG ONE UNLEASHED (Go menu, ⌘1…⌘6).
public enum PrimaryArea: String, CaseIterable, Identifiable, Sendable {
    case home, trading, explore, projects, connect, account

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .trading: "Trading"
        case .explore: "Explore"
        case .projects: "Projects"
        case .connect: "HCG Connect"
        case .account: "Account"
        }
    }

    /// Destination opened when the area is chosen from the Go menu.
    public var defaultItem: SidebarItem {
        switch self {
        case .home: .home
        case .trading: .orderFlow
        case .explore: .explore
        case .projects: .projects
        case .connect: .connect
        case .account: .profile
        }
    }

    /// Digit used with ⌘ in the Go menu.
    public var shortcutDigit: Character {
        switch self {
        case .home: "1"
        case .trading: "2"
        case .explore: "3"
        case .projects: "4"
        case .connect: "5"
        case .account: "6"
        }
    }
}

/// Every destination in the sidebar.
///
/// The Executive Workspace is deliberately absent: it is listed only after
/// HCG's servers verify access in the current session, and this build has no
/// sign-in (docs/SECURITY_BOUNDARIES.md, finding S-05).
public enum SidebarItem: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case learn, simulate, orderFlow, marketLab, progress
    case explore, projects, connect
    case profile, clientWorkspace, settings

    public var id: String { rawValue }

    public var area: PrimaryArea {
        switch self {
        case .home: .home
        case .learn, .simulate, .orderFlow, .marketLab, .progress: .trading
        case .explore: .explore
        case .projects: .projects
        case .connect: .connect
        case .profile, .clientWorkspace, .settings: .account
        }
    }

    public var title: String {
        switch self {
        case .home: "Home"
        case .learn: "Learn"
        case .simulate: "Simulate"
        case .orderFlow: "Order Flow"
        case .marketLab: "Market Lab"
        case .progress: "Progress"
        case .explore: "Explore"
        case .projects: "Projects"
        case .connect: "HCG Connect"
        case .profile: "Profile"
        case .clientWorkspace: "Client Workspace"
        case .settings: "Settings"
        }
    }

    /// SF Symbol name.
    public var systemImage: String {
        switch self {
        case .home: "house"
        case .learn: "book.closed"
        case .simulate: "arrow.left.arrow.right.square"
        case .orderFlow: "chart.bar.doc.horizontal"
        case .marketLab: "flask"
        case .progress: "chart.line.uptrend.xyaxis"
        case .explore: "sparkle.magnifyingglass"
        case .projects: "folder"
        case .connect: "bubble.left.and.bubble.right"
        case .profile: "person.crop.circle"
        case .clientWorkspace: "person.crop.circle.badge.checkmark"
        case .settings: "gearshape"
        }
    }

    /// Whether the destination has a working implementation in this build.
    public var isAvailableInThisBuild: Bool { developmentNote == nil }

    /// What an unavailable destination will contain and what it depends on.
    /// `nil` for destinations that work in this build. Milestones refer to
    /// docs/DEVELOPMENT_ROADMAP.md.
    public var developmentNote: DevelopmentNote? {
        switch self {
        case .home, .simulate, .orderFlow, .settings:
            nil
        case .learn:
            DevelopmentNote(
                summary: "Structured trading lessons from HCG ONE's Trading Lab curriculum.",
                details: ["Planned for milestone M2 (trading workstation).",
                          "Lesson content exists in HCG ONE and will be ported deliberately."])
        case .marketLab:
            DevelopmentNote(
                summary: "Scripted market scenarios — sweeps, absorption, breakouts — with debriefs.",
                details: ["Planned for milestone M2.",
                          "The ten HCG ONE scenarios are ported to the simulation engine, but there is no way to start them from the interface yet."])
        case .progress:
            DevelopmentNote(
                summary: "Lesson, quiz and scenario progress for the simulated Trading Lab.",
                details: ["Planned for milestone M2.",
                          "Progress will be stored only on this Mac."])
        case .explore:
            DevelopmentNote(
                summary: "HCG applications, services and product discovery.",
                details: ["Planned for milestone M5.",
                          "Service requests are not offered until HCG provides a server endpoint to receive them."])
        case .projects:
            DevelopmentNote(
                summary: "Your authorized HCG project information.",
                details: ["Requires sign-in (milestone M3) and an HCG projects service, which does not exist yet.",
                          "No project data is stored or shown in this build."])
        case .connect:
            DevelopmentNote(
                summary: "HCG Connect inbox and messages with the HCG team.",
                details: ["Requires sign-in (milestone M3); messaging arrives in milestone M5.",
                          "This build makes no network connections."])
        case .profile:
            DevelopmentNote(
                summary: "Your HCG account profile.",
                details: ["Requires sign-in with your HCG account (milestone M3, subject to approval).",
                          "The Executive Workspace appears only after HCG's servers verify access. It is never shown from local data."])
        case .clientWorkspace:
            DevelopmentNote(
                summary: "The HCG Client Workspace, opened securely from your HCG account.",
                details: ["Requires sign-in (milestone M3) and server-authorized workspace access (milestone M4).",
                          "Access is always decided by HCG's servers, never by this app."])
        }
    }

    public static let trading: [SidebarItem] = [.learn, .simulate, .orderFlow, .marketLab, .progress]
    public static let hcg: [SidebarItem] = [.explore, .projects, .connect]
    public static let account: [SidebarItem] = [.profile, .clientWorkspace, .settings]
}

/// Honest description of a destination that is not implemented yet.
public struct DevelopmentNote: Sendable, Equatable {
    public let summary: String
    public let details: [String]
}

/// Per-window navigation state, shared with menu commands.
@MainActor
@Observable
public final class NavigationModel {
    public var selection: SidebarItem?
    public var orderFlowSymbol: MarketSymbol

    public init(selection: SidebarItem? = .home, orderFlowSymbol: MarketSymbol = .gc) {
        self.selection = selection
        self.orderFlowSymbol = orderFlowSymbol
    }

    public func open(_ area: PrimaryArea) {
        selection = area.defaultItem
    }

    public func showOrderFlow(_ symbol: MarketSymbol) {
        orderFlowSymbol = symbol
        selection = .orderFlow
    }

    /// Restores state saved as raw strings (scene storage). Unknown or
    /// missing values fall back to Home and GC.
    public func restore(selection rawSelection: String?, symbol rawSymbol: String?) {
        selection = rawSelection.flatMap(SidebarItem.init(rawValue:)) ?? .home
        orderFlowSymbol = rawSymbol.flatMap(MarketSymbol.init(rawValue:)) ?? .gc
    }
}
