import AppKit
import Foundation
import PowerCore
import SwiftUI

/// Sample alert variants offered by the General "Preview" control so the user can
/// see how each severity reads on screen.
enum AlertPreviewKind: String, CaseIterable, Identifiable {
    case charged   // green
    case low       // orange
    case critical  // red

    var id: String { rawValue }

    var color: AlertColor {
        switch self {
        case .charged:  return .green
        case .low:      return .orange
        case .critical: return .red
        }
    }

    var label: String {
        switch self {
        case .charged:  return "Charged"
        case .low:      return "Low"
        case .critical: return "Critical"
        }
    }

    var title: String {
        switch self {
        case .charged:  return "Fully Charged"
        case .low:      return "Low Battery"
        case .critical: return "Battery Critical"
        }
    }

    var subtitle: String {
        switch self {
        case .charged:  return "100% — you can unplug"
        case .low:      return "20% remaining"
        case .critical: return "10% — plug in now"
        }
    }

    var icon: String {
        switch self {
        case .charged:  return "battery.100percent.bolt"
        case .low:      return "battery.25percent"
        case .critical: return "battery.0percent"
        }
    }
}

/// Decides *when* alerts fire and drives how they're presented (on-screen bubble
/// + optional screen-edge glow + optional sound). Uses per-rule armed/disarmed
/// flags with a hysteresis band so an alert fires once per crossing instead of
/// repeating every poll.
@MainActor
final class AlertManager {
    private let settings: AppSettings
    private let bubble: any AlertBubblePresenting
    private let glow: any GlowPresenting

    /// Per-rule armed state, keyed by rule id.
    private var armed: [UUID: Bool] = [:]
    /// Per-accessory armed state, keyed by device id.
    private var accessoryArmed: [String: Bool] = [:]
    /// Armed state for the underpowered-adapter warning.
    private var underpoweredArmed = true
    private var hasBaseline = false
    /// Previous plugged-in state, for power-source transition alerts.
    private var wasPluggedIn: Bool?

    /// The currently playing sound. `NSSound` stops playing when deallocated, so
    /// it must be retained for the duration of playback — this is deliberate,
    /// see `PlayingSound`.
    private var activeSound: PlayingSound?

    /// Re-arm band: charge must recover this many points past the threshold
    /// before the same alert can fire again.
    private let hysteresis = 5

    init(
        settings: AppSettings,
        bubble: any AlertBubblePresenting = AlertBubbleController.shared,
        glow: any GlowPresenting = GlowOverlayController(),
        sender: NotificationSender = NotificationSender { false }
    ) {
        self.settings = settings
        self.bubble = bubble
        self.glow = glow
        self.sender = sender
    }

    /// System-notification delivery, so alerts reach the user even when the
    /// bubble is missed (full-screen apps, Do Not Disturb). Injected for
    /// testability; the default never sends.
    private let sender: NotificationSender

    // MARK: - Evaluation

    func evaluate(_ snapshot: BatterySnapshot) {
        defer { hasBaseline = true }
        for rule in settings.alertRules where rule.enabled {
            switch rule.category {
            case .low: evaluateLow(rule, snapshot)
            case .charged: evaluateCharged(rule, snapshot)
            }
        }
        evaluatePowerSource(snapshot)
        evaluateUnderpoweredAdapter(snapshot)
    }

    /// Plugged in, yet the battery is draining — the adapter can't cover system
    /// draw. Same armed/hysteresis pattern as the other alerts: fires once per
    /// crossing, re-arms once the battery stops discharging or power is lost.
    private func evaluateUnderpoweredAdapter(_ s: BatterySnapshot) {
        guard settings.underpoweredAdapterAlertEnabled else { return }
        // Discharging while on AC means the adapter is undersized for the load.
        let isUnderpowered = s.isPluggedIn && s.powerWatts < 0
        if isUnderpowered {
            if underpoweredArmed {
                underpoweredArmed = false
                present(
                    title: "Adapter Can't Keep Up",
                    subtitle: "Plugged in but the battery is draining",
                    icon: "bolt.badge.clock", color: .orange, position: .top,
                    persistent: false, glow: true, sound: .system("Funk"),
                    notificationCategory: "underpowered"
                )
            }
        } else {
            // Re-arm once genuinely off power or no longer discharging.
            underpoweredArmed = true
        }
    }

