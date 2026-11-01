import HCGCharting
import HCGDesignSystem
import HCGDomain
import HCGMarketSim
import HCGTrading
import SwiftUI

/// Draws the candle chart into a `Canvas`. Holds only values; all geometry
/// comes from `ChartLayout`, `ChartViewport` and `PriceScale`.
struct ChartRenderer {
    let candles: [Candle]
    let studies: ChartStudies
    let viewport: ChartViewport
    let layout: ChartLayout
    let spec: InstrumentSpec
    let settings: ChartSettings
    let snapshot: MarketSnapshot
    let account: TradingAccount
    let hover: CGPoint?

    private var visible: Range<Int> { viewport.range }
    private var slotWidth: Double { layout.plot.width / Double(viewport.slots) }
    private var bodyWidth: Double { max(1, slotWidth * 0.64) }

    private func x(_ index: Int) -> Double { viewport.x(of: index, width: layout.plot.width) }

    /// Your simulated position and working orders on this market, as price levels.
    private var orderLevels: [(ticks: Double, label: String, color: Color)] {
        var levels: [(ticks: Double, label: String, color: Color)] = []
        if let p = account.position(snapshot.symbol) {
            levels.append((Double(spec.ticks(price: p.averagePrice)),
                           "\(p.isLong ? "Long" : "Short") \(abs(p.quantity))", p.isLong ? HCGColor.bid : HCGColor.ask))
        }
        for o in account.openOrders(for: snapshot.symbol) where o.status != .accepted {
            guard let ticks = o.stopTicks ?? o.limitTicks else { continue }
            let kind = o.role == .entry ? (o.type == .stop ? "STP" : "LMT") : (o.role == .stopLoss ? "SL" : "TP")
            levels.append((Double(ticks), "\(o.side == .buy ? "Buy" : "Sell") \(o.remainingQuantity) \(kind)",
                           o.side == .buy ? HCGColor.bid : HCGColor.ask))
        }
        return levels
    }

    private var priceScale: PriceScale {
        var values: [Double] = []
        for i in visible {
            values.append(Double(candles[i].highTicks))
            values.append(Double(candles[i].lowTicks))
        }
        values += studies.overlayValues(in: visible)
        if values.isEmpty { values = [Double(snapshot.bidTicks), Double(snapshot.askTicks)] }
        values.append(Double(snapshot.lastTicks))
        return PriceScale(fitting: values, minimumTicks: 8)
    }

    func draw(in context: inout GraphicsContext) {
        guard layout.plot.width > 20, layout.price.height > 20 else { return }
        let scale = priceScale
        drawPriceGrid(&context, scale)
        drawTimeAxis(&context)
        var price = context
        price.clip(to: Path(layout.price))
        drawBollinger(&price, scale)
        drawCandles(&price, scale)
        drawOverlays(&price, scale)
        drawLevels(&price, scale)
        drawLast(&context, scale)
        drawVolume(&context)
        if let rect = layout.study { drawStudy(&context, rect) }
        drawCrosshair(&context, scale)
    }

    // MARK: Price pane

