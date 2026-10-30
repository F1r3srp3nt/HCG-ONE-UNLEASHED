import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import SwiftUI

/// Home: development-build overview, simulated markets and the HCG ecosystem.
/// Shows no account, activity or server content — none exists in this build.
struct HomeView: View {
    @Environment(SimulationHost.self) private var simulation
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                buildNotice
                markets
                HStack(alignment: .top, spacing: 18) {
                    ecosystem
                    activity
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Home")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image("HCGLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(HCGColor.separator, lineWidth: 1))
                .accessibilityLabel("Hakmi Capital Group logo")
            VStack(alignment: .leading, spacing: 4) {
                HCGWordmark(size: 28)
                Text(HCGEcosystem.companyName)
                    .font(.callout)
                    .foregroundStyle(HCGColor.textSecondary)
            }
        }
    }

    private var buildNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hammer")
                .foregroundStyle(HCGColor.warning)
                .font(.system(size: 15, weight: .medium))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Development build — milestone M1")
                    .font(.headline)
                    .foregroundStyle(HCGColor.textPrimary)
                Text("This build runs entirely on this Mac. There is no sign-in, no HCG account data and no network connection. All market data is simulated.")
                    .font(.callout)
                    .foregroundStyle(HCGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .hcgPanel()
    }

    private var markets: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("Simulated markets", detail: simulation.isPlaying ? "Running · \(simulation.speed.label)" : "Paused") {
                SimulatedDataBadge()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(MarketSymbol.allCases) { symbol in
                    MarketCard(snapshot: simulation.frame[symbol]) {
                        navigation.showOrderFlow(symbol)
                    }
                }
            }
        }
    }

    private var ecosystem: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("HCG ecosystem")
            VStack(spacing: 0) {
                ForEach(HCGEcosystem.products) { product in
                    ProductRow(product: product)
                    if product.id != HCGEcosystem.products.last?.id { Divider() }
                }
            }
            .hcgPanel(padding: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("Your HCG activity")
            VStack(alignment: .leading, spacing: 10) {
                StatusBadge("Requires sign-in", tone: .unavailable, systemImage: "person.badge.key")
                Text("Authorized activity and notifications come from your HCG account. Sign-in is not part of this development build, so nothing is shown here.")
                    .font(.callout)
                    .foregroundStyle(HCGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hcgPanel()
        }
        .frame(width: 320, alignment: .topLeading)
    }
}

/// One simulated market, clickable to open it in Order Flow.
private struct MarketCard: View {
    let snapshot: MarketSnapshot
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        let decimals = snapshot.spec.priceDecimals
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(snapshot.symbol.ticker)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HCGColor.textPrimary)
                    Text(snapshot.spec.name)
                        .font(.caption)
                        .foregroundStyle(HCGColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(HCGColor.textSecondary)
                        .opacity(isHovered ? 1 : 0)
                }
                HStack(alignment: .firstTextBaseline) {
                    PriceText(PriceFormat.price(snapshot.last, decimals: decimals), size: 20, weight: .medium)
                    Spacer(minLength: 0)
                    PriceText(PriceFormat.change(snapshot.change, decimals: decimals), size: 12,
                              color: HCGColor.tone(for: snapshot.change))
                }
                HStack(spacing: 12) {
                    Text("Spread \(PriceFormat.price(snapshot.spread, decimals: decimals))")
                    Text("Vol \(snapshot.totalVolume.formatted())")
                }
                .font(HCGFont.value(11, weight: .regular))
                .foregroundStyle(HCGColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hcgPanel()
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(HCGColor.accent.opacity(isHovered ? 0.5 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(snapshot.symbol.ticker) in Order Flow")
        .accessibilityLabel("\(snapshot.symbol.ticker), simulated, last \(PriceFormat.price(snapshot.last, decimals: decimals))")
    }
}

private struct ProductRow: View {
    let product: HCGProduct

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HCGColor.textPrimary)
                Text(product.summary)
                    .font(.callout)
                    .foregroundStyle(HCGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(product.status.label, tone: product.status == .available ? .positive : .neutral)
                Text(product.platforms)
                    .font(.caption)
                    .foregroundStyle(HCGColor.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
