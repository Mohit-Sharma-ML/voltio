import PowerCore
import SwiftUI
import WidgetKit

/// systemSmall: the battery ring, centered, with status caption.
struct BatterySmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VoltioWidgetsBundle.smallKind, provider: VoltioTimelineProvider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Battery")
        .description("Battery level, charge state and time remaining.")
        .supportedFamilies([.systemSmall])
    }
}

/// systemMedium: battery ring on the left; energy today + system draw column
/// on the right (the panel's energy-card look).
struct BatteryMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VoltioWidgetsBundle.mediumKind, provider: VoltioTimelineProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Battery + Energy")
        .description("Battery state alongside today's energy use and current system draw.")
        .supportedFamilies([.systemMedium])
    }
}

/// Container background + a staleness cue: when the app hasn't published in
/// over an hour (Voltio quit, Mac asleep), dim the content so the user can
/// tell the numbers aren't live.
private struct WidgetChrome: ViewModifier {
    let isStale: Bool

    func body(content: Content) -> some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .opacity(isStale ? 0.55 : 1)
    }
}

private struct SmallWidgetView: View {
    let entry: BatteryEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                BatteryCoreView(snapshot: snapshot)
            } else {
                WaitingForAppView()
            }
        }
        .padding(12)
        .modifier(WidgetChrome(isStale: entry.isStale))
    }
}

private struct MediumWidgetView: View {
    let entry: BatteryEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                HStack(spacing: 16) {
                    BatteryCoreView(snapshot: snapshot, ringMaxSize: 92)
                        .frame(maxWidth: .infinity)
                    Divider()
                    EnergyColumnView(snapshot: snapshot)
                        .frame(maxWidth: .infinity)
                }
            } else {
                WaitingForAppView()
            }
        }
        .padding(14)
        .modifier(WidgetChrome(isStale: entry.isStale))
    }
}

private extension BatteryEntry {
    /// Payload older than an hour counts as stale — the app republishes every
    /// 5 s while running, so this only trips when Voltio isn't running.
    var isStale: Bool {
        guard let snapshot else { return false }
        return Date().timeIntervalSince(snapshot.timestamp) > 60 * 60
    }
}