    private func evaluateLow(_ rule: BatteryAlertRule, _ s: BatterySnapshot) {
        let isArmed = armed[rule.id] ?? true
        if !s.isPluggedIn && s.percentage <= rule.threshold {
            if isArmed {
                fire(rule, snapshot: s)
                armed[rule.id] = false
            }
        } else if s.isPluggedIn || s.percentage >= rule.threshold + hysteresis {
            armed[rule.id] = true
        }
    }

    private func evaluateCharged(_ rule: BatteryAlertRule, _ s: BatterySnapshot) {
        let isArmed = armed[rule.id] ?? true
        if s.isPluggedIn && s.percentage >= rule.threshold {
            if isArmed {
                // Don't nag at launch if we're already above the threshold; only
                // fire on a genuine crossing.
                if hasBaseline { fire(rule, snapshot: s) }
                armed[rule.id] = false
            }
        } else if !s.isPluggedIn || s.percentage <= rule.threshold - hysteresis {
            armed[rule.id] = true
        }
    }

    private func evaluatePowerSource(_ s: BatterySnapshot) {
        defer { wasPluggedIn = s.isPluggedIn }
        guard let prev = wasPluggedIn else { return }   // skip the baseline reading

        if !prev && s.isPluggedIn, settings.pluggedInAlertEnabled {
            present(
                title: "Power Connected",
                subtitle: s.adapterName ?? "Adapter plugged in",
                icon: "powerplug.fill", color: .green, position: .top,
                persistent: false, glow: false, sound: settings.pluggedInSound
            )
        } else if prev && !s.isPluggedIn, settings.unpluggedAlertEnabled {
            // Reflect the actual charge level — unplugging at 90% shouldn't look
            // as alarming as unplugging at 9%.
            present(
                title: "On Battery",
                subtitle: "\(s.percentage)% remaining",
                icon: levelIcon(s.percentage), color: Self.levelColor(s.percentage),
                position: .top, persistent: false, glow: false,
                sound: settings.unpluggedSound
            )
        }
    }

    /// Maps a charge level to an alert accent, matching the in-panel state color.
    private static func levelColor(_ pct: Int) -> AlertColor {
        switch pct {
        case ...10: return .red
        case ...20: return .orange
        case ...50: return .yellow
        default: return .green
        }
    }

