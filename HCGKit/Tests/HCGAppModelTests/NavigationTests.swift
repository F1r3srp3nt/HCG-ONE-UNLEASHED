import Foundation
import Testing
import HCGDomain
@testable import HCGAppModel

@Suite("Navigation model")
struct NavigationTests {
    @Test("Every destination belongs to exactly one sidebar group or is Home")
    func sidebarGroupsCoverEveryDestination() {
        let grouped = [SidebarItem.home] + SidebarItem.trading + SidebarItem.hcg + SidebarItem.account
        #expect(Set(grouped) == Set(SidebarItem.allCases))
        #expect(grouped.count == SidebarItem.allCases.count, "no destination listed twice")
        #expect(SidebarItem.trading.allSatisfy { $0.area == .trading })
        #expect(SidebarItem.account.allSatisfy { $0.area == .account })
    }

    @Test("The founder-specified destinations are all present, in order")
    func requiredDestinations() {
        #expect(SidebarItem.trading.map(\.title) == ["Learn", "Simulate", "Order Flow", "Market Lab", "Progress"])
        #expect(SidebarItem.hcg.map(\.title) == ["Explore", "Projects", "HCG Connect"])
        #expect(SidebarItem.account.map(\.title) == ["Profile", "Client Workspace", "Settings"])
    }

    @Test("Executive Workspace is never listed without server verification")
    func noExecutiveWorkspace() {
        #expect(!SidebarItem.allCases.contains { $0.title.localizedCaseInsensitiveContains("executive") })
    }

    @Test("Only implemented destinations are marked available; every other one explains why")
    func availabilityIsHonest() {
        let available = Set(SidebarItem.allCases.filter(\.isAvailableInThisBuild))
        #expect(available == [.home, .simulate, .orderFlow, .settings])
        for item in SidebarItem.allCases where !item.isAvailableInThisBuild {
            guard let note = item.developmentNote else {
                Issue.record("\(item) is unavailable but has no development note")
                continue
            }
            #expect(!note.summary.isEmpty, "\(item) needs a summary")
            #expect(!note.details.isEmpty, "\(item) needs details")
            #expect(note.details.contains { $0.contains("M2") || $0.contains("M3") || $0.contains("M4") || $0.contains("M5") },
                    "\(item) must name the milestone it depends on")
        }
    }

    @Test("Go menu: six areas, unique ⌘ digits 1–6, each opening a destination in its area")
    func goMenu() {
        #expect(PrimaryArea.allCases.count == 6)
        #expect(PrimaryArea.allCases.map(\.shortcutDigit) == ["1", "2", "3", "4", "5", "6"])
        for area in PrimaryArea.allCases {
            #expect(area.defaultItem.area == area)
        }
        #expect(PrimaryArea.trading.defaultItem == .orderFlow, "Trading opens the working screen")
    }

    @Test("Opening areas and markets updates the selection")
    @MainActor
    func navigationActions() {
        let model = NavigationModel()
        #expect(model.selection == .home)
        model.open(.connect)
        #expect(model.selection == .connect)
        model.showOrderFlow(.cl)
        #expect(model.selection == .orderFlow)
        #expect(model.orderFlowSymbol == .cl)
    }

    @Test("Restoring saved state accepts valid values and falls back on invalid ones")
    @MainActor
    func restore() {
        let model = NavigationModel()
        model.restore(selection: "marketLab", symbol: "nq")
        #expect(model.selection == .marketLab)
        #expect(model.orderFlowSymbol == .nq)
        model.restore(selection: "executiveWorkspace", symbol: "btc")
        #expect(model.selection == .home)
        #expect(model.orderFlowSymbol == .gc)
        model.restore(selection: nil, symbol: nil)
        #expect(model.selection == .home)
    }
}
