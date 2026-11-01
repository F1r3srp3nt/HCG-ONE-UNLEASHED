import HCGCharting
import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// Candlestick chart of the simulated market: 1m–1D candles built from the
/// simulated trades, price overlays, a lower study, volume coloured by
/// delta, and your position and working orders as lines.
///
/// All geometry (visible candles, price scale, labels, hit-testing) comes
/// from `HCGCharting`, where it is unit-tested; this view only draws it.
struct CandleChartPanel: View {
    let symbol: MarketSymbol
    let history: ChartHistory
    let snapshot: MarketSnapshot
    let account: TradingAccount
    let isPreparingHistory: Bool
    @Binding var settings: ChartSettings

    /// Candles scrolled back from the newest (0 = following the live market).
    @State private var offset = 0
    @State private var dragStartOffset: Int?
    @State private var zoomStartVisible: Int?
    @State private var hover: CGPoint?
    /// Plot width when `hover` was recorded, to find the candle under it.
    @State private var hoverPlotWidth: Double = 0

    var body: some View {
        let candles = history[settings.timeframe].candles
        let studies = ChartStudies(candles: candles, settings: settings)
        let viewport = ChartViewport(candleCount: candles.count, visible: settings.visibleCandles, offsetFromLatest: offset)

        VStack(alignment: .leading, spacing: 8) {
            toolbar
            GeometryReader { geometry in
                let layout = ChartLayout(size: geometry.size, study: settings.study)
                let renderer = ChartRenderer(candles: candles, studies: studies, viewport: viewport, layout: layout,
                                             spec: snapshot.spec, settings: settings, snapshot: snapshot,
                                             account: account, hover: hover)
                Canvas { context, _ in renderer.draw(in: &context) }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hover = location
                            hoverPlotWidth = layout.plot.width
                        case .ended: hover = nil
                        }
                    }
                    .gesture(panGesture(slotWidth: layout.plot.width / Double(viewport.slots), candleCount: candles.count))
                    .simultaneousGesture(zoomGesture)
                    .overlay {
                        if candles.isEmpty {
                            Text(isPreparingHistory ? "Building simulated market history…" : "Waiting for simulated trades…")
                                .font(.callout)
                                .foregroundStyle(HCGColor.textSecondary)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isPreparingHistory && !candles.isEmpty {
                            ProgressView().controlSize(.small).padding(6)
                        }
                    }
            }
            readout(candles: candles, studies: studies, viewport: viewport)
        }
        .padding(14)
        .background(HCGColor.surface)
        .onChange(of: settings.timeframe) { offset = 0 }
        .onChange(of: symbol) { offset = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Simulated \(symbol.ticker) \(settings.timeframe.label) chart")
        .accessibilityValue("\(candles.count) candles, last \(PriceFormat.price(snapshot.last, decimals: snapshot.spec.priceDecimals))")
    }

