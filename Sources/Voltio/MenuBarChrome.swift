import AppKit
import SwiftUI

/// Menu-bar glyph: a horizontal battery with the charge level drawn
/// *inside* it (or a clean fill bar), a leading bolt while charging, or the Voltio
/// logo. Rendered as a single view so the live status item and the settings
/// preview always look identical.
struct MenuBarGlyphView: View {
    let style: AppSettings.MenuBarIconStyle
    let value: AppSettings.MenuBarValue
    let percentage: Int
    let timeText: String
    let isCharging: Bool
    /// Pinned accessories rendered after the main glyph, as tiny battery fills.
    var pinnedDevices: [PinnedDevice] = []
    /// Glyph height in points; everything else scales from this.
    var height: CGFloat = 15

    /// A pinned accessory's menu-bar state: name, charge fraction, and
    /// low-battery color (nil = normal tint).
    struct PinnedDevice: Equatable {
        let name: String
        let fraction: Double
        let isLow: Bool
    }

    var body: some View {
        HStack(spacing: height * 0.18) {
            switch style {
            case .batteryIndicator: batteryIndicator
            case .minimal: minimal
            case .logo: logo
            }
            ForEach(pinnedDevices, id: \.name) { device in
                pinnedGlyph(device)
            }
        }
        .frame(height: height)
    }

    /// A small battery glyph for a pinned accessory. Same discrete-level
    /// system symbols as the main battery at ~78% size, tinted red when low.
    private func pinnedGlyph(_ device: PinnedDevice) -> some View {
        Image(systemName: Self.levelSymbolName(for: device.fraction))
            .font(.system(size: height * 0.9))
            .foregroundStyle(device.isLow ? Color.red : Color.primary)
    }

    // MARK: Styles

    @ViewBuilder private var batteryIndicator: some View {
        if isCharging { bolt }
        switch value {
        case .percentage: batteryWithText("\(percentage)")
        case .none: batteryWithFill(Double(percentage) / 100)
        case .time:
            batteryWithFill(Double(percentage) / 100)
            valueLabel(timeText)
        }
    }

    @ViewBuilder private var minimal: some View {
        if isCharging { bolt }
        batteryWithFill(Double(percentage) / 100)
    }

    @ViewBuilder private var logo: some View {
        bolt
        switch value {
        case .percentage: valueLabel("\(percentage)%")
        case .time: valueLabel(timeText)
        case .none: EmptyView()
        }
    }

    // MARK: Pieces

    private var bolt: some View {
        // While charging, the system shows the bolt *inside* the battery body
        // (`battery.100percent.bolt`); when discharging the status-color bolt
        // sits alongside the glyph. A glow can't survive template rendering,
        // so it's only applied in the colored (charging) case.
        let glyph = Image(systemName: isCharging ? "bolt.fill" : "bolt.fill")
            .font(.system(size: height * 0.74, weight: .bold))
        return Group {
            if isCharging {
                // Soft halo so the bolt reads as "actively charging".
                glyph
                    .shadow(color: .green.opacity(0.9), radius: height * 0.18)
                    .shadow(color: .green.opacity(0.55), radius: height * 0.09)
            } else {
                glyph
            }
        }
    }

    private func valueLabel(_ text: String) -> some View {
        Text(text).font(.system(size: height * 0.84, weight: .semibold))
    }

    /// Authentic system battery artwork with the percentage inside. The glyph
    /// is the real SF Symbol Apple ships with the OS (the same vector designs
    /// the system menu bar draws), rendered at runtime via `Image(systemName:)`
    /// — so it always matches the installed OS design (macOS 26 today, and the
    /// macOS 27 designs automatically once the OS updates).
    ///
    /// The number lives in a *fixed-width* frame, so the glyph's total width is
    /// constant whether the label is "1", "25", or "100".
    private func batteryWithText(_ text: String) -> some View {
        // At point size p the symbol draws 26/15·p wide × 12/15·p tall; a point
        // size of 1.15·height yields a battery body ≈ 0.92·height tall.
        let pointSize = height * 1.15
        let nubW = pointSize * 0.08        // terminal occupies the trailing ~8%
        let fontSize = height * 0.58
        return ZStack {
            Image(systemName: "battery.0percent")
                .font(.system(size: pointSize))
            Text(text)
                .font(.system(size: fontSize, weight: .heavy))
                .monospacedDigit()
                .minimumScaleFactor(0.85)
                .frame(width: pointSize * 1.5, height: pointSize * 0.75)
                // Center the number in the body, left of the terminal nub.
                .offset(x: -nubW / 2)
        }
    }

    /// Authentic discrete-level battery (0/25/50/75/100%), like the system
    /// menu bar battery. Used by Minimal and by the no-number/time modes.
    private func batteryWithFill(_ fraction: Double) -> some View {
        Image(systemName: Self.levelSymbolName(for: fraction))
            .font(.system(size: height * 1.15))
    }

