import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Alerts pane (split from SettingsView.swift)

struct AlertsSettingsView: View {
    @Bindable var settings: AppSettings
    let model: BatteryModel

    var body: some View {
        SettingsPane(
            icon: "bell.fill", tint: .green, title: "Alerts",
            subtitle: "On-screen alerts when your battery runs low or finishes charging. Add as many as you like and tune how each one looks and sounds."
        ) {
            alertGroup(.low, icon: "battery.25percent", tint: .orange)
            alertGroup(.charged, icon: "battery.100percent.bolt", tint: .green)

            SettingsSection(icon: "powerplug.fill", tint: .teal, title: "Power Source Alerts") {
                SettingsRow(
                    icon: "powerplug.fill", tint: .green,
                    title: "Plugged In",
                    subtitle: "Alert when the power adapter is connected"
                ) {
                    Toggle("", isOn: $settings.pluggedInAlertEnabled).labelsHidden()
                }
                if settings.pluggedInAlertEnabled {
                    RowDivider()
                    SettingsRow(icon: "speaker.wave.2.fill", tint: .green, title: "Sound") {
                        SoundPickerMenu(sound: $settings.pluggedInSound, maxWidth: 200)
                    }
                }
                RowDivider()
                SettingsRow(
                    icon: "powerplug", tint: .orange,
                    title: "Unplugged",
                    subtitle: "Alert when the power adapter is disconnected"
                ) {
                    Toggle("", isOn: $settings.unpluggedAlertEnabled).labelsHidden()
                }
                if settings.unpluggedAlertEnabled {
                    RowDivider()
                    SettingsRow(icon: "speaker.wave.2.fill", tint: .orange, title: "Sound") {
                        SoundPickerMenu(sound: $settings.unpluggedSound, maxWidth: 200)
                    }
                }
                RowDivider()
                SettingsRow(
                    icon: "bolt.badge.clock", tint: .red,
                    title: "Adapter Can't Keep Up",
                    subtitle: "Alert when plugged in but the battery is still draining"
                ) {
                    Toggle("", isOn: $settings.underpoweredAdapterAlertEnabled).labelsHidden()
                }
            }

            SettingsSection(icon: "airpodspro", tint: .blue, title: "Accessories") {
                SettingsRow(
                    icon: "airpodspro", tint: .blue,
                    title: "Accessory low battery",
                    subtitle: "AirPods & Magic devices. AirPods need Bluetooth access."
                ) {
                    Toggle("", isOn: $settings.accessoryLowAlertEnabled).labelsHidden()
                }
                if settings.accessoryLowAlertEnabled {
                    RowDivider()
                    SettingsRow(icon: "percent", tint: .blue, title: "Warn at") {
                        HStack(spacing: 10) {
                            Text("\(settings.accessoryLowThreshold)%")
                                .font(.body.weight(.semibold)).monospacedDigit()
                            Stepper("", value: $settings.accessoryLowThreshold, in: 5...50, step: 5)
                                .labelsHidden()
                        }
                    }
                }
            }

            Button { settings.resetRules() } label: {
                Label("Reset All Alerts", systemImage: "arrow.counterclockwise")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func alertGroup(_ category: AlertCategory, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(category.title).font(.title3.weight(.semibold))
            }

            ForEach($settings.alertRules) { $rule in
                if rule.category == category {
                    AlertRuleCard(
                        rule: $rule,
                        onTest: { model.testAlert(rule) },
                        onDelete: { settings.removeRule(rule.id) }
                    )
                }
            }

            Button { settings.addRule(category) } label: {
                Label(
                    category == .low ? "Add Low Battery Alert" : "Add Charged Alert",
                    systemImage: "plus"
                )
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.settingsInsetFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.settingsInsetStroke)
                )
            }
            .buttonStyle(.plain)
            .tint(.secondary)
        }
    }
}

/// One alert in the list — a collapsed summary that expands into a full editor
/// (threshold, color, position, sound, glow, persistence, Test).
private struct AlertRuleCard: View {
    @Binding var rule: BatteryAlertRule
    let onTest: () -> Void
    let onDelete: () -> Void

    @State private var expanded = false

