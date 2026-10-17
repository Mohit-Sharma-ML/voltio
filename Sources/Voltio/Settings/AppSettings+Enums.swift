import AppKit
import SwiftUI

/// Settings option enums (`AppSettings.PanelSection`, `AppSettings.Appearance`,
/// etc.), extracted from AppSettings.swift. Declared in an extension of
/// `AppSettings` so they stay nested — every existing
/// `AppSettings.PanelSection`-style reference is unchanged. Pure code motion
/// the @Observable stored properties
/// and their didSet wiring remain in the core file.
extension AppSettings {

    /// A reorderable card-group in the menu panel dropdown. The user drags
    /// these to change the stacking order; anything missing from the stored
    /// order (e.g. a section added in an update) appends at the end.
    enum PanelSection: String, CaseIterable, Identifiable, Codable {
        case batteryInfo
        case devices

        var id: String { rawValue }

        var label: String {
            switch self {
            case .batteryInfo: return "Battery Information"
            case .devices: return "Devices"
            }
        }

        var icon: String {
            switch self {
            case .batteryInfo: return "battery.100percent"
            case .devices: return "keyboard"  // devices: keyboards, mice, AirPods
            }
        }

        var detail: String {
            switch self {
            case .batteryInfo: return "Health, temperature, power flow"
            case .devices: return "Bluetooth accessories"
            }
        }
    }

    /// Menu-bar glyph size. Regular matches the system menu-bar text height;
    /// Large is the easiest to read at a glance.
    enum MenuBarIconSize: String, CaseIterable, Identifiable {
        case regular
        case large

        var id: String { rawValue }

        var label: String {
            switch self {
            case .regular: return "Regular"
            case .large: return "Large"
            }
        }

        var detail: String {
            switch self {
            case .regular: return "Standard menu-bar height"
            case .large: return "Taller glyph, easier to read"
            }
        }

        /// Glyph height in points for the live status item.
        var glyphHeight: CGFloat {
            switch self {
            case .regular: return 15
            case .large: return 20
            }
        }

        /// Height used by the settings preview strip.
        var previewHeight: CGFloat {
            switch self {
            case .regular: return 16
            case .large: return 22
            }
        }
    }

    /// The glyph drawn in the menu bar.
    enum MenuBarIconStyle: String, CaseIterable, Identifiable {
        case batteryIndicator
        case minimal
        case logo

        var id: String { rawValue }

        var label: String {
            switch self {
            case .batteryIndicator: return "Battery Indicator"
            case .minimal: return "Minimal"
            case .logo: return "Voltio Logo"
            }
        }

        var detail: String {
            switch self {
            case .batteryIndicator: return "Battery level and charging status"
            case .minimal: return "Just a clean battery glyph, no text"
            case .logo: return "Static Voltio bolt"
            }
        }
    }

    /// The value shown next to the icon.
    enum MenuBarValue: String, CaseIterable, Identifiable {
        case percentage
        case time
        case none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .percentage: return "Percentage"
            case .time: return "Time remaining"
            case .none: return "Nothing"
            }
        }
    }

    /// On-screen alert bubble size.
    enum BubbleSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Default"
            case .large: return "Large"
            }
        }
        var scale: CGFloat {
            switch self {
            case .small: return 0.9
            case .medium: return 1.0
            case .large: return 1.18
            }
        }
    }

    /// Strength of the screen-edge glow that accompanies an alert.
    enum GlowIntensity: String, CaseIterable, Identifiable {
        case off, subtle, standard, strong
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "Off"
            case .subtle: return "Subtle"
            case .standard: return "Default"
            case .strong: return "Strong"
            }
        }
        var multiplier: CGFloat {
            switch self {
            case .off: return 0
            case .subtle: return 0.55
            case .standard: return 1.0
            case .strong: return 1.6
            }
        }
    }

    /// App-wide color scheme: follow the system, or force Light/Dark.
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "Match System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        /// SwiftUI color scheme applied via `preferredColorScheme`;
        /// `nil` for `.system` so the system setting decides.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }

        /// AppKit appearance name applied via `NSApp.appearance`; `nil` for
        /// `.system` so windows inherit the system appearance.
        var nsAppearanceName: NSAppearance.Name? {
            switch self {
            case .system: return nil
            case .light: return .aqua
            case .dark: return .darkAqua
            }
        }
    }

    /// How often battery telemetry is polled.
    enum RefreshInterval: Int, CaseIterable, Identifiable {
        case fast = 2
        case normal = 5
        case relaxed = 10
        case slow = 30

        var id: Int { rawValue }
        var duration: Duration { .seconds(rawValue) }

        var label: String {
            switch self {
            case .fast: return "Every 2 seconds"
            case .normal: return "Every 5 seconds"
            case .relaxed: return "Every 10 seconds"
            case .slow: return "Every 30 seconds"
            }
        }
    }
}
