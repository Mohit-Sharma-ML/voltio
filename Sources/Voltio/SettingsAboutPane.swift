import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - About pane (split from SettingsView.swift)

struct AboutSettingsView: View {
    let model: BatteryModel
    @State private var showWhatsNew = false

    var body: some View {
        SettingsPane(icon: "info", tint: .indigo, title: "About") {
            VStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text(AppInfo.name).font(.title.weight(.bold))
                Text("Version \(AppInfo.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("A native macOS battery & power monitor — health, power flow and accessory battery, right from the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.bottom, 4)

                SettingsCard {
                    SettingsRow(
                        icon: "sparkles", tint: .pink,
                        title: "What's New",
                        subtitle: "Recent changes and features"
                    ) {
                        Button("Show") { showWhatsNew = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    RowDivider()
                    SettingsRow(
                        icon: "battery.100percent", tint: .green,
                        title: "macOS Battery Settings",
                        subtitle: "Open the system battery preferences"
                    ) {
                        Button("Open") { openBatterySettings() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    RowDivider()
                    SettingsRow(
                        icon: "doc.text", tint: .blue,
                        title: "Export Diagnostics",
                        subtitle: "Save a battery & settings report to share"
                    ) {
                        Button("Export") { exportDiagnostics() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet { showWhatsNew = false }
        }
    }

    private func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            NSWorkspace.shared.open(url)
        }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Voltio-Diagnostics.txt"
        panel.title = "Export Diagnostics"
        if panel.runModal() == .OK, let url = panel.url {
            try? Diagnostics.report(model: model).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// A short, in-app changelog shown from About → What's New.
private struct WhatsNewSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2).foregroundStyle(.pink)
                Text("What's New in \(AppInfo.name)").font(.title2.weight(.bold))
                Spacer()
            }
            Text("Version \(AppInfo.version)")
                .font(.callout).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                bullet("On-screen alert bubbles you can place, color and sound")
                bullet("Add unlimited low-battery and charged alerts")
                bullet("Power-source alerts when you plug in or unplug")
                bullet("Per-device battery alerts and hide-from-menu-bar")
                bullet("Custom alert sounds and adjustable bubble size & glow")
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440, height: 340)
        .background(Color.settingsDetailBG)
        // No explicit colorScheme pin: the sheet follows the app appearance
        // (NSApp.appearance / window appearance) like the rest of Settings.
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
    }
}

/// Builds a plain-text diagnostics report (battery snapshot + key settings).
enum Diagnostics {
    @MainActor
    static func report(model: BatteryModel) -> String {
        var lines: [String] = []
        lines.append("\(AppInfo.name) \(AppInfo.version) — Diagnostics")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        if let s = model.snapshot {
            lines.append("Battery")
            lines.append("  Charge: \(s.percentage)%")
            lines.append("  State: \(s.isCharging ? "Charging" : (s.isPluggedIn ? "Plugged in" : "On battery"))")
            lines.append("  Health: \(s.healthPercent)% (\(s.cycleCount)/\(s.designCycleCount) cycles)")
            lines.append("  Temperature: \(String(format: "%.1f", s.temperatureCelsius))°C")
            lines.append("  Voltage: \(String(format: "%.2f", s.voltage)) V  Amperage: \(s.amperage) mA")
            lines.append("  Capacity: \(s.currentCapacitymAh)/\(s.maxCapacitymAh) of \(s.designCapacitymAh) mAh (design)")
            if let m = s.minutesRemaining { lines.append("  Time remaining: \(Format.minutes(m))") }
        } else {
            lines.append("Battery: \(model.lastError ?? "no reading")")
        }
        lines.append("")
        lines.append("Connected devices")
        if model.peripherals.isEmpty {
            lines.append("  none")
        } else {
            for d in model.peripherals {
                lines.append("  \(d.name): \(d.minPercent.map { "\($0)%" } ?? "—")")
            }
        }
        return lines.joined(separator: "\n")
    }
}
