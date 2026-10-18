import AppKit
import SwiftUI
import PowerCore

/// The full battery panel: a bold hero plus color-coded information cards.
struct MenuPanelView: View {
    let model: BatteryModel
    /// Needed for the per-device pin indicator; injected at the call site.
    var settings: AppSettings? = nil

    /// The panel's active scheme — the single source of truth every color in
    /// the panel derives from (gradient here, everything else via the
    /// injected environment below).
    @State private var observedSystemScheme: ColorScheme = .light
    /// KVO token for NSApp.effectiveAppearance (Match System mode).
    @State private var appearanceObservation: Any?

    var activeScheme: ColorScheme {
        switch settings?.preferredAppearance ?? .system {
        case .system: return observedSystemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Current system scheme, nil-safe for bare test processes (NSApp is an
    /// implicitly unwrapped optional that is nil without NSApplication).
    private static func currentSystemScheme(from app: NSApplication? = nil) -> ColorScheme {
        let app = app ?? NSApp
        guard let app else { return .light }
        return app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark : .light
    }

    /// Installs a KVO observer on NSApp.effectiveAppearance (once). Called
    /// from `.onAppear` — NOT from body: writing @State while SwiftUI is
    /// mid-view-update is discarded, which is exactly the bug that froze
    /// Match System on light. The KVO handler hops asynchronously onto the
    /// main actor so the state write never lands mid-update either.
    private func installSystemAppearanceObserver() {
        // Pin the panel window's appearance FIRST — on every panel open.
        // The panel lives in SwiftUI's `MenuBarExtraWindow` (level 101, above
        // the status item's NSStatusBarWindow at level 25). That window does
        // not reliably follow the NSApp appearance cascade: after the user
        // flips Light → Dark, it keeps resolving semantic colors (system
        // green, etc.) with their LIGHT variants while every scheme-explicit
        // surface renders dark — the "Dark looks washed" bug. Re-pinning the
        // window's appearance on open guarantees the whole window resolves
        // under the preference's appearance. (Must run even when the KVO
        // observer below is already installed — the window is recreated each
        // time the panel opens.)
        if let panelWindow = NSApp.windows.first(where: {
            $0.className.contains("MenuBarExtraWindow") && $0.level.rawValue == 101
        }) {
            panelWindow.appearance = settings?.preferredAppearance.nsAppearanceName.flatMap { NSAppearance(named: $0) }
        }
        guard appearanceObservation == nil, NSApp != nil else { return }
        observedSystemScheme = Self.currentSystemScheme()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { app, _ in
            Task { @MainActor in
                observedSystemScheme = Self.currentSystemScheme(from: app)
            }
        }
    }

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

            Divider().overlay(Color.primary.opacity(activeScheme == .light ? 0.12 : 0.08))
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
        .onAppear { installSystemAppearanceObserver() }
        .background(
            LinearGradient(
                colors: [Color.panelTop(activeScheme), Color.panelBottom(activeScheme)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // The MenuBarExtra hosting window is system-owned and ignores
        // `preferredColorScheme` (and window-appearance cascades) for a LIVE
        // panel — so the scheme is injected directly into the environment.
        // Explicit Light/Dark pins the scheme; Match System falls through to
        // the environment's own value (which tracks the system appearance and
        // re-renders when the system theme flips). Every color in the panel is
        // semantic (primary-based) or scheme-explicit, so this one modifier
        // drives the whole theme in real time.
        .environment(\.colorScheme, activeScheme)
        .environment(\.panelScheme, activeScheme)
        // Re-key the entire panel on scheme change. The MenuBarExtra hosting
        // window lags behind scheme flips: after Light → Dark, SwiftUI keeps
        // rendering some views with light-resolved colors (darkened greens,
        // washed pill) while scheme-explicit surfaces already render dark —
        // a mixed frame that persists until an unrelated full re-render.
        // Changing identity discards every cached render state and rebuilds
        // the panel from scratch under the new scheme, so all colors resolve
        // in one pass.
        .id(activeScheme)
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
