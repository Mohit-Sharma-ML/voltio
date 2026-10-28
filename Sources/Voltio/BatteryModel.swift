import Foundation
import Observation
import PowerCore
import SwiftUI

/// Observable view-model that polls `PowerCore` on a timer and publishes the
/// latest snapshot to SwiftUI. Lives for the whole app lifetime.
@MainActor
@Observable
final class BatteryModel {
    /// Snapshot the rest of the app sees. When Developer Mode's fake battery
    /// percent is set, a copy with the overridden percentage is returned so the
    /// whole UI (menu bar, panel, alerts) exercises the simulated level.
    var snapshot: BatterySnapshot? {
        guard let fake = settings.fakeBatteryPercent, let live = _snapshot else { return _snapshot }
        return live.overridingPercentage(fake)
    }
    private var _snapshot: BatterySnapshot?

    /// The unmodified live reading (used for energy accounting, which should
    /// always reflect reality).
    private var liveSnapshot: BatterySnapshot? { _snapshot }
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?

    /// Merged list of connected accessories with battery (HID + Bluetooth).
    private(set) var peripherals: [PeripheralDevice] = []

    private let reader: BatteryReadingProviding
    private let hidReader = HIDBatteryReader()
    private let bluetooth = BluetoothBatteryScanner()
    private let history = DeviceHistoryStore()
    private let energy = EnergyStore()
    private let energyAppsSampler = EnergyAppsSampler()
    private var powerEstimator = PowerEstimator()
    /// Publishes battery/energy state to the widget extension via the App Group.
    private let widgetWriter: WidgetPublishing
    /// Native macOS charge-limit state (System Settings → Battery). Read-only.
    private let chargeLimitReader: ChargeLimitReading
    /// Injected sleep/wake notifier (tests); nil = create the IOKit one.
    private let sleepWakeNotifier: (any SleepWakeNotifying)?
    /// Injected sleep/wake notifier (tests); nil = create the IOKit one.
    /// Last known charge-limit configuration; refreshed on each battery tick.
    private(set) var chargeLimit: ChargeLimitState?
    private let settings: AppSettings
    private let alerts: AlertManager
    private var hidDevices: [PeripheralDevice] = []
    private var bleDevices: [PeripheralDevice] = []

    /// EMA-smoothed battery power in watts, for the power flow gauges.
    private(set) var smoothedPowerWatts: Double?

    /// Charging-glow phase for the menu-bar bolt (0–1). A timer advances it in
    /// a triangle wave only while plugged in, so the status item's halo
    /// "breathes"; on battery the timer is parked and the phase rests at 1.
    /// Observed by the menu-bar label — the only animation channel that
    /// actually re-renders a MenuBarExtra status item.
    private(set) var pulsePhase: Double = 1
    private var pulseTimer: Timer?

    /// Per-day energy history (oldest first), including today's running total.
    var energyHistory: [EnergyAggregator.DayTotal] { energy.dailyTotals }

    /// Today's accumulated energy use, once two samples exist.
    var todayEnergy: EnergyAggregator.DayTotal? { energy.todayTotal }

    /// Per-app energy attribution (highest draw first). Empty until two
    /// sampler ticks have run.
    var energyApps: [EnergyAppTracker.AppUsage] { energyAppsSampler.usage }

    /// True when per-app figures come from hardware energy counters rather
    /// than the CPU-share estimate.
    var energyAppsMeasured: Bool { energyAppsSampler.usesEnergyCounters }

    private var batteryPollTask: Task<Void, Never>?
    private var accessoryPollTask: Task<Void, Never>?
    private var powerMonitor: PowerSourceMonitor?
    /// Wake/sleep notifications, so alerts catch up on thresholds crossed while
    /// the Mac slept (poll timers are suspended during sleep).
    private var wakeObserver: (any SleepWakeNotifying)?

    /// Guards the heavier accessory read (IORegistry walk). Dropping an extra tick
    /// is fine here — the next accessory poll catches up.
    private var isReadingAccessories = false

    /// Coarse Bluetooth state for the Connected Devices section.
    var bluetoothAccess: BluetoothAccess { bluetooth.access }

    /// True once the Bluetooth radio has been brought up (i.e. the TCC prompt may have fired).
    var isBluetoothActivated: Bool { bluetooth.isActivated }

    /// BLE scan diagnostics (Settings → Devices, Developer Mode only).
    var bleDiagnostics: BLEDiagnostics { bluetooth.diagnostics }

