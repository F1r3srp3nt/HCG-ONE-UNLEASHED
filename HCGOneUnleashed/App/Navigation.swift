import HCGDomain
import Observation
import SwiftUI

/// The six primary areas of HCG ONE UNLEASHED (Go menu, ⌘1…⌘6).
enum PrimaryArea: String, CaseIterable, Identifiable {
    case home, trading, explore, projects, connect, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .trading: "Trading"
        case .explore: "Explore"
        case .projects: "Projects"
        case .connect: "HCG Connect"
        case .account: "Account"
        }
    }

    /// Item selected when the area is opened from the Go menu.
    var defaultItem: SidebarItem {
        switch self {
        case .home: .home
        case .trading: .orderFlow
        case .explore: .explore
        case .projects: .projects
        case .connect: .connect
        case .account: .profile
        }
    }

    var shortcut: KeyEquivalent {
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
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home
    case learn, simulate, orderFlow, marketLab, progress
    case explore, projects, connect
    case profile, clientWorkspace, settings

    var id: String { rawValue }

    var area: PrimaryArea {
        switch self {
        case .home: .home
        case .learn, .simulate, .orderFlow, .marketLab, .progress: .trading
        case .explore: .explore
        case .projects: .projects
        case .connect: .connect
        case .profile, .clientWorkspace, .settings: .account
        }
    }

    var title: String {
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

    var systemImage: String {
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
    var isAvailableInThisBuild: Bool {
        switch self {
        case .home, .orderFlow, .settings: true
        default: false
        }
    }

    static let trading: [SidebarItem] = [.learn, .simulate, .orderFlow, .marketLab, .progress]
    static let hcg: [SidebarItem] = [.explore, .projects, .connect]
    static let account: [SidebarItem] = [.profile, .clientWorkspace, .settings]
}

/// Per-window navigation state, shared with menu commands through focus.
@MainActor
@Observable
final class NavigationModel {
    var selection: SidebarItem? = .home
    var orderFlowSymbol: MarketSymbol = .gc

    func open(_ area: PrimaryArea) {
        selection = area.defaultItem
    }

    func showOrderFlow(_ symbol: MarketSymbol) {
        orderFlowSymbol = symbol
        selection = .orderFlow
    }
}

struct NavigationFocusKey: FocusedValueKey {
    typealias Value = NavigationModel
}

extension FocusedValues {
    var navigation: NavigationModel? {
        get { self[NavigationFocusKey.self] }
        set { self[NavigationFocusKey.self] = newValue }
    }
}
