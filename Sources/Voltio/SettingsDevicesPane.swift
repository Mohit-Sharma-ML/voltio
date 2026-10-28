import AppKit
import PowerCore
import SwiftUI

// MARK: - Devices pane (split from SettingsView.swift)

struct DevicesSettingsView: View {
    @Bindable var settings: AppSettings
    let model: BatteryModel

    /// Results of the last Platform Health run (empty until "Run Checks").
    @State private var healthChecks: [PlatformHealth.Check] = []
    @State private var healthRunAt: Date?

    var body: some View {
        SettingsPane(
            icon: "ipad.and.iphone", tint: .blue, title: "Devices",
            subtitle: "Monitor battery levels of your AirPods, Magic accessories and paired iPhone/iPad."
        ) {
            SettingsSection(
                icon: "dot.radiowaves.left.and.right", tint: .blue, title: "Bluetooth Devices"
            ) {
                SettingsRow(
                    icon: "dot.radiowaves.left.and.right", tint: .blue,
                    title: "Show Devices",
                    subtitle: "List paired devices and accessories in the menu-bar dropdown — including their last-known battery while offline"
                ) {
                    Toggle("", isOn: $settings.showConnectedDevices).labelsHidden()
                }
            }

            SettingsSection(
                icon: "antenna.radiowaves.left.and.right", tint: .teal, title: "Detected Devices"
            ) {
                if model.peripherals.isEmpty {
                    SettingsRow(
                        icon: "dot.radiowaves.left.and.right", tint: .gray,
                        title: bluetoothTitle, subtitle: bluetoothSubtitle
                    ) {
                        // macOS never re-prompts after a denial, so a text-only row has no way back.
                        if model.bluetoothAccess == .denied {
                            Button("Open Settings") {
                                BluetoothPrivacySettings.open()
                            }
                            .controlSize(.small)
                        }
                    }
                } else {
                    ForEach(Array(model.peripherals.enumerated()), id: \.element.id) { index, device in
                        DeviceSettingsRow(settings: settings, model: model, device: device)
                        if index < model.peripherals.count - 1 { RowDivider() }
                    }
                }
            }

            deviceLegend

            developerDiagnostics

            SettingsSection(icon: "questionmark.circle.fill", tint: .gray, title: "Troubleshooting") {
                troubleshootingRow(
                    "My iPhone or accessory isn't showing up",
                    "Pair it in System Settings → Bluetooth and keep it in range. AirPods only appear when in use near this Mac."
                )
                RowDivider()
                troubleshootingRow(
                    "Mouse/keyboard appear without Bluetooth permission",
                    "Magic accessories are read over USB/HID and need no permission. AirPods battery requires Bluetooth access."
                )
                RowDivider()
                troubleshootingRow(
                    "A device shows as offline",
                    "Voltio keeps showing the last battery it read, greyed out, after a device disconnects. It updates live again on reconnect, or is forgotten after two weeks."
                )
            }
        }
    }