    init(
        settings: AppSettings,
        reader: BatteryReadingProviding = BatteryReader(),
        widgetWriter: WidgetPublishing = WidgetSnapshotWriter(),
        chargeLimitReader: ChargeLimitReading = ChargeLimitReader(),
        sleepWakeNotifier: (any SleepWakeNotifying)? = nil,
        startMonitors: Bool = true
    ) {
        self.settings = settings
        self.sleepWakeNotifier = sleepWakeNotifier
        self.reader = reader
        self.widgetWriter = widgetWriter
        self.chargeLimitReader = chargeLimitReader
        self.alerts = AlertManager(
            settings: settings,
            sender: NotificationSender { [weak settings] in settings?.notificationsEnabled ?? false }
        )
        bluetooth.onUpdate = { [weak self] devices in
            self?.bleDevices = devices
            self?.recomputePeripherals()
        }
        // Synchronous first read so the menu bar shows real data the instant the
        // app appears; every subsequent read runs off the main thread.
        bootstrap()

        // Sleep/wake wiring is test-safe (an injected fake never touches
        // IOKit), so it runs regardless of startMonitors — the model's
        // sleep/wake behavior is part of the characterized surface.
        let observer: any SleepWakeNotifying = sleepWakeNotifier ?? SleepWakeObserver()
        observer.onSleep = { [weak self] in self?.handleSleep() }
        observer.onWake = { [weak self] in self?.handleWake() }
        observer.start()
        wakeObserver = observer

        guard startMonitors else { return }
        startPolling()

        // Instant updates on charger plug/unplug and level changes. This only
        // affects the Mac battery, so it drives the battery path — accessories
        // keep to their own slower timer.
        let monitor = PowerSourceMonitor { [weak self] in self?.refreshBattery() }
        monitor.start()
        powerMonitor = monitor
    }

    /// Sleep suspends the poll tasks and IOKit notifications, so the state the
    /// alert manager remembers is the pre-sleep one. Cache the last reading.
    private func handleSleep() {
        preSleepReading = _snapshot
        parkPulseTimer()
    }

    /// On wake, re-evaluate the battery immediately: the Mac may have crossed an
    /// alert threshold (or discharged significantly) while asleep. Bypasses the
    /// "only republish on change" gate so alerts run even when the reading
    /// happens to equal the pre-sleep one.
    private func handleWake() {
        guard let reading = try? reader.read() else {
            refresh()
            return
        }
        _snapshot = reading
        lastUpdated = Date()
        lastError = nil
        recordEnergy(for: reading)
        alerts.evaluate(reading)
        refreshAccessories()
        updatePulseTimer(charging: reading.isPluggedIn)
    }

    // MARK: Charging-glow pulse

