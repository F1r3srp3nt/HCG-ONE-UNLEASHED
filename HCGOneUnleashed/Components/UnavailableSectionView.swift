import HCGAppModel
import HCGDesignSystem
import SwiftUI

/// Honest placeholder for a destination that is not implemented in this
/// development build. It names what is missing and what it depends on —
/// it never shows sample or invented content. The text comes from
/// `SidebarItem.developmentNote` (HCGAppModel, unit-tested).
struct UnavailableSectionView: View {
    let item: SidebarItem
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        let note = item.developmentNote
        ScrollView {
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

                if let note {
                    Text(note.summary)
                        .font(.callout)
                        .foregroundStyle(HCGColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(note.details, id: \.self) { line in
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
                }

                if item.area == .trading {
                    Button("Open Order Flow") { navigation.selection = .orderFlow }
                        .buttonStyle(HCGButtonStyle(.primary))
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(item.title)
    }
}
