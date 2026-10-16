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

    /// Compact, always-visible line explaining macOS's charging management:
    /// the native Charge Limit when set, or a one-word pointer to the hold
    /// state shown in the status pill ("Paused by macOS"). Hidden when macOS
    /// isn't managing charging at all.
    @ViewBuilder private func chargeManagementHint(_ s: BatterySnapshot) -> some View {
        let limitLabel = s.chargeLimitLabel(limit: model.chargeLimit)
        if let limitLabel {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.needle")
                    .font(.caption2)
                    .foregroundStyle(.mint)
                Text(limitLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if s.isPausedByMacOS {
            HStack(spacing: 5) {
                Image(systemName: "bolt.pause.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("macOS is holding the charge (Optimized Charging)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    // MARK: - Hero

    private func hero(_ s: BatterySnapshot) -> some View {
        VStack(spacing: 12) {
            BatteryRing(
                level: Double(s.percentage) / 100,
                percentage: s.percentage,
                tint: s.stateColor,
                isCharging: s.isCharging
            )

            StatusPill(text: s.statusText, systemName: s.statusIcon, tint: s.stateColor)

            if let minutes = s.minutesRemaining {
                Text(timeText(s, minutes: minutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.cardFill)
                RadialGradient(
                    colors: [s.stateColor.opacity(0.16), .clear],
                    center: .center,
                    startRadius: 6,
                    endRadius: 160
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(s.stateColor.opacity(0.20))
        )
    }

    // MARK: - Cards

    private func healthCard(_ s: BatterySnapshot) -> some View {
        HStack(spacing: 12) {
            IconBadge(
                systemName: s.isHealthGood ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: s.healthColor
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Battery Health").font(.callout.weight(.medium))
                    InfoButton(text: "Maximum charge your battery can now hold versus when it was new. Below ~80% macOS may recommend service.")
                    Spacer()
                    Text("\(s.healthPercent)%")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(s.healthColor)
                        .glow(s.healthColor, radius: 3)
                }
                FillBar(value: Double(s.healthPercent) / 100, tint: s.healthColor, height: 5)
                HStack {
                    Text(s.healthLabel).font(.caption).foregroundStyle(s.healthColor)
                    Spacer()
                    Text("\(s.cycleCount)/\(s.designCycleCount) cycles")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func temperatureCard(_ s: BatterySnapshot) -> some View {
        let status = s.temperatureStatus
        return HStack(spacing: 12) {
            IconBadge(systemName: "thermometer.medium", tint: status.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Temperature").font(.callout.weight(.medium))
                    InfoButton(text: "Battery pack temperature. Sustained high temperatures speed up wear; under ~35°C is ideal.")
                }
                Text("\(status.label) · optimal performance")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.1f°C", s.temperatureCelsius))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(status.color)
                Text(String(format: "%.0f°F", s.temperatureFahrenheit))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func powerCard(_ s: BatterySnapshot) -> some View {
        let verdict = s.electricalVerdict
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                cardTitle("Power & Electrical", systemImage: "bolt.fill", tint: .yellow)
                Spacer()
                InfoButton(text: "Live power draw, pack voltage and current. A down arrow means the battery is discharging; up means charging.")
            }
            HStack(alignment: .top) {
                statBlock("Power Usage", Format.watts(abs(s.powerWatts)))
                Spacer()
                statBlock("Voltage", String(format: "%.2f V", s.voltage), trailing: true)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("\(abs(s.amperage)) mA").font(.callout.weight(.semibold))
                        Image(systemName: s.currentDirectionIcon)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(verdict.color)
                    }
                }
                Spacer()
                Text(verdict.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(verdict.color)
            }
        }
        .card()
    }

    private func flowCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                cardTitle("Power Flow", systemImage: "bolt.horizontal.circle.fill", tint: .teal)
                Spacer()
                InfoButton(text: "Where energy is moving right now — out of the battery to power the Mac, or into the battery while charging.")
            }
            PowerFlowView(flow: s.powerFlow)
        }
        .card()
    }

    private func statBlock(_ label: String, _ value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold))
        }
    }

    private func capacityCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                cardTitle("Capacity", systemImage: "battery.100percent", tint: .green)
                InfoButton(text: "Charge stored now (remaining) vs. the most it can hold today (full charge) vs. its original factory capacity (design).")
                Spacer()
                Text("mAh").font(.caption2).foregroundStyle(.secondary)
            }
            capacityBar(s)
            HStack(alignment: .top) {
                capacityStat("Remaining", s.currentCapacitymAh, .green)
                Spacer()
                capacityStat("Full charge", s.maxCapacitymAh, .primary)
                Spacer()
                capacityStat("Design", s.designCapacitymAh, .secondary)
            }
        }
        .card()
    }

    private func capacityBar(_ s: BatterySnapshot) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let design = Double(s.designCapacitymAh)
            let fullFraction = design > 0 ? Double(s.maxCapacitymAh) / design : 0
            let currentFraction = design > 0 ? Double(s.currentCapacitymAh) / design : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(Color.primary.opacity(0.20))
                    .frame(width: width * min(1, fullFraction))
                Capsule().fill(Color.green)
                    .frame(width: width * min(1, currentFraction))
            }
        }
        .frame(height: 8)
    }

    /// Charging-condition note: why a plugged-in battery isn't charging, plus a
    /// Low Power Mode chip. Collapses into the expanded detail cards.
    @ViewBuilder private func batteryConditionCard(_ s: BatterySnapshot) -> some View {
        if s.isLowPowerMode || s.notChargingReason != nil {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: s.isLowPowerMode ? "bolt.badge.a" : "pause.circle.fill",
                    tint: .yellow
                )
                VStack(alignment: .leading, spacing: 2) {
                    if s.isLowPowerMode {
                        Text("Low Power Mode is on").font(.callout.weight(.medium))
                    }
                    if let reason = s.notChargingReason {
                        Text("Not charging — \(reason.explanation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .card()
        }
        chargeLimitCard(s)
    }

    /// Native charge-limit awareness: shows the macOS-configured Charge Limit
    /// (System Settings → Battery) when one is set, with a deep-link button.
    /// Read-only — Voltio deliberately doesn't (and can't) set the limit;
    /// see Docs/gap2-charge-limit.md.
    @ViewBuilder private func chargeLimitCard(_ s: BatterySnapshot) -> some View {
        if let label = s.chargeLimitLabel(limit: model.chargeLimit) {
            HStack(spacing: 12) {
                IconBadge(systemName: "gauge.with.needle", tint: .mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.callout.weight(.medium))
                    Text("Set in System Settings → Battery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Battery settings")
            }
            .card()
        }
    }

    /// Today's accumulated energy (trapezoid integral over sampled power) and
    /// the smoothed live draw. Appears once two samples exist; hidden entirely
    /// when the ⇧⌘E toggle (or its Settings row) turns it off.
    @ViewBuilder private var energyCard: some View {
        if settings?.showEnergyCard != false, let today = model.todayEnergy {
            HStack(spacing: 12) {
                IconBadge(systemName: "gauge.with.dots.needle.33percent", tint: .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Energy Today").font(.callout.weight(.medium))
                    Text("Sampled over \(Int(today.sampledMinutes.rounded())) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.2f Wh", today.wattHours))
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.teal)
                    if let watts = model.smoothedPowerWatts {
                        Text(String(format: "%.1f W avg", watts))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .card()
        }
    }

    /// Per-app energy attribution, sampled only while on battery. Hidden until
    /// the first two sampler ticks produce data; when the OS energy counters
    /// are unavailable the figures carry a CPU-share estimate disclosure.
    @ViewBuilder private var energyAppsCard: some View {
        if settings?.showEnergyApps != false, !model.energyApps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    IconBadge(systemName: "bolt.horizontal.circle", tint: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apps Using Energy").font(.callout.weight(.medium))
                        Text(model.energyAppsMeasured
                             ? "Sampled over the last few minutes"
                             : "Estimated from CPU share")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.energyApps.prefix(5)) { app in
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(app.method == .cpuShare ? "~" : "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f W", app.watts))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                if model.energyApps.count > 5 {
                    Text("+\(model.energyApps.count - 5) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    /// Hardware identity: pack serial number and manufacture date. Missing
    /// fields are simply omitted — many Macs don't expose both.
    @ViewBuilder private func specsCard(_ s: BatterySnapshot) -> some View {
        if s.serialNumber != nil || s.manufactureDate != nil {
            HStack(spacing: 12) {
                IconBadge(systemName: "info.circle", tint: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    if let serial = s.serialNumber {
                        HStack(spacing: 6) {
                            Text("Serial").font(.caption).foregroundStyle(.secondary)
                            Text(serial)
                                .font(.caption.weight(.medium).monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    if let made = s.manufactureDate {
                        HStack(spacing: 6) {
                            Text("Made").font(.caption).foregroundStyle(.secondary)
                            Text(made.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.medium))
                        }
                    }
                }
                Spacer()
            }
            .card()
        }
    }

    // MARK: - Smaller pieces

    private func cardTitle(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            IconBadge(systemName: systemImage, tint: tint, size: 24)
            Text(title).font(.callout.weight(.medium))
        }
    }

    private func capacityStat(_ label: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(Format.number(value))
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
        }
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

    // MARK: - Connected Devices

    @ViewBuilder private var devicesSection: some View {
        if model.showsConnectedDevices {
            SectionHeader(title: "Devices")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            if model.visiblePeripherals.isEmpty {
                devicesPlaceholder
            } else {
                ForEach(model.visiblePeripherals) { deviceRow($0) }
            }
        }
    }

    private func deviceRow(_ device: PeripheralDevice) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: device.kind.symbol, tint: device.isConnected ? .blue : .gray)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(device.name).font(.callout.weight(.medium)).lineLimit(1)
                    if device.isAnyCharging && device.isConnected {
                        Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green)
                    }
                    if let settings, settings.isDevicePinned(device.id) {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .help("Pinned to menu bar")
                    }
                    Spacer()
                    if let percent = device.minPercent {
                        Text("\(percent)%")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(device.isConnected ? device.tint : .secondary)
                    }
                }
                if device.isConnected {
                    if device.batteries.count > 1 {
                        HStack(spacing: 14) {
                            ForEach(device.batteries) { compartment($0) }
                            Spacer()
                        }
                    } else if let single = device.batteries.first {
                        FillBar(value: Double(single.percent) / 100, tint: single.tint, height: 5)
                    }
                } else {
                    Text("Last seen \(Format.relative(device.lastSeen))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
        .opacity(device.isConnected ? 1 : 0.55)
    }

    private func compartment(_ reading: BatteryReading) -> some View {
        HStack(spacing: 4) {
            Text(compartmentLabel(reading.label))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(reading.percent)%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(reading.tint)
            if reading.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
    }

    private func compartmentLabel(_ label: String?) -> String {
        switch label {
        case "Left": return "L"
        case "Right": return "R"
        default: return label ?? ""
        }
    }

    private var devicesPlaceholder: some View {
        let message: String
        switch model.bluetoothAccess {
        case .needsPermission:
            message = "Allow Bluetooth to see AirPods & accessory battery."
        case .poweredOff:
            message = "Bluetooth is off."
        case .scanning, .unavailable:
            message = "No accessories with battery nearby."
        }
        return HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .card()
    }

    @ViewBuilder private var updatedLine: some View {
        if let updated = model.lastUpdated {
            HStack(spacing: 4) {
                Text("Updated \(Format.relative(updated))")
                Text("·")
                Button { model.refresh() } label: {
                    Text("Refresh now").foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
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

    private func timeText(_ s: BatterySnapshot, minutes: Int) -> String {
        s.isCharging
            ? "Full in \(Format.minutes(minutes))"
            : "\(Format.minutes(minutes)) remaining"
    }
}

struct MenuPanelWindowSizer: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> SizingView {
        SizingView()
    }

    func updateNSView(_ view: SizingView, context: Context) {
        view.contentSize = contentSize
    }

    static func resize(_ window: NSWindow, to contentSize: CGSize) {
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        let size = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        let current = window.frame
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else {
            return
        }
        window.setFrame(
            CGRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    final class SizingView: NSView {
        var contentSize: CGSize = .zero {
            didSet { scheduleResize() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResize()
        }

        private func scheduleResize() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                MenuPanelWindowSizer.resize(window, to: contentSize)
            }
        }
    }
}

