import SwiftUI

/// Power-flow diagram: the wall adapter on the left feeds two animated "liquid"
/// gauges (charge into the battery + system load), which terminate in the
/// battery and Mac on the right. On battery, it collapses to Battery ──▶ Mac.
struct PowerFlowView: View {
    let flow: PowerFlow

    private let barHeight: CGFloat = 56
    private let barSpacing: CGFloat = 8
    private let tileWidth: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            diagram
            summary
        }
    }

    // MARK: - Diagram

    @ViewBuilder
    private var diagram: some View {
        if flow.isPluggedIn {
            chargingDiagram
        } else {
            dischargingDiagram
        }
    }

    /// Adapter ─▶ [battery gauge / system gauge] ─▶ [battery icon / Mac icon].
    private var chargingDiagram: some View {
        let fullHeight = barHeight * 2 + barSpacing
        let scale = gaugeScale
        return HStack(spacing: 8) {
            sourceTile(
                icon: "powerplug.fill",
                label: adapterLabel,
                tint: .secondary,
                height: fullHeight
            )

            VStack(spacing: barSpacing) {
                LiquidBar(
                    watts: max(0, flow.batteryWatts),
                    fill: clampFill(max(0, flow.batteryWatts) / scale),
                    tint: .green,
                    emptyLabel: flow.isCharging ? nil : "Not charging"
                )
                .frame(height: barHeight)

                LiquidBar(
                    watts: flow.systemWatts,
                    fill: clampFill(flow.systemWatts / scale),
                    tint: Color(white: 0.78),
                    emptyLabel: nil
                )
                .frame(height: barHeight)
            }

            VStack(spacing: barSpacing) {
                deviceTile(
                    icon: flow.isCharging ? "battery.100percent.bolt" : "battery.100percent",
                    tint: flow.isCharging ? .green : .secondary,
                    height: barHeight,
                    label: "\(flow.batteryPercent)%"
                )
                deviceTile(icon: "laptopcomputer", tint: .secondary, height: barHeight)
            }
        }
    }

    /// Battery ─▶ system gauge ─▶ Mac.
    private var dischargingDiagram: some View {
        let h = barHeight * 2 + barSpacing
        return HStack(spacing: 8) {
            sourceTile(
                icon: batteryIcon(flow.batteryPercent, charging: false),
                label: "\(flow.batteryPercent)%",
                tint: .orange,
                height: h
            )
            LiquidBar(
                watts: flow.systemWatts,
                fill: clampFill(flow.systemWatts / 35.0),
                tint: .orange,
                emptyLabel: nil
            )
            .frame(height: h)
            deviceTile(icon: "laptopcomputer", tint: .secondary, height: h)
        }
    }

    // MARK: - Tiles

    private func sourceTile(icon: String, label: String, tint: Color, height: CGFloat) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: tileWidth, height: height)
        .background(tileBackground)
    }

    private func deviceTile(icon: String, tint: Color, height: CGFloat, label: String? = nil) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: tileWidth - 6, height: height)
        .background(tileBackground)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07))
            )
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: summaryIcon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(summaryTint)
                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Text(usageHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryIcon: String {
        if flow.isCharging { return "bolt.fill" }
        if flow.isPluggedIn { return "powerplug.fill" }
        return "battery.50percent"
    }

    private var summaryTint: Color {
        flow.isCharging ? .green : (flow.isPluggedIn ? .teal : .orange)
    }

    private var summaryText: String {
        if flow.isFullyCharged { return "Fully charged" }
        if flow.isCharging {
            return "Charging at \(Int(max(0, flow.batteryWatts).rounded())) W"
        }
        if flow.isPluggedIn { return "Plugged in · not charging" }
        return "On battery · \(Int(flow.systemWatts.rounded())) W"
    }

    private var usageHint: String {
        switch flow.systemWatts {
        case ..<8: return "Light workload: sipping power"
        case ..<22: return "Normal workload: comfortably within range"
        default: return "Heavy workload: running warm"
        }
    }

    // MARK: - Helpers

    private var adapterLabel: String {
        if let w = flow.adapterRatedWatts, w > 0 { return "\(w)W" }
        if flow.adapterWatts > 0 { return "\(Int(flow.adapterWatts.rounded()))W" }
        return "AC"
    }

    /// Per-gauge scale so a near-maxed adapter reads almost full,
    /// while a charger with headroom shows lower levels. Splits the adapter's
    /// rated/observed budget across the two streams.
    private var gaugeScale: Double {
        let budget = max(Double(flow.adapterRatedWatts ?? 0), flow.adapterWatts, 1)
        return max(budget * 0.5, max(0, flow.batteryWatts), flow.systemWatts, 1)
    }

    private func clampFill(_ value: Double) -> Double {
        min(1.0, max(0.05, value))
    }

    private func batteryIcon(_ pct: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch pct {
        case ...10: return "battery.0percent"
        case ...30: return "battery.25percent"
        case ...55: return "battery.50percent"
        case ...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Liquid gauge

/// A horizontal "tank" that fills from the left to `fill`, with a gently
/// animated wavy surface and the wattage centered on top.
private struct LiquidBar: View {
    let watts: Double
    let fill: Double          // 0...1
    let tint: Color
    var emptyLabel: String?   // shown instead of watts when there's no flow

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.035))

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate * 2.2
                    WaveShape(progress: fill, phase: phase, amplitude: 2.4)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.55), tint.opacity(0.22)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(
                            WaveShape(progress: fill, phase: phase, amplitude: 2.4)
                                .stroke(tint.opacity(0.7), lineWidth: 1)
                        )
                        .frame(width: w, height: h)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(label)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
        }
    }

    private var label: String {
        if watts < 0.05, let emptyLabel { return emptyLabel }
        return Format.watts(watts)
    }
}

/// Fills a rect from the left edge to `progress`, with a vertical sine wave
/// forming the liquid's surface on the trailing edge.
private struct WaveShape: Shape {
    var progress: Double
    var phase: Double
    var amplitude: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let level = rect.width * CGFloat(min(1, max(0, progress)))
        let steps = 28

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        // Walk up the wavy trailing surface from bottom to top.
        for i in stride(from: steps, through: 0, by: -1) {
            let frac = Double(i) / Double(steps)
            let y = rect.height * CGFloat(frac)
            let x = level + CGFloat(sin(frac * .pi * 2 + phase) * amplitude)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}
