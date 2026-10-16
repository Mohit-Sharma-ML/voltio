import SwiftUI

/// What kind of crossing an alert watches for.
enum AlertCategory: String, Codable, Hashable, CaseIterable, Identifiable {
    case low
    case charged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low Battery Alerts"
        case .charged: return "Charged Alerts"
        }
    }

    /// Sensible default threshold for a brand-new rule of this kind.
    var defaultThreshold: Int { self == .low ? 20 : 80 }

    /// Allowed slider range for the threshold.
    var thresholdRange: ClosedRange<Double> {
        self == .low ? 5...50 : 50...100
    }
}

/// Where the on-screen alert bubble appears.
enum AlertPosition: String, Codable, Hashable, CaseIterable, Identifiable {
    case center
    case top

    var id: String { rawValue }

    var label: String { self == .center ? "Center of Screen" : "Top of Screen" }
    var shortLabel: String { self == .center ? "Center" : "Top" }
    var systemImage: String {
        self == .center ? "rectangle.center.inset.filled" : "rectangle.topthird.inset.filled"
    }
}

/// The accent color of an alert (bubble border + glyph + screen-edge glow).
enum AlertColor: String, Codable, Hashable, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        }
    }

    var nsColor: NSColor { NSColor(color) }
}

/// The sound played when an alert fires. System sounds ship with macOS; custom
/// sounds point at a user-imported audio file on disk (we're non-sandboxed).
enum AlertSound: Codable, Hashable {
    case none
    case system(String)
    case custom(String)   // absolute file path

    /// Built-in macOS system sounds offered in the picker, with friendly names.
    static let presets: [AlertSound] = [
        .none,
        .system("Sosumi"),
        .system("Funk"),
        .system("Glass"),
        .system("Hero"),
        .system("Submarine"),
        .system("Tink"),
        .system("Ping"),
    ]

    var label: String {
        switch self {
        case .none: return "No Sound"
        case .system(let name): return Self.friendlyNames[name] ?? name
        case .custom(let path):
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
    }

    private static let friendlyNames: [String: String] = [
        "Sosumi": "Critical",
        "Funk": "Warning",
        "Glass": "Alert",
        "Hero": "Success",
        "Submarine": "Deep",
        "Tink": "Gentle",
        "Ping": "Ping",
    ]

    var isNone: Bool { if case .none = self { return true } else { return false } }
}

/// One configurable battery alert: a threshold
/// plus how it's presented (color, on-screen position, sound, edge glow, and
/// whether it stays until dismissed).
struct BatteryAlertRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var category: AlertCategory
    var threshold: Int
    var color: AlertColor
    var position: AlertPosition
    var sound: AlertSound
    var borderGlow: Bool
    var persistent: Bool
    var enabled: Bool = true

    /// One-line summary shown on the collapsed card, e.g.
    /// "Center of Screen • Border Glow • Sound".
    var summary: String {
        var parts = [position.label]
        if borderGlow { parts.append("Border Glow") }
        if !sound.isNone { parts.append("Sound") }
        if persistent { parts.append("Persistent") }
        return parts.joined(separator: " • ")
    }

    static func new(_ category: AlertCategory) -> BatteryAlertRule {
        BatteryAlertRule(
            category: category,
            threshold: category.defaultThreshold,
            color: category == .low ? .orange : .green,
            position: .top,
            sound: category == .low ? .system("Funk") : .system("Glass"),
            borderGlow: false,
            persistent: false
        )
    }

    /// Default set seeded on first launch.
    static var defaults: [BatteryAlertRule] {
        [
            BatteryAlertRule(category: .low, threshold: 20, color: .orange,
                             position: .top, sound: .system("Funk"),
                             borderGlow: false, persistent: false),
            BatteryAlertRule(category: .low, threshold: 10, color: .red,
                             position: .center, sound: .system("Sosumi"),
                             borderGlow: true, persistent: false),
            BatteryAlertRule(category: .charged, threshold: 80, color: .green,
                             position: .top, sound: .system("Glass"),
                             borderGlow: true, persistent: false),
        ]
    }
}
