import HCGAppModel
import SwiftUI

// Destinations, the Go menu and per-window navigation state live in
// HCGKit/Sources/HCGAppModel (unit-tested). This file adapts them to SwiftUI.

extension PrimaryArea {
    /// ⌘ shortcut for the Go menu.
    var shortcut: KeyEquivalent { KeyEquivalent(shortcutDigit) }
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
