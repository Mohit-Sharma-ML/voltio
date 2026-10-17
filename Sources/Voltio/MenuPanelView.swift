import AppKit
import SwiftUI
import PowerCore

/// The full battery panel: a bold hero plus color-coded information cards.
struct MenuPanelView: View {
    let model: BatteryModel
    /// Needed for the per-device pin indicator; injected at the call site.
    var settings: AppSettings? = nil

    /// Battery Information is collapsible (compact by default) so the
    /// panel stays short and never reaches the Dock. Persisted via `AppSettings`
    /// (migrated from the former raw `@AppStorage("expandBatteryInfo")`) so the
    /// ⇧⌘I global shortcut toggles the same flag the header tap does.
    private var showDetails: Bool { settings?.expandBatteryInfo ?? false }
    /// Ideal height reported by the content (via an idealSize background read);
    /// the ScrollView proposes this to the window so it hugs the content and
    /// still shrinks when Battery Information collapses.
    @State private var idealHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = model.snapshot {
                ScrollView {
                    contentStack(snapshot)
                }
                .defaultScrollAnchor(.top)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(idealHeight > 0 ? idealHeight : 300, maxContentHeight))
            } else {
                errorState
            }

            Divider().overlay(Color.white.opacity(0.06))
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                MenuPanelWindowSizer(contentSize: geometry.size)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.panelTop, Color.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Panel inherits the app appearance (System/Light/Dark) when settings
        // are injected; falls back to the system look when settings is nil.
        .preferredColorScheme(settings?.preferredAppearance.colorScheme ?? nil)
    }

    /// The whole "Battery Information" group: collapsible header plus the
    /// detail cards it reveals.
    @ViewBuilder
    private func batteryInfoSection(_ s: BatterySnapshot) -> some View {
        batteryInfoHeader

        if showDetails {
            healthCard(s)
            temperatureCard(s)
            powerCard(s)
            flowCard(s)
            capacityCard(s)
            batteryConditionCard(s)
            energyCard
            energyAppsCard
            specsCard(s)
            updatedLine
        }
    }

    /// Tappable "Battery Information" header that expands/collapses the detail cards.
    private var batteryInfoHeader: some View {
        Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { settings?.expandBatteryInfo.toggle() }
        } label: {
            HStack {
                SectionHeader(title: "Battery Information")
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showDetails ? 0 : -90))
                    .animation(.easeInOut(duration: 0.22), value: showDetails)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }


    /// The scrollable panel content, extracted so the same stack can be measured
    /// (ideal size) and rendered inside the ScrollView.
    private func contentStack(_ s: BatterySnapshot) -> some View {
        VStack(spacing: 12) {
            hero(s)

            // Above the fold: macOS charging management state (native Charge
            // Limit or an Optimized Charging hold) — the expanded Battery
            // Information section is collapsed by default, so this hint keeps
            // the "why isn't it charging past 80?" answer visible at a glance.
            chargeManagementHint(s)

            // Sections stack in the user's chosen order
            // (Settings → Menu Bar → Panel Sections).
            ForEach(settings?.orderedPanelSections ?? AppSettings.PanelSection.allCases) { section in
                switch section {
                case .batteryInfo:
                    batteryInfoSection(s)
                case .devices:
                    devicesSection
                }
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { idealHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, new in idealHeight = new }
            }
        )
    }

    /// Reserve space for the footer and window margins outside the scroll area.
    private var maxContentHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 760
        return max(300, visible - 86)
    }

    private var errorState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(model.lastError ?? "Reading battery…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }

    private var footer: some View {
        HStack {
            Text("\(AppInfo.name) \(AppInfo.version)")
                .foregroundStyle(.tertiary)
            Spacer()
            HStack(spacing: 16) {
                Button { SettingsLauncher.open() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button { model.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit", systemImage: "power")
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }


}
