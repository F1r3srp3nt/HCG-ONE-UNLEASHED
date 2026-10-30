import HCGAppModel
import HCGDesignSystem
import HCGDomain
import SwiftUI

/// The main window: native sidebar navigation with the six primary areas.
struct MainWindow: View {
    @State private var navigation = NavigationModel()
    @SceneStorage("sidebarSelection") private var storedSelection = SidebarItem.home.rawValue
    @SceneStorage("orderFlowSymbol") private var storedSymbol = MarketSymbol.gc.rawValue

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $navigation.selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
        } detail: {
            NavigationStack {
                DetailView(item: navigation.selection ?? .home)
                    .safeAreaInset(edge: .top, spacing: 0) { SessionNoticeBanner() }
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .background(HCGColor.canvas)
        .environment(navigation)
        .focusedSceneValue(\.navigation, navigation)
        .onAppear(perform: restoreState)
        .onChange(of: navigation.selection) { _, item in
            if let item { storedSelection = item.rawValue }
        }
        .onChange(of: navigation.orderFlowSymbol) { _, symbol in
            storedSymbol = symbol.rawValue
        }
    }

    private func restoreState() {
        navigation.restore(selection: storedSelection, symbol: storedSymbol)
    }
}

private struct Sidebar: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            row(.home)

            Section("Trading") {
                ForEach(SidebarItem.trading) { row($0) }
            }

            Section("HCG") {
                ForEach(SidebarItem.hcg) { row($0) }
            }

            Section("Account") {
                ForEach(SidebarItem.account) { row($0) }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BuildFooter()
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        HCGSidebarLabel(item.title, systemImage: item.systemImage, isAvailable: item.isAvailableInThisBuild)
            .tag(item)
    }
}

private struct BuildFooter: View {
    var body: some View {
        // Stacked, not side by side: both badges together are wider than the
        // sidebar's minimum width and would clip.
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                StatusBadge("Dev build", tone: .warning)
                SimulatedDataBadge()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Routes a sidebar item to its screen.
private struct DetailView: View {
    let item: SidebarItem

    var body: some View {
        switch item {
        case .home:
            HomeView()
        case .simulate:
            SimulateView()
        case .orderFlow:
            OrderFlowView()
        case .settings:
            SettingsPage()
        case .learn, .marketLab, .progress, .explore, .projects, .connect, .profile, .clientWorkspace:
            UnavailableSectionView(item: item)
        }
    }
}