    /// Developer Mode: BLE scan pipeline counters, platform health checks,
    /// and a fake battery override for exercising alerts without draining
    /// the real battery.
    @ViewBuilder private var developerDiagnostics: some View {
        if settings.developerMode {
            let d = model.bleDiagnostics
            SettingsSection(icon: "wrench.and.screwdriver.fill", tint: .orange, title: "Developer") {
                SettingsRow(
                    icon: "wrench.and.screwdriver.fill", tint: .orange,
                    title: "Fake Battery Percent",
                    subtitle: "Override the reported battery level across the whole UI. Clear to return to live readings"
                ) {
                    TextField("Live", value: $settings.fakeBatteryPercent, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .textFieldStyle(.roundedBorder)
                }
                RowDivider()
                SettingsRow(
                    icon: "antenna.radiowaves.left.and.right", tint: .blue,
                    title: "BLE Advertisements",
                    subtitle: "Seen: \(d.advertsSeen) · Decoded: \(d.advertsDecoded) · Weak RSSI: \(d.rejectedWeakRSSI) · Not Continuity: \(d.rejectedNotContinuity) · No batteries: \(d.rejectedNoBatteries) · Hidden by ownership: \(d.hiddenByOwnership) (paired addresses known: \(d.knownOwnerSuffixes))"
                ) { EmptyView() }
                RowDivider()
                SettingsRow(
                    icon: "link", tint: .teal,
                    title: "GATT Devices",
                    subtitle: "Connected exposing Battery Service: \(d.gattDevicesSeen) · Battery reads: \(d.gattReads)"
                ) { EmptyView() }
                RowDivider()
                SettingsRow(
                    icon: "circle.lefthalf.filled", tint: .indigo,
                    title: "Appearance Resolution",
                    subtitle: appearanceResolutionText
                ) { EmptyView() }
                RowDivider()
                platformHealthSection
            }
        }
    }

    /// Platform health: pass/fail per fragile platform seam. Runs on
    /// demand via the refresh button — never on a polling path.
    @ViewBuilder private var platformHealthSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Platform Health").font(.callout.weight(.medium))
                Text(healthSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                healthChecks = PlatformHealth.runChecks(bluetoothAccess: model.bluetoothAccess)
                healthRunAt = Date()
            } label: {
                Label("Run Checks", systemImage: "stethoscope")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)

        ForEach(healthChecks) { check in
            HStack(spacing: 8) {
                Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(check.passed ? .green : .red)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.name).font(.caption.weight(.medium))
                    Text(check.detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.leading, 4)
        }

        if let runAt = healthRunAt {
            Text("Checked \(runAt.formatted(date: .omitted, time: .standard)) · run after a macOS update")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var healthSummary: String {
        guard !healthChecks.isEmpty else {
            return "Pass/fail per fragile platform seam — run after a macOS update"
        }
        let passed = healthChecks.filter(\.passed).count
        return passed == healthChecks.count
            ? "All \(healthChecks.count) checks passing"
            : "\(passed)/\(healthChecks.count) passing — a failing check points at the seam to investigate"
    }

    /// Live appearance-resolution readout: what the app thinks the scheme is
    /// right now, from each of the three sources that must agree. Used to
    /// diagnose Match System vs explicit Dark rendering differences.
    private var appearanceResolutionText: String {
        let pref = settings.preferredAppearance.rawValue
        let appAppearance = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? "dark" : "light"
        return "preference=\(pref) · NSApp=\(appAppearance) · panel resolves via pref"
    }

    private var deviceLegend: some View {
        VStack(alignment: .leading, spacing: 9) {
            legendRow("bell.fill", "Tap the bell on a device to set its own battery alert.")
            legendRow("pin.fill", "Pin a device to the menu bar: its battery shows next to your Mac's, even with the panel closed.")
            legendRow("eye.slash.fill", "Tap the eye to hide a device from the menu bar.")
            legendRow("moon.zzz.fill", "Offline devices stay listed with their last-known battery; tap the trash to forget one.")
            legendRow("arrow.up.arrow.down", "Connected devices come first, ranked by battery level, lowest first.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.settingsCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.settingsCardStroke)
        )
    }

    private func legendRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .frame(width: 16)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func troubleshootingRow(_ title: String, _ body: String) -> some View {
        DisclosureGroup {
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text(title).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .tint(.secondary)
    }

    private var bluetoothTitle: String {
        switch model.bluetoothAccess {
        case .denied: return "Bluetooth access denied"
        case .awaitingPermission: return "Bluetooth permission pending"
        case .poweredOff: return "Bluetooth is off"
        case .scanning, .unavailable: return "No accessories nearby"
        }
    }

    private var bluetoothSubtitle: String {
        switch model.bluetoothAccess {
        case .denied:
            return "macOS won't ask again. Enable Voltio under System Settings → Privacy & Security → Bluetooth."
        case .awaitingPermission:
            return "macOS will ask for Bluetooth access; AirPods and accessory battery need it."
        case .poweredOff: return "Turn on Bluetooth to detect accessories."
        case .scanning, .unavailable: return "No accessories with a battery detected nearby."
        }
    }
}

/// One device row in the Devices pane: battery readout plus a per-device alert
/// (bell → popover) and a hide-from-menu-bar toggle (eye).
private struct DeviceSettingsRow: View {
    @Bindable var settings: AppSettings
    let model: BatteryModel
    let device: PeripheralDevice
    @State private var showAlertConfig = false

    var body: some View {
        HStack(spacing: 12) {
            SquareIconBadge(systemName: device.kind.symbol, tint: device.isConnected ? .blue : .gray, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.body.weight(.medium))
                if !device.isConnected {
                    Text("Offline · last seen \(Format.relative(device.lastSeen))")
                        .font(.caption).foregroundStyle(.secondary)
                } else if device.batteries.count > 1 {
                    Text(compartments).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 10)

            if let percent = device.minPercent {
                HStack(spacing: 3) {
                    // One pod in the case: name the compartment, or the number reads as the whole device's charge.
                    if let sole = device.soleCompartment {
                        Text(sole.shortLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(percent)%")
                        .font(.body.weight(.bold))
                        .foregroundStyle(device.isConnected ? device.tint : .secondary)
                        .monospacedDigit()
                }
            }

            Button { showAlertConfig.toggle() } label: {
                Image(systemName: alertEnabled ? "bell.fill" : "bell")
                    .font(.system(size: 13))
                    .foregroundStyle(alertEnabled ? Color.orange : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Battery alert for this device")
            .popover(isPresented: $showAlertConfig, arrowEdge: .bottom) { alertPopover }

            Button {
                settings.setDevicePinned(device.id, !pinned)
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundStyle(pinned ? Color.blue : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(pinned ? "Pinned to menu bar" : "Pin to menu bar")

            Button {
                settings.setDeviceHidden(device.id, !hidden)
            } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .foregroundStyle(hidden ? Color.secondary : Color.blue)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(hidden ? "Hidden from menu bar" : "Shown in menu bar")

            if !device.isConnected {
                Button { model.forget(device) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Forget this device")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .opacity(hidden || !device.isConnected ? 0.6 : 1)
    }

    private var hidden: Bool { settings.isDeviceHidden(device.id) }

    private var pinned: Bool { settings.isDevicePinned(device.id) }
    private var config: DeviceAlertConfig { settings.effectiveDeviceAlert(device.id) }
    private var alertEnabled: Bool { config.enabled }

    private var compartments: String {
        device.batteries
            .map { "\($0.label ?? ""): \($0.percent)%" }
            .joined(separator: "   ")
    }

    private var alertPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(device.name).font(.headline)
            Toggle("Low battery alert", isOn: enabledBinding)
                .toggleStyle(.switch)
            if alertEnabled {
                HStack(spacing: 10) {
                    Text("Warn at").font(.callout)
                    Spacer()
                    Text("\(config.threshold)%")
                        .font(.callout.weight(.semibold)).monospacedDigit()
                    Stepper("", value: thresholdBinding, in: 5...50, step: 5).labelsHidden()
                }
                HStack(spacing: 10) {
                    Text("Color").font(.callout)
                    Spacer()
                    Picker("", selection: colorBinding) {
                        Text("Default").tag(AlertColor?.none)
                        ForEach(AlertColor.allCases) { color in
                            Circle()
                                .fill(color.color)
                                .frame(width: 11, height: 11)
                                .tag(AlertColor?.some(color))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 88)
                    .appearanceAdaptivePicker()
                }
                HStack(spacing: 10) {
                    Text("Sound").font(.callout)
                    Spacer()
                    Picker("", selection: soundBinding) {
                        Text("Default").tag(AlertSound?.none)
                        ForEach(AlertSound.presets, id: \.self) { sound in
                            Text(sound.label).tag(AlertSound?.some(sound))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .appearanceAdaptivePicker()
                }
            }
            Text("Overrides the global accessory default for this device.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 264)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { config.enabled },
            set: { settings.deviceAlerts[device.id] = DeviceAlertConfig(enabled: $0, threshold: config.threshold, color: config.color, sound: config.sound) }
        )
    }

    private var thresholdBinding: Binding<Int> {
        Binding(
            get: { config.threshold },
            set: { settings.deviceAlerts[device.id] = DeviceAlertConfig(enabled: config.enabled, threshold: $0, color: config.color, sound: config.sound) }
        )
    }

    private var colorBinding: Binding<AlertColor?> {
        Binding(
            get: { config.color },
            set: { settings.deviceAlerts[device.id] = DeviceAlertConfig(enabled: config.enabled, threshold: config.threshold, color: $0, sound: config.sound) }
        )
    }

    private var soundBinding: Binding<AlertSound?> {
        Binding(
            get: { config.sound },
            set: { settings.deviceAlerts[device.id] = DeviceAlertConfig(enabled: config.enabled, threshold: config.threshold, color: config.color, sound: $0) }
        )
    }
}