    /// Runs the bolt-glow breathe cycle while plugged in. A true sine wave at
    /// ~12 fps: `pulsePhase` itself stays unquantized (smooth), while the
    /// raster cache key rounds it to 2 decimals so each distinct level renders
    /// once and repeats hit the cache — ~17 renders per 1.4s cycle, ~12/sec,
    /// each a tiny 33×24-pt bitmap.
    private func updatePulseTimer(charging: Bool) {
        if charging {
            guard pulseTimer == nil else { return }
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let t = Date().timeIntervalSinceReferenceDate
                    // Sine breathe: (1 − cos) maps 0→1→0 smoothly over 1.4s.
                    let wave = (1 - cos(t / 1.4 * 2 * .pi)) / 2
                    self.pulsePhase = wave
                }
            }
        } else {
            parkPulseTimer()
        }
    }

    /// Stops the pulse and restores the full-strength halo on battery or sleep.
    private func parkPulseTimer() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        if pulsePhase != 1 { pulsePhase = 1 }
    }

    /// Last reading before sleep; kept only so catch-up evaluation has a
    /// reference if the live read fails on wake.
    private var preSleepReading: BatterySnapshot?

    /// One blocking read at launch — acceptable a single time during startup, and
    /// it avoids a flash of placeholder data in the menu bar.
    private func bootstrap() {
        if let reading = try? reader.read() {
            _snapshot = reading
            lastUpdated = Date()
            alerts.evaluate(reading)
        }
        hidDevices = hidReader.read()
        // Bluetooth stays dormant until onboarding has explained the permission: creating the
        // central manager is what raises the system prompt.
        if settings.hasCompletedOnboarding {
            bluetooth.activate()
            bluetooth.startIfPossible()
            bluetooth.refreshConnectedDevices()
        }
        recomputePeripherals()
    }

    /// Called when onboarding finishes (or is skipped), so the Bluetooth prompt arrives after the
    /// step that explains it rather than during app launch.
    func activateBluetoothIfNeeded() {
        bluetooth.activate()
        bluetooth.startIfPossible()
        bluetooth.refreshConnectedDevices()
        recomputePeripherals()
    }

    /// Full manual refresh (used by the panel's refresh button): both the Mac
    /// battery and accessories.
    func refresh() {
        refreshBattery()
        refreshAccessories()
    }

    // MARK: - Battery (fast path)

    /// Reads the Mac's internal battery. This runs *synchronously on the main
    /// actor* on purpose: the read is cheap (a single IOKit service lookup) and
    /// must feel instant — pushing it to a background task added perceptible
    /// menu-bar lag on charger plug/unplug. The expensive accessory work (the
    /// recursive IORegistry walk + BLE) is what stays off-main.
    func refreshBattery() {
        do {
            let reading = try reader.read()
            // Only republish when it actually changed — keeps the menu-bar image
            // from re-rasterizing every poll on a steady battery.
            if reading != _snapshot {
                _snapshot = reading
                alerts.evaluate(reading)
            }
            lastUpdated = Date()
            lastError = nil
            recordEnergy(for: reading)
            refreshChargeLimit()
            updatePulseTimer(charging: reading.isPluggedIn)
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Reads the native charge-limit config (pmset + defaults). All I/O runs on
    /// a background queue — spawning `pmset` on the main runloop starves the
    /// IOPS MachPort callbacks and crashes `MainActor.assumeIsolated` (verified
    /// 2026-10-16: crashes ~60 s after launch when read inline on the tick).
    /// Republished only on change.
    private func refreshChargeLimit() {
        chargeLimitIOQueue.async { [weak self] in
            guard let self else { return }
            let state = self.chargeLimitReader.read()
            Task { @MainActor [weak self] in
                guard let self, state != self.chargeLimit else { return }
                self.chargeLimit = state
            }
        }
    }

    /// Serial queue for the charge-limit subprocess/defaults I/O.
    private let chargeLimitIOQueue = DispatchQueue(label: "com.voltio.chargelimit", qos: .utility)

    /// Feeds the EMA estimator and the daily energy sampler. Every tick counts —
    /// the energy integral needs samples even when nothing else changed, so this
    /// runs outside the "republish only on change" gate above.
    private func recordEnergy(for reading: BatterySnapshot) {
        let watts = reading.powerWatts
        powerEstimator = powerEstimator.updated(with: watts, at: Date())
        smoothedPowerWatts = powerEstimator.estimateWatts
        energy.record(powerWatts: watts)
        sampleEnergyApps(systemWatts: reading.isPluggedIn ? nil : watts)
        // Force a widget reload on state flips (charging started/stopped,
        // plugged in/out, hold engaged) — rare events worth spending the
        // WidgetKit reload budget on, and the ones where a stale widget is
        // most misleading. Percentage-only changes ride the throttled path.
        let stateKey = "\(reading.isCharging)-\(reading.isPluggedIn)-\(reading.isFullyCharged)-\(reading.isPausedByMacOS)-\(reading.isLowPowerMode)"
        let flipped = stateKey != lastWidgetStateKey
        lastWidgetStateKey = stateKey
        publishWidgetSnapshot(from: reading, forceReload: flipped)
    }

    /// Last published widget state signature, for flip detection.
    private var lastWidgetStateKey: String?

    /// One-way handoff to the widget extension: the latest snapshot + today's
    /// energy, written to the App Group suite. Best-effort; failures are silent
    /// (the widget just keeps its previous timeline until the next tick).
    private func publishWidgetSnapshot(from reading: BatterySnapshot, forceReload: Bool = false) {
        widgetWriter.publish(
            reading,
            todayEnergy: energy.todayTotal,
            smoothedPowerWatts: smoothedPowerWatts,
            at: Date(),
            forceReload: forceReload
        )
    }

    /// Drives the per-app energy sampler. The process walk happens off-main
    /// inside the sampler; dropping a tick if one is somehow still running is
    /// fine — the next 5 s tick catches up.
    private var isSamplingEnergyApps = false
    private func sampleEnergyApps(systemWatts: Double?) {
        guard !isSamplingEnergyApps else { return }
        isSamplingEnergyApps = true
        Task {
            await energyAppsSampler.tick(systemWatts: systemWatts)
            isSamplingEnergyApps = false
        }
    }

    // MARK: - Accessories (slow path)

    /// Refreshes connected accessories. CoreBluetooth runs on the main actor
    /// (cheap), while the heavier IORegistry (HID) walk is pushed off the main
    /// thread. Runs on its own slower timer since accessory levels move slowly and
    /// BLE scanning + the registry walk dominate cost.
    func refreshAccessories() {
        bluetooth.rescan()
        bluetooth.refreshConnectedDevices()
        bluetooth.pruneStale()

        guard !isReadingAccessories else { return }
        isReadingAccessories = true
        let hidReader = self.hidReader
        Task.detached(priority: .utility) {
            let hid = hidReader.read()
            await self.applyAccessories(hid: hid)
        }
    }

    private func applyAccessories(hid: [PeripheralDevice]) {
        isReadingAccessories = false
        hidDevices = hid
        recomputePeripherals()
    }

    /// Fires a specific alert rule so the user can preview bubble + glow + sound.
    func testAlert(_ rule: BatteryAlertRule) {
        alerts.test(rule)
    }

    /// Fires a sample bubble in the chosen accent (General "Preview" control).
    func previewAlert(_ kind: AlertPreviewKind = .low) {
        alerts.preview(kind)
    }

    /// Whether the Connected Devices section should appear in the menu dropdown.
    var showsConnectedDevices: Bool { settings.showConnectedDevices }

    /// Peripherals to show in the menu-bar dropdown — hidden devices removed.
    var visiblePeripherals: [PeripheralDevice] {
        peripherals.filter { !settings.hiddenDeviceIDs.contains($0.id) }
    }

    private func recomputePeripherals() {
        var liveByID: [String: PeripheralDevice] = [:]
        for device in hidDevices + bleDevices {
            liveByID[device.id] = device
        }
        let live = Array(liveByID.values)

        // Remember only devices with a *stable* identity (HID address / connected
        // GATT peripheral). BLE Continuity adverts ("ble:") use a UUID that rotates
        // with the device's privacy MAC, so persisting them spawns endless
        // "last seen" duplicates — they are shown only while live.
        history.record(live.filter(\.hasStableIdentity))
        peripherals = history.merged(withLive: live)

        // Only alert on devices that are actually connected right now.
        alerts.evaluatePeripherals(peripherals.filter(\.isConnected))
    }

    /// Forget a remembered (offline) device so it stops appearing in the list.
    func forget(_ device: PeripheralDevice) {
        history.forget(device.id)
        recomputePeripherals()
    }

    /// Accessories refresh no faster than every 20s (and never faster than the
    /// battery interval): BLE scanning and the registry walk dominate cost, and
    /// accessory battery levels change slowly.
    private var accessoryInterval: Duration {
        .seconds(max(settings.refreshInterval.rawValue, 20))
    }

    /// Adaptive battery polling: the configured interval, shortened when the
    /// battery is low so alerts fire promptly. A charge/discharge percent point
    /// at low levels lasts well under a minute, so a slow fixed interval could
    /// let the battery cross the alert threshold unnoticed.
    var batteryInterval: Duration {
        let base = settings.refreshInterval.rawValue
        guard let percent = snapshot?.percentage else { return .seconds(base) }
        if percent <= 10 { return .seconds(min(base, 5)) }
        if percent <= 20 { return .seconds(min(base, 10)) }
        if percent <= 30 { return .seconds(min(base, 20)) }
        return .seconds(base)
    }

    private func startPolling() {
        batteryPollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.batteryInterval ?? .seconds(5)
                try? await Task.sleep(for: interval)
                self?.refreshBattery()
            }
        }
        accessoryPollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.accessoryInterval ?? .seconds(20)
                try? await Task.sleep(for: interval)
                self?.refreshAccessories()
            }
        }
    }

    /// Compact menu-bar label, e.g. "97%".
    var menuBarTitle: String {
        guard let snapshot else { return "—" }
        return "\(snapshot.percentage)%"
    }

    /// Level-aware SF Symbol shown next to the percentage in the menu bar.
    var menuBarSymbol: String {
        snapshot?.menuBarSymbol ?? "battery.0percent"
    }

    /// Charge-state tint for the menu-bar icon when status colors are enabled.
    /// Uses the plug-in-keyed color so it turns green instantly on connect.
    var menuBarTint: Color? {
        snapshot?.menuBarStateColor
    }

    /// Time-remaining label for the menu bar, e.g. "5h 0m" (or "—" if unknown).
    var menuBarTimeTitle: String {
        guard let minutes = snapshot?.minutesRemaining else { return "—" }
        return Format.minutes(minutes)
    }
}
