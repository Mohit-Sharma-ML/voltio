import SwiftUI
import PowerCore

/// UI presentation for peripherals, kept out of `PowerCore` so the library stays
/// SwiftUI-free.
extension PeripheralKind {
    var symbol: String {
        switch self {
        case .airpods: return "airpods"
        case .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .headphones: return "headphones"
        case .magicMouse: return "magicmouse.fill"
        case .mouse: return "computermouse.fill"
        case .magicKeyboard, .keyboard: return "keyboard.fill"
        case .magicTrackpad, .trackpad: return "rectangle.fill"
        case .gameController: return "gamecontroller.fill"
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .watch: return "applewatch"
        case .mac: return "laptopcomputer"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

extension BatteryReading {
    var tint: Color { batteryTint(percent) }
}

extension PeripheralDevice {
    /// Headline tint based on the lowest compartment.
    var tint: Color { batteryTint(minPercent ?? 0) }
}

/// Battery-level color used across device rows.
func batteryTint(_ percent: Int) -> Color {
    switch percent {
    case ...10: return .red
    case ...20: return .orange
    case ...50: return .yellow
    default: return .green
    }
}