    /// Level-aware battery glyph spanning the full 0–100 range.
    private func levelIcon(_ pct: Int) -> String {
        switch pct {
        case ...10: return "battery.0percent"
        case ...30: return "battery.25percent"
        case ...55: return "battery.50percent"
        case ...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Evaluate connected accessories for low-battery warnings, honoring each
    /// device's own override (or the global accessory default).
    func evaluatePeripherals(_ devices: [PeripheralDevice]) {
        for device in devices {
            let config = settings.effectiveDeviceAlert(device.id)
            guard config.enabled, let percent = device.minPercent else { continue }
            let isArmed = accessoryArmed[device.id] ?? true

            if !device.isAnyCharging && percent <= config.threshold {
                if isArmed {
                    let text = accessoryAlertText(for: device)
                    present(
                        title: text.title,
                        subtitle: text.subtitle,
                        icon: "battery.25percent",
                        color: config.color ?? .orange,
                        position: .top,
                        persistent: false, glow: true,
                        sound: config.sound ?? .system("Funk"),
                        notificationCategory: "accessory"
                    )
                    accessoryArmed[device.id] = false
                }
            } else if device.isAnyCharging || percent >= config.threshold + hysteresis {
                accessoryArmed[device.id] = true
            }
        }
    }

    // MARK: - Firing

    private func fire(_ rule: BatteryAlertRule, snapshot s: BatterySnapshot) {
        let content = content(for: rule, percentage: s.percentage, minutes: s.minutesRemaining)
        present(
            title: content.title, subtitle: content.subtitle, icon: content.icon,
            color: rule.color, position: rule.position, persistent: rule.persistent,
            glow: rule.borderGlow, sound: rule.sound,
            notificationCategory: rule.category.rawValue
        )
    }

    /// Fire an alert immediately for the Settings "Test" button, ignoring the
    /// armed state and current battery level.
    func test(_ rule: BatteryAlertRule) {
        let content = content(for: rule, percentage: rule.threshold, minutes: nil)
        present(
            title: content.title, subtitle: content.subtitle, icon: content.icon,
            color: rule.color, position: rule.position, persistent: rule.persistent,            glow: rule.borderGlow, sound: rule.sound
        )
    }

    /// A sample bubble for the General "Preview" control, in the chosen accent.
    func preview(_ kind: AlertPreviewKind = .low) {
        present(
            title: kind.title, subtitle: kind.subtitle, icon: kind.icon,
            color: kind.color, position: .top,
            persistent: false, glow: true, sound: .system("Funk")
        )
    }

    // MARK: - Presentation

    private func present(
        title: String, subtitle: String, icon: String, color: AlertColor,
        position: AlertPosition, persistent: Bool, glow: Bool, sound: AlertSound,
        notificationCategory: String? = nil
    ) {
        bubble.show(.init(
            title: title, subtitle: subtitle, systemImage: icon,
            color: color.color, position: position, persistent: persistent,
            scale: settings.bubbleSize.scale, holdSeconds: settings.alertHoldSeconds
        ))
        if glow {
            self.glow.flash(color: color.nsColor, intensity: settings.glowIntensity.multiplier)
        }
        play(sound)
        if let notificationCategory {
            sender.send(title: title, subtitle: subtitle, category: notificationCategory)
        }
    }

    private func content(for rule: BatteryAlertRule, percentage: Int, minutes: Int?)
        -> (title: String, subtitle: String, icon: String)
    {
        switch rule.category {
        case .low:
            let subtitle = minutes.map { "\(Format.minutes($0)) until empty" } ?? "On battery power"
            return ("\(percentage)% Remaining", subtitle, lowIcon(percentage))
        case .charged:
            let subtitle = minutes.map { "\(Format.minutes($0)) until full" } ?? "Plugged in"
            return ("\(percentage)% Charged", subtitle, "battery.100percent.bolt")
        }
    }

    private func lowIcon(_ pct: Int) -> String {
        switch pct {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        default: return "battery.50percent"
        }
    }

    private func play(_ sound: AlertSound) {
        let nsSound: NSSound?
        switch sound {
        case .none: return
        case .system(let name): nsSound = NSSound(named: name)
        case .custom(let path): nsSound = NSSound(contentsOfFile: path, byReference: true)
        }
        guard let nsSound else { return }
        let playing = PlayingSound(nsSound)
        activeSound = playing
        playing.stop()
        playing.play()
    }
}

/// Retention wrapper for the sound playing during an alert. `NSSound` stops as
/// soon as it is deallocated, so a reference must outlive `play()` — previously
/// this was a bare `activeSound: NSSound?` ivar that read like an accident.
/// Wrapping it makes the intent explicit and gives playback a single owner.
@MainActor
private final class PlayingSound {
    private let sound: NSSound

    init(_ sound: NSSound) {
        self.sound = sound
    }

    func stop() { sound.stop() }
    func play() { sound.play() }
}

/// Accessory low-battery alert copy. A lone compartment must be named, or the number reads as the
/// whole device's charge — the same rule the panel applies. Pure, so it is testable on its own.
func accessoryAlertText(for device: PeripheralDevice) -> (title: String, subtitle: String) {
    guard let percent = device.minPercent else {
        return ("\(device.name) Low", "Time to charge")
    }
    let level = device.soleCompartment
        .map { "\($0.label ?? "One part") \(percent)%" }
        ?? "\(percent)%"
    return ("\(device.name) Low", "\(level) remaining — time to charge")
}
