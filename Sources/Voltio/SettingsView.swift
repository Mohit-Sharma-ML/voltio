import AppKit
import PowerCore
import SwiftUI
import UniformTypeIdentifiers

/// The app window — a dark, card-based settings layout (General / Alerts / Menu
/// Bar / Devices / About) opened from the panel footer or the Dock icon.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: BatteryModel

    @State private var selection: Pane? = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general, alerts, menuBar, devices, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .alerts: return "Alerts"
            case .menuBar: return "Menu Bar"
            case .devices: return "Devices"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .alerts: return "bell.fill"
            case .menuBar: return "menubar.rectangle"
            case .devices: return "ipad.and.iphone"
            case .about: return "info"
            }
        }

        var tint: Color {
            switch self {
            case .general: return .green
            case .alerts: return .green
            case .menuBar: return .teal
            case .devices: return .blue
            case .about: return .indigo
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach([Pane.general, .alerts, .menuBar, .devices]) { pane in
                    sidebarRow(pane).tag(pane)
                }
                Section("Voltio") {
                    sidebarRow(.about).tag(Pane.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 198, ideal: 208, max: 230)
            .scrollContentBackground(.hidden)
            .background(Color.settingsSidebarBG)
            .safeAreaInset(edge: .bottom) {
                SidebarStatusCard(model: model)
            }
        } detail: {
            detail
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 620)
        .preferredColorScheme(settings.preferredAppearance.colorScheme)
        .tint(.green)
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .general {
        case .general: GeneralSettingsView(settings: settings, model: model)
        case .alerts: AlertsSettingsView(settings: settings, model: model)
        case .menuBar: MenuBarSettingsView(settings: settings, model: model)
        case .devices: DevicesSettingsView(settings: settings, model: model)
        case .about: AboutSettingsView(model: model)
        }
    }

    private func sidebarRow(_ pane: Pane) -> some View {
        HStack(spacing: 10) {
            SquareIconBadge(systemName: pane.symbol, tint: pane.tint, size: 24)
            Text(pane.title).font(.body)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sidebar status

/// A compact live battery readout pinned to the bottom of the sidebar.
struct SidebarStatusCard: View {
    let model: BatteryModel

    var body: some View {
        HStack(spacing: 10) {
            if let s = model.snapshot {
                Image(systemName: model.menuBarSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(s.stateColor)
                    .glow(s.stateColor, radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(s.percentage)%")
                        .font(.callout.weight(.bold))
                        .monospacedDigit()
                    Text(s.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "bolt.slash")
                    .foregroundStyle(.secondary)
                Text("Reading…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .padding(10)
    }
}
