import SwiftUI
import UniformTypeIdentifiers

// MARK: - Menu Bar pane (split from SettingsView.swift)

struct MenuBarSettingsView: View {
    @Bindable var settings: AppSettings
    let model: BatteryModel

    var body: some View {
        SettingsPane(
            icon: "menubar.rectangle", tint: .teal, title: "Menu Bar",
            subtitle: "Customize how Voltio appears in your menu bar"
        ) {
            SettingsSection(icon: "menubar.rectangle", tint: .teal, title: "Menu Bar Icon") {
                ForEach(Array(AppSettings.MenuBarIconStyle.allCases.enumerated()), id: \.element) { index, style in
                    RadioRow(
                        title: style.label,
                        subtitle: style.detail,
                        isSelected: settings.menuBarIconStyle == style
                    ) {
                        settings.menuBarIconStyle = style
                    }
                    if index < AppSettings.MenuBarIconStyle.allCases.count - 1 { RowDivider() }
                }
            }

            SettingsSection(icon: "arrow.up.left.and.arrow.down.right", tint: .indigo, title: "Icon Size") {
                ForEach(Array(AppSettings.MenuBarIconSize.allCases.enumerated()), id: \.element) { index, size in
                    RadioRow(
                        title: size.label,
                        subtitle: size.detail,
                        isSelected: settings.menuBarIconSize == size
                    ) {
                        settings.menuBarIconSize = size
                    }
                    if index < AppSettings.MenuBarIconSize.allCases.count - 1 { RowDivider() }
                }
            }

            SettingsSection(icon: "slider.horizontal.3", tint: .purple, title: "Display") {
                SettingsRow(
                    icon: "textformat.123", tint: .purple,
                    title: "Show value",
                    subtitle: "What to display next to the icon"
                ) {
                    Picker("", selection: $settings.menuBarValue) {
                        ForEach(AppSettings.MenuBarValue.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(settings.menuBarIconStyle == .minimal)
                    .appearanceAdaptivePicker()
                }
                RowDivider()
                SettingsRow(
                    icon: "paintpalette.fill", tint: .orange,
                    title: "Status colors",
                    subtitle: "Green charging, orange low, red critical"
                ) {
                    Toggle("", isOn: $settings.statusColors).labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Panel Sections").font(.title3.weight(.semibold))
                }
                SettingsCard {
                    ForEach(Array(settings.orderedPanelSections.enumerated()), id: \.element) { index, section in
                        if index > 0 { RowDivider() }
                        PanelSectionReorderRow(
                            section: section,
                            isFirst: index == 0,
                            isLast: index == settings.orderedPanelSections.count - 1,
                            settings: settings
                        )
                    }
                }
                Text("Drag to reorder: the first item is the first section in the menu panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Reset to Default") {
                        withAnimation(.easeInOut(duration: 0.2)) { settings.resetPanelSectionOrder() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Preview").font(.title3.weight(.semibold))
                }
                MenuBarPreview(settings: settings, model: model)
            }
        }
    }
}

/// A faux menu-bar strip that mirrors the live icon settings.
private struct MenuBarPreview: View {
    @Bindable var settings: AppSettings
    let model: BatteryModel

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            rendered
            Text(Date.now, style: .time)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.18, blue: 0.24), Color(red: 0.07, green: 0.11, blue: 0.17)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }

    @ViewBuilder private var rendered: some View {
        let glyph = MenuBarRender.glyphView(
            settings: settings,
            model: model,
            height: settings.menuBarIconSize.previewHeight
        )
        if settings.statusColors, let tint = model.menuBarTint {
            glyph.foregroundStyle(tint)
        } else {
            glyph.foregroundStyle(.white)
        }
    }
}

/// One draggable row in the "Panel Sections" reorder card. Supports
/// drag-and-drop reordering plus explicit up/down buttons (also the
/// keyboard-accessible path).
private struct PanelSectionReorderRow: View {
    let section: AppSettings.PanelSection
    let isFirst: Bool
    let isLast: Bool
    let settings: AppSettings

    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .help("Drag to reorder")

            SquareIconBadge(systemName: section.icon, tint: .orange, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.label).font(.body.weight(.medium))
                Text(section.detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                reorderButton(icon: "chevron.up", disabled: isFirst) {
                    withAnimation(.easeInOut(duration: 0.2)) { settings.movePanelSectionUp(section) }
                }
                reorderButton(icon: "chevron.down", disabled: isLast) {
                    withAnimation(.easeInOut(duration: 0.2)) { settings.movePanelSectionDown(section) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isDropTarget ? Color.accentColor.opacity(0.12) : .clear)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.text],
            delegate: PanelSectionDropDelegate(
                target: section,
                settings: settings,
                isTargeted: { isDropTarget = $0 }
            )
        )
        .onDrag {
            NSItemProvider(object: section.rawValue as NSString)
        }
    }

    private func reorderButton(icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : Color.secondary)
        .disabled(disabled)
        .help(icon.contains("up") ? "Move up" : "Move down")
    }
}

/// Moves the dragged section to the dropped-on row's position. Only accepts
/// providers carrying another `PanelSection` raw value.
private struct PanelSectionDropDelegate: DropDelegate {
    let target: AppSettings.PanelSection
    let settings: AppSettings
    let isTargeted: (Bool) -> Void

    func dropEntered(info: DropInfo) {
        isTargeted(true)
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String,
                  let dragged = AppSettings.PanelSection(rawValue: raw),
                  dragged != target else { return }
            Task { @MainActor in
                var order = settings.orderedPanelSections
                guard let from = order.firstIndex(of: dragged),
                      let to = order.firstIndex(of: target) else { return }
                order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                withAnimation(.easeInOut(duration: 0.2)) { settings.panelSectionOrder = order }
            }
        }
    }

    func dropExited(info: DropInfo) { isTargeted(false) }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted(false)
        return true
    }
}
