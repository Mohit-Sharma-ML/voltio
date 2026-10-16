import PowerCore
import SwiftUI
import WidgetKit

@main
struct VoltioWidgetsBundle: WidgetBundle {
    /// Must match the widget Info.plist's bundle identifier suffix and the
    /// kinds used by the individual widgets.
    static let smallKind = "VoltioBatterySmall"
    static let mediumKind = "VoltioBatteryMedium"

    var body: some Widget {
        BatterySmallWidget()
        BatteryMediumWidget()
    }
}