    private func drawPriceGrid(_ context: inout GraphicsContext, _ scale: PriceScale) {
        let count = max(3, Int(layout.price.height / 46))
        for ticks in scale.labels(count: count, tickSize: spec.tickSize) {
            let y = scale.y(ticks, height: layout.price.height)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: layout.plot.width, y: y))
            context.stroke(line, with: .color(HCGColor.separator.opacity(0.6)), lineWidth: 0.5)
            context.draw(label(ChartText.price(ticks: ticks, spec), color: HCGColor.textSecondary),
                         at: CGPoint(x: layout.plot.width + 6, y: y), anchor: .leading)
        }
    }

    private func drawCandles(_ context: inout GraphicsContext, _ scale: PriceScale) {
        let h = layout.price.height
        for i in visible {
            let c = candles[i]
            let cx = x(i)
            let color = c.isUp ? HCGColor.gain : HCGColor.loss
            var wick = Path()
            wick.move(to: CGPoint(x: cx, y: scale.y(Double(c.highTicks), height: h)))
            wick.addLine(to: CGPoint(x: cx, y: scale.y(Double(c.lowTicks), height: h)))
            context.stroke(wick, with: .color(color), lineWidth: 1)
            let top = scale.y(Double(max(c.openTicks, c.closeTicks)), height: h)
            let bottom = scale.y(Double(min(c.openTicks, c.closeTicks)), height: h)
            let body = CGRect(x: cx - bodyWidth / 2, y: top, width: bodyWidth, height: max(1, bottom - top))
            context.fill(Path(body), with: .color(color.opacity(c.isUp ? 0.85 : 0.9)))
        }
    }

    private func drawOverlays(_ context: inout GraphicsContext, _ scale: PriceScale) {
        line(&context, studies.sma, scale, layout.price, color: HCGColor.info)
        line(&context, studies.fastEMA, scale, layout.price, color: HCGColor.warning)
        line(&context, studies.slowEMA, scale, layout.price, color: HCGColor.accent)
        line(&context, studies.vwap, scale, layout.price, color: HCGColor.vwap, dash: [4, 3])
    }

    private func drawBollinger(_ context: inout GraphicsContext, _ scale: PriceScale) {
        guard let bands = studies.bollinger else { return }
        var area = Path()
        let points = visible.compactMap { i -> (Double, Double, Double)? in
            guard let u = bands.upper[i], let l = bands.lower[i] else { return nil }
            return (x(i), scale.y(u, height: layout.price.height), scale.y(l, height: layout.price.height))
        }
        if let first = points.first {
            area.move(to: CGPoint(x: first.0, y: first.1))
            for p in points.dropFirst() { area.addLine(to: CGPoint(x: p.0, y: p.1)) }
            for p in points.reversed() { area.addLine(to: CGPoint(x: p.0, y: p.2)) }
            area.closeSubpath()
            context.fill(area, with: .color(HCGColor.info.opacity(0.07)))
        }
        line(&context, bands.upper, scale, layout.price, color: HCGColor.info.opacity(0.6))
        line(&context, bands.lower, scale, layout.price, color: HCGColor.info.opacity(0.6))
    }

    /// Position and working orders: dashed lines with a label on the axis.
    private func drawLevels(_ clipped: inout GraphicsContext, _ scale: PriceScale) {
        for level in orderLevels where level.ticks >= scale.lowTicks && level.ticks <= scale.highTicks {
            let y = scale.y(level.ticks, height: layout.price.height)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: layout.plot.width, y: y))
            clipped.stroke(path, with: .color(level.color.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
            clipped.draw(label(level.label, color: level.color), at: CGPoint(x: 6, y: y - 7), anchor: .leading)
        }
    }

    private func drawLast(_ context: inout GraphicsContext, _ scale: PriceScale) {
        let ticks = Double(snapshot.lastTicks)
        guard ticks >= scale.lowTicks && ticks <= scale.highTicks else { return }
        let y = scale.y(ticks, height: layout.price.height)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: layout.plot.width, y: y))
        context.stroke(path, with: .color(HCGColor.lastTrade.opacity(0.35)), lineWidth: 1)
        let tag = CGRect(x: layout.plot.width + 2, y: y - 8, width: ChartLayout.axisWidth - 4, height: 16)
        context.fill(Path(roundedRect: tag, cornerRadius: 3), with: .color(HCGColor.accent))
        context.draw(label(ChartText.price(snapshot.lastTicks, spec), color: HCGColor.onAccent, weight: .semibold),
                     at: CGPoint(x: tag.minX + 4, y: y), anchor: .leading)
    }

    // MARK: Volume pane

    /// Volume bars coloured by the candle's delta (buyers vs sellers).
    private func drawVolume(_ context: inout GraphicsContext) {
        let rect = layout.volume
        let maxVolume = visible.map { candles[$0].volume }.max() ?? 0
        context.draw(label("Vol · Δ", color: HCGColor.textSecondary), at: CGPoint(x: 4, y: rect.minY + 6), anchor: .leading)
        guard maxVolume > 0 else { return }
        for i in visible {
            let c = candles[i]
            let height = Double(c.volume) / Double(maxVolume) * (rect.height - 2)
            let bar = CGRect(x: x(i) - bodyWidth / 2, y: rect.maxY - height, width: bodyWidth, height: height)
            context.fill(Path(bar), with: .color((c.delta >= 0 ? HCGColor.gain : HCGColor.loss).opacity(0.55)))
        }
    }

    // MARK: Study pane

    private func drawStudy(_ context: inout GraphicsContext, _ rect: CGRect) {
        var pane = context
        pane.clip(to: Path(rect))
        var top = Path()
        top.move(to: CGPoint(x: 0, y: rect.minY))
        top.addLine(to: CGPoint(x: layout.plot.width, y: rect.minY))
        context.stroke(top, with: .color(HCGColor.separator), lineWidth: 0.5)
        context.draw(label(settings.study.label, color: HCGColor.textSecondary), at: CGPoint(x: 4, y: rect.minY + 8), anchor: .leading)

        switch settings.study {
        case .none:
            return
        case .rsi:
            let scale = PriceScale(lowTicks: 0, highTicks: 100)
            for guide in [30.0, 70.0] { horizontal(&pane, y: rect.minY + scale.y(guide, height: rect.height), HCGColor.separator) }
            line(&pane, studies.rsi, scale, rect, color: HCGColor.info)
            axisLabels(&context, rect, scale, values: [30, 70]) { String(format: "%.0f", $0) }
        case .macd:
            guard let m = studies.macd else { return }
            let values = visible.flatMap { [m.macd[$0], m.signal[$0], m.histogram[$0]].compactMap { $0 } }
            let extent = max(values.map(abs).max() ?? 1, 1e-9)
            let scale = PriceScale(lowTicks: -extent * 1.1, highTicks: extent * 1.1)
            let zero = scale.y(0, height: rect.height)
            horizontal(&pane, y: rect.minY + zero, HCGColor.separator)
            for i in visible {
                guard let h = m.histogram[i] else { continue }
                let y = rect.minY + scale.y(h, height: rect.height)
                let bar = CGRect(x: x(i) - bodyWidth / 2, y: min(y, rect.minY + zero), width: bodyWidth, height: abs(y - (rect.minY + zero)))
                pane.fill(Path(bar), with: .color((h >= 0 ? HCGColor.gain : HCGColor.loss).opacity(0.5)))
            }
            line(&pane, m.macd, scale, rect, color: HCGColor.info)
            line(&pane, m.signal, scale, rect, color: HCGColor.warning)
            axisLabels(&context, rect, scale, values: [0]) { _ in "0" }
        case .atr:
            let values = visible.compactMap { studies.atr[$0] }
            let scale = PriceScale(fitting: values, minimumTicks: 1)
            line(&pane, studies.atr, scale, rect, color: HCGColor.info)
            axisLabels(&context, rect, scale, values: values.isEmpty ? [] : [values.max()!]) {
                PriceFormat.price($0 * spec.tickSize, decimals: spec.priceDecimals)
            }
        }
    }

    // MARK: Time axis and crosshair

    private func drawTimeAxis(_ context: inout GraphicsContext) {
        guard !visible.isEmpty else { return }
        let every = max(1, Int((90 / slotWidth).rounded(.up)))
        for i in visible where (viewport.slot(of: i)) % every == 0 {
            context.draw(label(ChartText.time(candles[i].start, settings.timeframe), color: HCGColor.textSecondary),
                         at: CGPoint(x: x(i), y: layout.timeAxis.midY), anchor: .center)
        }
    }

    private func drawCrosshair(_ context: inout GraphicsContext, _ scale: PriceScale) {
        guard let hover, hover.x < layout.plot.width, let index = viewport.index(atX: hover.x, width: layout.plot.width) else { return }
        let cx = x(index)
        var vertical = Path()
        vertical.move(to: CGPoint(x: cx, y: 0))
        vertical.addLine(to: CGPoint(x: cx, y: layout.timeAxis.minY))
        context.stroke(vertical, with: .color(HCGColor.textSecondary.opacity(0.5)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
        guard layout.price.contains(hover) else { return }
        horizontal(&context, y: hover.y, HCGColor.textSecondary.opacity(0.5))
        let ticks = scale.ticks(atY: hover.y, height: layout.price.height)
        let tag = CGRect(x: layout.plot.width + 2, y: hover.y - 8, width: ChartLayout.axisWidth - 4, height: 16)
        context.fill(Path(roundedRect: tag, cornerRadius: 3), with: .color(HCGColor.surfaceRaised))
        context.draw(label(ChartText.price(ticks: ticks.rounded(), spec), color: HCGColor.textPrimary),
                     at: CGPoint(x: tag.minX + 4, y: hover.y), anchor: .leading)
    }

    // MARK: Helpers

    /// A series as a line, broken where it has no value.
    private func line(_ context: inout GraphicsContext, _ series: [Double?], _ scale: PriceScale, _ rect: CGRect,
                      color: Color, dash: [CGFloat] = []) {
        var path = Path()
        var drawing = false
        for i in visible {
            guard i < series.count, let v = series[i] else {
                drawing = false
                continue
            }
            let point = CGPoint(x: x(i), y: rect.minY + scale.y(v, height: rect.height))
            if drawing { path.addLine(to: point) } else { path.move(to: point) }
            drawing = true
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round, dash: dash))
    }

    /// Dashed horizontal line at canvas y-coordinate `y`.
    private func horizontal(_ context: inout GraphicsContext, y: Double, _ color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: layout.plot.width, y: y))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
    }

    private func axisLabels(_ context: inout GraphicsContext, _ rect: CGRect, _ scale: PriceScale,
                            values: [Double], format: (Double) -> String) {
        for v in values {
            context.draw(label(format(v), color: HCGColor.textSecondary),
                         at: CGPoint(x: layout.plot.width + 6, y: rect.minY + scale.y(v, height: rect.height)), anchor: .leading)
        }
    }

    private func label(_ text: String, color: Color, weight: Font.Weight = .regular) -> Text {
        Text(text).font(.system(size: 10, weight: weight).monospacedDigit()).foregroundStyle(color)
    }
}