    private var accent: Color { rule.color.color }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                Divider().overlay(Color.settingsRowDivider)
                editor.padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.settingsCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    rule.enabled ? accent.opacity(0.4) : Color.settingsCardStroke,
                    lineWidth: rule.enabled ? 1.2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(rule.enabled ? 1 : 0.6)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(accent.gradient)
                        Text("\(rule.threshold)")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 38, height: 30)
                    .shadow(color: accent.opacity(0.4), radius: 3, y: 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(rule.threshold)%")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(rule.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: $rule.enabled)
                .labelsHidden()
                .controlSize(.mini)
                .tint(accent)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Battery Percentage") {
                HStack(spacing: 12) {
                    Slider(value: thresholdBinding, in: rule.category.thresholdRange, step: 1)
                        .tint(accent)
                    Text("\(rule.threshold)%")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            HStack(alignment: .top, spacing: 22) {
                field("Color") { ColorSwatchPicker(selection: $rule.color) }
                field("Position") { PositionPicker(selection: $rule.position) }
            }

            field("Sound") { SoundPickerMenu(sound: $rule.sound) }

            HStack(spacing: 22) {
                Toggle(isOn: $rule.borderGlow) {
                    Text("Border Glow").font(.callout)
                }
                .toggleStyle(.switch).controlSize(.small).tint(accent)

                Toggle(isOn: $rule.persistent) {
                    Text("Persistent").font(.callout)
                }
                .toggleStyle(.switch).controlSize(.small).tint(accent)

                Spacer()

                Button(action: onTest) {
                    Label("Test", systemImage: "play.fill")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accent)
            }
        }
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(rule.threshold) },
            set: { rule.threshold = Int($0.rounded()) }
        )
    }

    private func field<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

/// The row of selectable color circles.
private struct ColorSwatchPicker: View {
    @Binding var selection: AlertColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AlertColor.allCases) { color in
                Circle()
                    .fill(color.color)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle().strokeBorder(.white, lineWidth: selection == color ? 2 : 0)
                    )
                    .overlay(
                        Circle().strokeBorder(Color.settingsInsetStroke, lineWidth: 0.5)
                    )
                    .scaleEffect(selection == color ? 1.12 : 1)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.12)) { selection = color }
                    }
            }
        }
    }
}

/// Center vs. Top, as two icon toggles.
private struct PositionPicker: View {
    @Binding var selection: AlertPosition

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AlertPosition.allCases) { position in
                Button {
                    selection = position
                } label: {
                    Image(systemName: position.systemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(selection == position ? .white : .secondary)
                        .frame(width: 40, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection == position ? Color.settingsSelectionFill : Color.settingsInsetFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(selection == position ? Color.settingsSelectionStroke : Color.settingsInsetStroke)
                        )
                }
                .buttonStyle(.plain)
                .help(position.label)
            }
        }
    }
}

/// Sound chooser: system presets (previewed on selection) plus custom import.
/// Bound directly to an `AlertSound` so it works for alert rules and power-source
/// alerts alike.
struct SoundPickerMenu: View {
    @Binding var sound: AlertSound
    var maxWidth: CGFloat = 320
    @State private var importError: String?

    var body: some View {
        Menu {
            ForEach(AlertSound.presets, id: \.self) { option in
                Button {
                    sound = option
                    SoundPreview.play(option)
                } label: {
                    Label(option.label, systemImage: sound == option ? "checkmark" : "")
                }
            }
            if case .custom = sound {
                Divider()
                Button {
                    SoundPreview.play(sound)
                } label: {
                    Label("\(sound.label) (current)", systemImage: "checkmark")
                }
                if !sound.isAvailable {
                    // Entry points at a file that no longer resolves — either
                    // the user deleted the stored copy or it predates sounds
                    // being copied into the container.
                    Button {
                        sound = .none
                        importError = nil
                    } label: {
                        Label("Sound file is missing — use No Sound", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            Divider()
            Button {
                importCustomSound()
            } label: {
                Label("Import Custom Sound…", systemImage: "square.and.arrow.down")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: sound.isNone ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                Text(sound.label)
                if case .custom = sound, !sound.isAvailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.settingsInsetFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.settingsInsetStroke)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: maxWidth)
        .alert(
            "Couldn't Import Sound",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importCustomSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, .aiff, .mpeg4Audio, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Sound"
        panel.message = "Choose an audio file for this alert (MP3, WAV, M4A, AIFF)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Copy into the container rather than storing the picked path: the
        // sandbox grant on `url` does not survive relaunch, so a bare path
        // would silently stop playing.
        switch AlertSoundLibrary.importSound(from: url) {
        case .imported(let path):
            sound = .custom(path)
            SoundPreview.play(sound)
        case .tooLarge(let bytes):
            importError = "That file is \(Format.bytes(bytes)). Alert sounds must be under \(Format.bytes(AlertSoundLibrary.maxImportBytes))."
        case .failed(let reason):
            importError = "Could not import that sound: \(reason)"
        }
    }
}

/// Plays a sound once for previewing in the editor. Retains the instance so it
/// isn't deallocated mid-playback.
@MainActor
enum SoundPreview {
    static var active: NSSound?

    static func play(_ sound: AlertSound) {
        let ns: NSSound?
        switch sound {
        case .none: return
        case .system(let name): ns = NSSound(named: name)
        case .custom(let path): ns = NSSound(contentsOfFile: path, byReference: true)
        }
        guard let ns else { return }
        active = ns
        ns.stop()
        ns.play()
    }
}
