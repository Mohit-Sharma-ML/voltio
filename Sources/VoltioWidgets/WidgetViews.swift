import PowerCore
import SwiftUI

/// Shared visual vocabulary with the in-app panel (DesignSystem lives in the
/// app target, so the widget keeps its own small copy of the accents).
enum WidgetTheme {
    static let green = Color(red: 0.22, green: 0.78, blue: 0.42)
    static let teal = Color(red: 0.13, green: 0.72, blue: 0.70)
    static let orange = Color(red: 0.95, green: 0.58, blue: 0.18)
    static let red = Color(red: 0.92, green: 0.30, blue: 0.28)

    /// Percentage color follows the app's alert semantics.
    static func tint(for snapshot: WidgetSnapshot) -> Color {
        if snapshot.isCharging { return green }
        if snapshot.percentage <= 20 { return red }
        if snapshot.percentage <= 40 { return orange }
        return snapshot.isPluggedIn ? teal : green
    }
}

/// Small-family content: progress ring with the percentage in the middle,
/// status caption underneath.
struct BatteryRingView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.02, Double(snapshot.percentage) / 100))
                .stroke(
                    WidgetTheme.tint(for: snapshot),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            // Single-line "NN%", constrained INSIDE the ring's stroke: the
            // frame caps the text at (ring width − horizontal padding), and
            // minimumScaleFactor shrinks "100%" rather than letting the
            // glyphs cross the circle.
            Text("\(snapshot.percentage)%")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Content shared by both families (the medium layout nests this next to the
/// energy column).
struct BatteryCoreView: View {
    let snapshot: WidgetSnapshot
    /// Caps the ring so it never fills the full column height; the small
    /// family passes a larger cap since it has the whole widget to itself.
    var ringMaxSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            BatteryRingView(snapshot: snapshot)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: ringMaxSize, maxHeight: ringMaxSize)
                .frame(maxWidth: .infinity)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(WidgetTheme.tint(for: snapshot))
                        .frame(width: 6, height: 6)
                    Text(snapshot.statusText)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let time = snapshot.timeRemainingText {
                    Text(time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Energy column for the medium family: today's Wh total + current draw,
/// mirroring the panel's energy card formatting ("21.3 Wh", "12.0 W avg").
struct EnergyColumnView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let wh = snapshot.energyTodayWh {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ENERGY TODAY")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1f Wh", wh))
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(WidgetTheme.teal)
                        .monospacedDigit()
                    if let minutes = snapshot.energySampledMinutes, minutes >= 2 {
                        Text(String(format: "%.0f min sampled", minutes))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Divider()
            if let systemWatts = snapshot.systemPowerWatts {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SYSTEM DRAW")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1f W", systemWatts))
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    if let adapter = snapshot.adapterWatts {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(WidgetTheme.orange)
                            Text("\(adapter) W adapter\(snapshot.adapterName.map { " · \($0)" } ?? "")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown when the widget has no payload yet (app not run since the widget was
/// added, or App Group mismatch).
struct WaitingForAppView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.badge.clock")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Waiting for Voltio")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Launch the app to start feeding live battery data.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
