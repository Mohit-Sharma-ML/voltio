import SwiftUI

// MARK: - General pane (split from SettingsView.swift)

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let model: BatteryModel

    /// Which sample alert the Preview button fires.
    @State private var previewKind: AlertPreviewKind = .low

    /// "3s" for whole values, "3.5s" otherwise.
    private func holdLabel(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? "\(Int(seconds))s" : String(format: "%.1fs", seconds)
    }

    var body: some View {
        SettingsPane(
            icon: "gearshape.fill", tint: .green, title: "General",
            subtitle: "Basic app settings and preferences"
        ) {
            SettingsSection(icon: "circle.lefthalf.filled", tint: .indigo, title: "Appearance") {
                SettingsRow(
                    icon: "circle.lefthalf.filled", tint: .indigo,
                    title: "App Appearance",
                    subtitle: "Match the system look, or force Light or Dark"
                ) {
                    Picker("", selection: $settings.preferredAppearance) {
                        ForEach(AppSettings.Appearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .appearanceAdaptivePicker()
                }
            }
            SettingsSection(icon: "power", tint: .green, title: "System Integration") {
                SettingsRow(
                    icon: "power", tint: .green,
                    title: "Launch at Login",
                    subtitle: "Start Voltio automatically when you log in"
                ) {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                }
                RowDivider()
                SettingsRow(
                    icon: "dock.rectangle", tint: .blue,
                    title: "Always keep in Dock",
                    subtitle: "Otherwise the Dock icon shows only while a window is open"
                ) {
                    Toggle("", isOn: $settings.showInDock).labelsHidden()
                }
                if let error = settings.launchAtLoginError {
                    RowDivider()
                    SettingsRow(
                        icon: "exclamationmark.triangle.fill", tint: .red,
                        title: "Login item error", subtitle: error
                    ) { EmptyView() }
                }
            }

            SettingsSection(icon: "arrow.clockwise", tint: .teal, title: "Telemetry") {
                SettingsRow(
                    icon: "arrow.clockwise", tint: .teal,
                    title: "Refresh rate",
                    subtitle: "How often battery data is read. Faster uses slightly more energy."
                ) {
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(AppSettings.RefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .appearanceAdaptivePicker()
                }
            }

            SettingsSection(icon: "keyboard", tint: .purple, title: "Shortcuts") {
                SettingsRow(
                    icon: "keyboard", tint: .purple,
                    title: "Global Shortcuts",
                    subtitle: "Works system-wide, even when Voltio isn't focused"
                ) {
                    Toggle("", isOn: $settings.hotkeysEnabled).labelsHidden()
                }
                if settings.hotkeysEnabled {
                    RowDivider()
                    SettingsRow(
                        icon: "command", tint: .purple,
                        title: "Toggle Battery Panel", subtitle: "⇧⌘B"
                    ) { EmptyView() }
                    RowDivider()
                    SettingsRow(
                        icon: "gearshape", tint: .purple,
                        title: "Open Settings", subtitle: "⇧⌘S"
                    ) { EmptyView() }
                    RowDivider()
                    SettingsRow(
                        icon: "battery.75percent", tint: .purple,
                        title: "Toggle Battery Info",
                        subtitle: "Expand/collapse panel details — \(settings.toggleBatteryInfoShortcut.display)"
                    ) { EmptyView() }
                    RowDivider()
                    SettingsRow(
                        icon: "magicmouse", tint: .purple,
                        title: "Toggle Devices",
                        subtitle: "Show/hide connected devices — \(settings.toggleDevicesShortcut.display)"
                    ) { EmptyView() }
                    RowDivider()
                    SettingsRow(
                        icon: "gauge.with.dots.needle.33percent", tint: .purple,
                        title: "Toggle Energy Card",
                        subtitle: "Show/hide the Energy Today card — \(settings.toggleEnergyAppsShortcut.display)"
                    ) { EmptyView() }
                    RowDivider()
                    SettingsRow(
                        icon: "arrow.counterclockwise", tint: .purple,
                        title: "Reset to default shortcuts",
                        subtitle: "Restore ⇧⌘I, ⇧⌘D and ⇧⌘E for the toggles above"
                    ) {
                        Button("Reset") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.resetShortcutBindings()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.purple)
                    }
                }
            }

            SettingsSection(icon: "bell.badge.fill", tint: .pink, title: "Notification Appearance") {
                SettingsRow(
                    icon: "rectangle.portrait.and.arrow.right", tint: .pink,
                    title: "Alert bubble size",
                    subtitle: "Size of the on-screen alert bubble"
                ) {
                    Picker("", selection: $settings.bubbleSize) {
                        ForEach(AppSettings.BubbleSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .appearanceAdaptivePicker()
                }
                RowDivider()
                SettingsRow(
                    icon: "rays", tint: .yellow,
                    title: "Screen edge glow",
                    subtitle: "Strength of the colored glow around the screen"
                ) {
                    Picker("", selection: $settings.glowIntensity) {
                        ForEach(AppSettings.GlowIntensity.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .appearanceAdaptivePicker()
                }
                RowDivider()
                SettingsRow(
                    icon: "clock.fill", tint: .orange,
                    title: "Alert duration",
                    subtitle: "How long an alert stays on screen before sliding away"
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $settings.alertHoldSeconds, in: 2...8, step: 0.5)
                            .tint(.orange)
                            .frame(width: 130)
                        Text(holdLabel(settings.alertHoldSeconds))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                RowDivider()
                SettingsRow(
                    icon: "play.circle.fill", tint: .green,
                    title: "Preview notification",
                    subtitle: "Pick a state, then preview how that alert looks"
                ) {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ForEach(AlertPreviewKind.allCases) { kind in
                                PreviewSwatch(
                                    kind: kind,
                                    isSelected: previewKind == kind
                                ) { previewKind = kind }
                            }
                        }
                        Button("Preview") { model.previewAlert(previewKind) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(previewKind.color.color)
                    }
                }
            }

            SettingsSection(icon: "wrench.and.screwdriver.fill", tint: .orange, title: "Advanced") {
                SettingsRow(
                    icon: "wrench.and.screwdriver.fill", tint: .orange,
                    title: "Developer Mode",
                    subtitle: "Show BLE diagnostics on the Devices pane and enable the fake battery override"
                ) {
                    Toggle("", isOn: $settings.developerMode).labelsHidden()
                }
            }
        }
    }
}

/// A small selectable color dot used to choose which sample alert to preview.
private struct PreviewSwatch: View {
    let kind: AlertPreviewKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let tint = kind.color.color
        Button(action: action) {
            Circle()
                .fill(tint)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.settingsInsetStroke, lineWidth: 1))
                .overlay(
                    Circle()
                        .strokeBorder(.white, lineWidth: isSelected ? 2 : 0)
                        .padding(-3)
                )
                .shadow(color: tint.opacity(isSelected ? 0.6 : 0), radius: 4)
                .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .help("Preview \(kind.label) alert")
        .accessibilityLabel("\(kind.label) alert")
    }
}