    /// Maps a continuous charge fraction to the nearest of the system's
    /// discrete battery symbols.
    private static func levelSymbolName(for fraction: Double) -> String {
        switch fraction {
        case ..<0.125: "battery.0percent"
        case ..<0.375: "battery.25percent"
        case ..<0.625: "battery.50percent"
        case ..<0.875: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Builds the menu-bar glyph (as a live view or a rasterized status-item image).
@MainActor
enum MenuBarRender {
    static func glyphView(settings: AppSettings, model: BatteryModel, height: CGFloat? = nil) -> MenuBarGlyphView {
        MenuBarGlyphView(
            style: settings.menuBarIconStyle,
            value: settings.menuBarValue,
            percentage: model.snapshot?.percentage ?? 0,
            timeText: model.menuBarTimeTitle,
            isCharging: model.snapshot?.menuBarCharging ?? false,
            pinnedDevices: pinnedDevices(settings: settings, model: model),
            // Default to the user's chosen icon size; callers may override
            // (e.g. the settings preview uses its own strip height).
            height: height ?? settings.menuBarIconSize.glyphHeight
        )
    }

    /// Current state of the user's pinned devices, in display order. Only
    /// connected, non-hidden devices render; disconnected pins drop out until
    /// they reconnect.
    private static func pinnedDevices(settings: AppSettings, model: BatteryModel) -> [MenuBarGlyphView.PinnedDevice] {
        guard settings.showConnectedDevices else { return [] }
        return model.peripherals
            .filter { settings.isDevicePinned($0.id) && !settings.isDeviceHidden($0.id) && $0.isConnected }
            .map { peripheral in
                let percent = peripheral.minPercent ?? 0
                return MenuBarGlyphView.PinnedDevice(
                    name: peripheral.name,
                    fraction: Double(percent) / 100,
                    isLow: percent <= 20
                )
            }
    }

    /// Everything that affects the rendered glyph. If this is unchanged, the
    /// previously rasterized image is reused.
    private struct Key: Equatable {
        let style: AppSettings.MenuBarIconStyle
        let value: AppSettings.MenuBarValue
        let size: AppSettings.MenuBarIconSize
        let percentage: Int
        let isCharging: Bool
        let timeText: String
        let colored: Bool
        let tint: Color
        let scale: CGFloat
        let pinnedDevices: [MenuBarGlyphView.PinnedDevice]
    }

    private static var cacheKey: Key?
    private static var cachedImage: NSImage?

    /// Rasterizes the glyph for `MenuBarExtra`. Bitmaps render reliably in the
    /// menu bar (unlike SF Symbols interpolated into `Text`). Template images
    /// adapt to the menu-bar appearance; colored images keep the state color.
    ///
    /// Cached by `Key`: `ImageRenderer` only runs when the visible glyph actually
    /// changes, so repeated SwiftUI re-evaluations on a steady battery are free.
    static func image(settings: AppSettings, model: BatteryModel) -> NSImage? {
        // Keyed on plug-in (instant) rather than the lagging `IsCharging` flag.
        let charging = model.snapshot?.menuBarCharging ?? false
        // While charging we always render in color so the green bolt + glow show,
        // even when "status colors" is off (a transient charging affordance).
        let colored = settings.statusColors || charging
        let tint: Color = colored ? (model.menuBarTint ?? .white) : .white
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        // Reading these properties here also keeps SwiftUI's observation tracking
        // intact, so the label still re-evaluates when the state changes.
        let pinned = pinnedDevices(settings: settings, model: model)
        let key = Key(
            style: settings.menuBarIconStyle,
            value: settings.menuBarValue,
            size: settings.menuBarIconSize,
            percentage: model.snapshot?.percentage ?? 0,
            isCharging: charging,
            timeText: model.menuBarTimeTitle,
            colored: colored,
            tint: tint,
            scale: scale,
            pinnedDevices: pinned
        )
        if key == cacheKey, let cachedImage { return cachedImage }

        let content = glyphView(settings: settings, model: model)
            .foregroundStyle(tint)
            .padding(.horizontal, 2)
            // Extra vertical headroom on large glyphs so the charging glow
            // still isn't clipped by the status-item cap.
            .padding(.vertical, settings.menuBarIconSize == .large ? 2.5 : 1.5)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.isOpaque = false
        guard let image = renderer.nsImage else { return nil }
        // A glow can't be expressed in a template mask, so only treat the
        // monochrome (non-charging, colors-off) case as a template image.
        image.isTemplate = !colored
        // VoiceOver reads this in place of the rasterized glyph.
        image.accessibilityDescription = accessibilityLabel(percentage: model.snapshot?.percentage, charging: charging)

        cacheKey = key
        cachedImage = image
        return image
    }

    /// Spoken description for the status item, e.g. "Battery 80%, charging".
    private static func accessibilityLabel(percentage: Int?, charging: Bool) -> String {
        guard let percentage else { return "Battery" }
        return charging ? "Battery \(percentage)%, charging" : "Battery \(percentage)%"
    }
}

/// Opens Voltio's app window (used at launch and for Dock/Applications reopen).
/// Delegates to the AppKit-managed `MainWindowController` for reliable behavior.
@MainActor
enum SettingsLauncher {
    static func open() {
        MainWindowController.shared.show()
    }
}

/// Opens a SwiftUI `Window` scene declared in the app (e.g. the onboarding
/// window) by id. Uses the scene-phase environment on a hidden helper view.
@MainActor
enum OpenWindow {
    static func open(id: String) {
        OpenWindowBridge.shared.requestOpen(id: id)
    }
}

/// Bridges `openWindow` (a SwiftUI environment action, unavailable from
/// AppKit code) to the app: a view installed at launch captures the action
/// so `OpenWindow.open` can call it later.
@MainActor
final class OpenWindowBridge {
    static let shared = OpenWindowBridge()
    private var action: ((String) -> Void)?

    func install(_ action: @escaping (String) -> Void) { self.action = action }

    func requestOpen(id: String) { action?(id) }
}

private struct OpenWindowBridgeInstaller: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            OpenWindowBridge.shared.install { id in
                openWindow(id: id)
            }
        }
    }
}

extension View {
    /// Captures the environment's `openWindow` action for later use by
    /// `OpenWindow.open(id:)` from non-SwiftUI code paths.
    func installOpenWindowBridge() -> some View { modifier(OpenWindowBridgeInstaller()) }
}
