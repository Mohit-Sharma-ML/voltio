import SwiftUI

/// A card-based settings design language for the app window — modeled on a
/// modern macOS settings layout (sidebar + detail panes with section headers
/// and grouped rows). Used by `SettingsView`. Backgrounds are appearance-
/// adaptive (dynamic NSColors) so the System/Light/Dark preference works;
/// the dark values match the original fixed dark palette.

extension Color {
    /// Detail-pane background (near-black in dark, light neutral in light).
    static let settingsDetailBG = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.065, green: 0.067, blue: 0.078, alpha: 1)
            : NSColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1)
    })
    /// Sidebar background (slightly lifted from the detail pane).
    static let settingsSidebarBG = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.095, green: 0.10, blue: 0.115, alpha: 1)
            : NSColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)
    })
    static let settingsCardFill = Color.white.opacity(0.045)
    static let settingsCardStroke = Color.white.opacity(0.075)
    static let settingsRowDivider = Color.white.opacity(0.06)
}

/// Rebuilds AppKit-backed controls (menu-style `Picker` → `NSPopUpButton` and
/// its `NSMenu`) whenever the effective color scheme flips. AppKit caches the
/// popup cell's label color and the menu's appearance when the control is
/// created, so after a Light/Dark switch the control keeps rendering with the
/// stale look (white-on-light labels, dark popup in a light window). Changing
/// the view's identity via `.id(colorScheme)` forces SwiftUI to discard and
/// recreate the control under the new appearance.
private struct AppearanceKeyedPicker: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.id(colorScheme)
    }
}

extension View {
    /// Apply to every menu-style `Picker` so its popup and label follow the
    /// selected app appearance immediately (see `AppearanceKeyedPicker`).
    func appearanceAdaptivePicker() -> some View {
        modifier(AppearanceKeyedPicker())
    }
}

/// A solid, rounded-square SF Symbol badge (the colored icon used throughout).
struct SquareIconBadge: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(tint.gradient)
            )
            .shadow(color: tint.opacity(0.35), radius: 3, y: 1)
    }
}

/// A detail pane: a fixed header (badge + title) over a scrollable body that
/// opens with a one-line subtitle followed by the supplied sections.
struct SettingsPane<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                SquareIconBadge(systemName: icon, tint: tint, size: 30)
                Text(title).font(.title2.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().overlay(Color.settingsRowDivider)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    content()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.settingsDetailBG)
    }
}

/// A titled group: a small colored icon + bold title above a card of rows.
struct SettingsSection<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title).font(.title3.weight(.semibold))
            }
            SettingsCard { content() }
        }
    }
}

/// The rounded dark surface that holds a vertical stack of rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.settingsCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.settingsCardStroke)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// An inset divider between rows inside a `SettingsCard`.
struct RowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.settingsRowDivider)
            .padding(.leading, 58)
    }
}

/// A single settings row: colored badge + title (+ optional description) and a
/// trailing control (toggle, picker, button, value…).
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            SquareIconBadge(systemName: icon, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// A selectable option row (radio/checkmark on the trailing edge).
struct RadioRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.green : Color.secondary.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
