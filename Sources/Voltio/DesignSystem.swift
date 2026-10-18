import SwiftUI
import AppKit

/// Shared visual language for the panel: card surfaces, badges, bars.
/// Kept flat and native — tint is used deliberately, not everywhere.
enum Theme {
    static let panelWidth: CGFloat = 320
    static let cornerRadius: CGFloat = 14
    static let cardCornerRadius: CGFloat = 12
}

// MARK: - Panel palette

extension Color {
    /// Panel background gradient (top), chosen by the panel's active scheme.
    /// Scheme-explicit (not dynamic NSColors): the MenuBarExtra window's
    /// effectiveAppearance doesn't follow the in-app Light/Dark pick, so
    /// window-resolved colors would stay on the old theme. Light mirrors the
    /// native macOS panel: soft gray backdrop so white cards read as cards.
    static func panelTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.15)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }
    /// Panel background gradient (bottom of the gradient).
    static func panelBottom(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.05, blue: 0.07)
            : Color(red: 0.88, green: 0.88, blue: 0.91)
    }
    static let cardFill = Color.primary.opacity(0.06)
    static let cardStroke = Color.primary.opacity(0.09)
}

/// Subtle colored glow used sparingly on accent elements.
private struct Glow: ViewModifier {
    let color: Color
    let radius: CGFloat
    @Environment(\.panelScheme) private var scheme

    func body(content: Content) -> some View {
        // Glow is a dark-mode effect: on light backgrounds the shadow
        // renders as a dirty halo around icons/text. Light mode gets a
        // crisp, glow-free render.
        if scheme == .dark {
            content.shadow(color: color.opacity(0.4), radius: radius)
        } else {
            content
        }
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 8) -> some View {
        modifier(Glow(color: color, radius: radius))
    }
}

// MARK: - Panel scheme (custom environment key)

/// The panel's authoritative color scheme, written ONLY by MenuPanelView.
/// The system `\.colorScheme` environment is set by the hosting window —
/// and the MenuBarExtra window's value does not reliably follow the system
/// appearance (it read *light* under Match System with a dark system),
/// which produced mixed renders: scheme-explicit surfaces dark while
/// env-reading components (glows, pill, bar tracks) rendered their light
/// variants. A custom key has exactly one writer, so every component in
/// the panel agrees.
private struct PanelSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .dark
}

extension EnvironmentValues {
    var panelScheme: ColorScheme {
        get { self[PanelSchemeKey.self] }
        set { self[PanelSchemeKey.self] = newValue }
    }
}

// MARK: - Card surface

private struct CardSurface: ViewModifier {
    @Environment(\.panelScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(scheme == .light ? Color.white : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .light ? 0.12 : 0.09))
            )
    }
}

extension View {
    func card() -> some View { modifier(CardSurface()) }
}

// MARK: - Scheme-aware accent text

extension Color {
    /// A tint tuned for use as *text* on the panel's cards. SwiftUI's fixed
    /// colors (.green/.orange/…) are calibrated for fills and turn washy on a
    /// light background — dark mode darkens them for contrast there instead.
    /// Views read the scheme from the environment at the call site.
    func adaptiveTextTint(_ scheme: ColorScheme) -> Color {
        guard scheme == .light else { return self }
        // Darken by blending toward black — keeps the hue, restores contrast.
        let ns = NSColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(1, s * 1.15)), brightness: Double(b * 0.72))
    }
}

// MARK: - Reusable pieces

/// A circular tinted badge holding an SF Symbol.
struct IconBadge: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.18)))
            .glow(tint, radius: 3)
    }
}

/// A small tappable "info" affordance that reveals an explanation popover.
struct InfoButton: View {
    let text: String
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(width: 230)
        }
    }
}

/// Uppercase section label.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Rounded progress capsule with a tinted fill.
struct FillBar: View {
    let value: Double           // 0...1
    var tint: Color = .accentColor
    var height: CGFloat = 6

    @Environment(\.panelScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(scheme == .light ? 0.14 : 0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
/// A small labeled statistic used in horizontal groups.
struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A status pill (icon + text) tinted by battery state.
struct StatusPill: View {
    let text: String
    let systemName: String
    let tint: Color

    @Environment(\.panelScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint.adaptiveTextTint(scheme))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(scheme == .light ? 0.14 : 0.18)))
        .glow(tint, radius: 4)
    }
}

/// A circular charge gauge with the percentage in the center — the hero centerpiece.
struct BatteryRing: View {
    let level: Double           // 0...1
    let percentage: Int
    let tint: Color
    let isCharging: Bool

    var size: CGFloat = 150
    private var lineWidth: CGFloat { size * 0.08 }

    @Environment(\.panelScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(scheme == .light ? 0.14 : 0.10), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, level)))
                // Solid tint, not an angular gradient: a 2-stop angular ramp always has a wrap
                // point somewhere on the circle, and SwiftUI sweeps the gradient opposite to the
                // trim's clockwise direction — so for any level past ~75% the wrap lands ON the
                // visible arc as a hard brightness seam (reported: "hard line on the left side"
                // at 85%). Solid + glow reads identically at a glance and is seam-free at every
                // level.
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .glow(tint, radius: 5)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(percentage)")
                        .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: size * 0.12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.45))
                }
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.09, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: level)
    }
}