    // MARK: Controls

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Timeframe", selection: $settings.timeframe) {
                ForEach(Timeframe.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Candle timeframe. Every timeframe is built from the same simulated trades.")

            Menu("Indicators") {
                Toggle("SMA (\(settings.smaPeriod))", isOn: $settings.showSMA)
                Toggle("EMA (\(settings.fastEMAPeriod))", isOn: $settings.showFastEMA)
                Toggle("EMA (\(settings.slowEMAPeriod))", isOn: $settings.showSlowEMA)
                Toggle("Bollinger Bands (20, 2)", isOn: $settings.showBollinger)
                Toggle("Session VWAP", isOn: $settings.showVWAP)
            }
            .fixedSize()

            Picker("Study", selection: $settings.study) {
                ForEach(ChartStudy.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Lower study pane")

            Spacer(minLength: 6)

            Button { zoom(by: 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Show more candles")
                .accessibilityLabel("Zoom out")
            Button { zoom(by: 0.8) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Show fewer candles")
                .accessibilityLabel("Zoom in")
            if offset > 0 {
                Button("Latest") { offset = 0 }
                    .help("Return to the newest candle")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private func zoom(by factor: Double) {
        var next = settings
        next.visibleCandles = Int((Double(settings.visibleCandles) * factor).rounded())
        settings = next.clamped()
    }

    /// Drag right to look back in time, left to come forward.
    private func panGesture(slotWidth: Double, candleCount: Int) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let start = dragStartOffset ?? offset
                dragStartOffset = start
                guard slotWidth > 0 else { return }
                let moved = Int((value.translation.width / slotWidth).rounded())
                offset = min(max(0, start + moved), max(0, candleCount - 1))
            }
            .onEnded { _ in dragStartOffset = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStartVisible ?? settings.visibleCandles
                zoomStartVisible = start
                var next = settings
                next.visibleCandles = Int((Double(start) / max(0.1, value.magnification)).rounded())
                settings = next.clamped()
            }
            .onEnded { _ in zoomStartVisible = nil }
    }

    // MARK: Readout

    /// OHLC, volume, delta and indicator values of the candle under the
    /// pointer, or of the newest candle.
    private func readout(candles: [Candle], studies: ChartStudies, viewport: ChartViewport) -> some View {
        let spec = snapshot.spec
        let index = hover.flatMap { viewport.index(atX: $0.x, width: hoverPlotWidth) } ?? candles.indices.last
        return HStack(spacing: 12) {
            if let index, candles.indices.contains(index) {
                let c = candles[index]
                Text(ChartText.time(c.start, settings.timeframe) + " UTC")
                    .foregroundStyle(HCGColor.textSecondary)
                Text("O \(ChartText.price(c.openTicks, spec))  H \(ChartText.price(c.highTicks, spec))  L \(ChartText.price(c.lowTicks, spec))  C \(ChartText.price(c.closeTicks, spec))")
                Text("Vol \(c.volume.formatted())")
                    .foregroundStyle(HCGColor.textSecondary)
                Text("Δ \(c.delta >= 0 ? "+" : "")\(c.delta.formatted())")
                    .foregroundStyle(HCGColor.tone(for: Double(c.delta)))
                Text(ChartText.studyReadout(studies, index: index, settings: settings, spec: spec))
                    .foregroundStyle(HCGColor.textSecondary)
                    .lineLimit(1)
            } else {
                Text("No candles yet").foregroundStyle(HCGColor.textSecondary)
            }
            Spacer(minLength: 0)
            SimulatedDataBadge()
        }
        .font(HCGFont.value(11, weight: .regular))
        .monospacedDigit()
        .lineLimit(1)
    }
}

// MARK: - Layout

/// Pane rectangles inside the canvas.
struct ChartLayout {
    static let axisWidth: Double = 64
    static let timeAxisHeight: Double = 16
    static let gap: Double = 6

    let size: CGSize
    let price: CGRect
    let volume: CGRect
    let study: CGRect?
    let timeAxis: CGRect
    /// Horizontal extent shared by every pane (excludes the price axis).
    let plot: CGRect

    init(size: CGSize, study: ChartStudy) {
        self.size = size
        let width = max(0, size.width - Self.axisWidth)
        let height = max(0, size.height - Self.timeAxisHeight)
        let studyHeight = study == .none ? 0 : max(60, height * 0.2)
        let volumeHeight = max(34, height * 0.13)
        let priceHeight = max(40, height - volumeHeight - studyHeight - Self.gap * (study == .none ? 1 : 2))
        price = CGRect(x: 0, y: 0, width: width, height: priceHeight)
        volume = CGRect(x: 0, y: price.maxY + Self.gap, width: width, height: volumeHeight)
        self.study = study == .none ? nil : CGRect(x: 0, y: volume.maxY + Self.gap, width: width, height: studyHeight)
        timeAxis = CGRect(x: 0, y: (self.study ?? volume).maxY, width: width, height: Self.timeAxisHeight)
        plot = CGRect(x: 0, y: 0, width: width, height: size.height)
    }
}

// MARK: - Text

enum ChartText {
    private static let clock = Date.FormatStyle(timeZone: .gmt).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    private static let day = Date.FormatStyle(timeZone: .gmt).day().month(.abbreviated)

    static func time(_ date: Date, _ timeframe: Timeframe) -> String {
        timeframe == .d1 ? date.formatted(day) : date.formatted(clock)
    }

    static func price(_ ticks: Int64, _ spec: InstrumentSpec) -> String {
        PriceFormat.price(spec.price(ticks: ticks), decimals: spec.priceDecimals)
    }

    static func price(ticks: Double, _ spec: InstrumentSpec) -> String {
        PriceFormat.price(spec.price(fractionalTicks: ticks), decimals: spec.priceDecimals)
    }

    static func studyReadout(_ s: ChartStudies, index i: Int, settings: ChartSettings, spec: InstrumentSpec) -> String {
        var parts: [String] = []
        func add(_ name: String, _ v: Double?) { if let v { parts.append("\(name) \(price(ticks: v, spec))") } }
        add("SMA", s.sma[safe: i] ?? nil)
        add("EMA\(settings.fastEMAPeriod)", s.fastEMA[safe: i] ?? nil)
        add("EMA\(settings.slowEMAPeriod)", s.slowEMA[safe: i] ?? nil)
        add("VWAP", s.vwap[safe: i] ?? nil)
        switch settings.study {
        case .rsi: if let v = s.rsi[safe: i] ?? nil { parts.append(String(format: "RSI %.1f", v)) }
        case .macd:
            if let m = s.macd, let line = m.macd[safe: i] ?? nil {
                let ticks = spec.tickSize
                parts.append(String(format: "MACD %.2f / %.2f", line * ticks, ((m.signal[safe: i] ?? nil) ?? 0) * ticks))
            }
        case .atr: if let v = s.atr[safe: i] ?? nil { parts.append("ATR \(PriceFormat.price(v * spec.tickSize, decimals: spec.priceDecimals))") }
        case .none: break
        }
        return parts.joined(separator: "  ")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
