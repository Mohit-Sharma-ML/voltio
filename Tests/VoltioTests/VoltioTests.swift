import AppKit
import Foundation
import PowerCore
import Testing
@testable import Voltio

// MARK: - Presenter fakes

/// Records bubble presentations instead of showing real panels.
@MainActor
private final class FakeBubble: AlertBubblePresenting {
    private(set) var styles: [AlertBubbleController.Style] = []
    func show(_ style: AlertBubbleController.Style) { styles.append(style) }
}

/// Records glow flashes instead of overlaying windows.
@MainActor
private final class FakeGlow: GlowPresenting {
    private(set) var flashes: [(color: NSColor, intensity: CGFloat)] = []
    func flash(color: NSColor, intensity: CGFloat) { flashes.append((color, intensity)) }
}

// MARK: - Snapshot helper

private func makeSnapshot(
    percentage: Int,
    isPluggedIn: Bool,
    isCharging: Bool = false
) -> BatterySnapshot {
    BatterySnapshot(
        percentage: percentage,
        isCharging: isCharging,
        isPluggedIn: isPluggedIn,
        isFullyCharged: isPluggedIn && percentage >= 100,
        minutesRemaining: nil,
        cycleCount: 0,
        designCycleCount: 1000,
        temperatureCelsius: 30,
        voltage: 12.5,
        amperage: 0,
        currentCapacitymAh: 4000,
        maxCapacitymAh: 5000,
        designCapacitymAh: 5000,
        adapterWatts: isPluggedIn ? 60 : nil,
        adapterName: isPluggedIn ? "Test Adapter" : nil,
        systemPowerWatts: nil,
        batteryPowerWatts: nil
    )
}

// MARK: - Hysteresis tests

/// Drives `AlertManager.evaluate` through a discharge→recharge cycle and asserts
/// the alert fires exactly once per crossing — the hysteresis band must prevent
/// re-firing every poll while the battery hovers near the threshold.
@MainActor
@Suite("AlertManager hysteresis")
struct AlertManagerHysteresisTests {

    private func makeManager(defaults: UserDefaults) -> (AlertManager, FakeBubble, FakeGlow) {
        let bubble = FakeBubble()
        let glow = FakeGlow()
        let settings = AppSettings(defaults: defaults)
        let manager = AlertManager(settings: settings, bubble: bubble, glow: glow)
        return (manager, bubble, glow)
    }

    @Test("Low alert fires once, then waits for the re-arm band")
    func lowAlertFiresOncePerCrossing() {
        let suite = UserDefaults(suiteName: "test.low.hysteresis")!
        suite.removePersistentDomain(forName: "test.low.hysteresis")
        let (manager, bubble, _) = makeManager(defaults: suite)

        // Baseline: healthy and charging — nothing armed-low should fire.
        manager.evaluate(makeSnapshot(percentage: 80, isPluggedIn: true, isCharging: true))
        #expect(bubble.styles.isEmpty)

        // Cross below the 20% threshold on battery → fires once.
        manager.evaluate(makeSnapshot(percentage: 19, isPluggedIn: false))
        #expect(bubble.styles.count == 1)

        // Hover near the threshold — hysteresis must suppress repeats.
        manager.evaluate(makeSnapshot(percentage: 18, isPluggedIn: false))
        manager.evaluate(makeSnapshot(percentage: 21, isPluggedIn: false))
        manager.evaluate(makeSnapshot(percentage: 20, isPluggedIn: false))
        #expect(bubble.styles.count == 1, "no re-fire before recovering the full 5-point band")

        // Still inside the band (threshold+4) → must not re-arm.
        manager.evaluate(makeSnapshot(percentage: 24, isPluggedIn: false))
        manager.evaluate(makeSnapshot(percentage: 20, isPluggedIn: false))
        #expect(bubble.styles.count == 1, "no re-fire from inside the hysteresis band")

        // Recover past threshold + 5 → re-armed; next crossing fires again.
        manager.evaluate(makeSnapshot(percentage: 26, isPluggedIn: false))
        manager.evaluate(makeSnapshot(percentage: 19, isPluggedIn: false))
        #expect(bubble.styles.count == 2)
    }

    @Test("Plugging in disarms a low alert without firing")
    func pluggingInDisarms() {
        let suite = UserDefaults(suiteName: "test.low.plug")!
        suite.removePersistentDomain(forName: "test.low.plug")
        let (manager, bubble, _) = makeManager(defaults: suite)

        manager.evaluate(makeSnapshot(percentage: 50, isPluggedIn: false))
        manager.evaluate(makeSnapshot(percentage: 19, isPluggedIn: false))
        #expect(bubble.styles.count == 1)

        // Plugged in below threshold: disarms, no new presentation.
        manager.evaluate(makeSnapshot(percentage: 19, isPluggedIn: true, isCharging: true))
        #expect(bubble.styles.count == 1)

        // Unplug again, still low → armed was reset, so it fires once more.
        manager.evaluate(makeSnapshot(percentage: 19, isPluggedIn: false))
        #expect(bubble.styles.count == 2)
    }

    @Test("Charged alert skips the launch baseline and honors hysteresis")
    func chargedAlertSkipsBaseline() {
        let suite = UserDefaults(suiteName: "test.charged.hysteresis")!
        suite.removePersistentDomain(forName: "test.charged.hysteresis")
        let (manager, bubble, _) = makeManager(defaults: suite)

        // First evaluation while already charged must NOT fire (no baseline).
        manager.evaluate(makeSnapshot(percentage: 100, isPluggedIn: true, isCharging: false))
        #expect(bubble.styles.isEmpty, "no alert at launch even if already charged")

        // Drop below (threshold - 5) to re-arm, then cross again → fires.
        manager.evaluate(makeSnapshot(percentage: 70, isPluggedIn: false))
        manager.evaluate(makeSnapshot(percentage: 100, isPluggedIn: true, isCharging: true))
        #expect(bubble.styles.count == 1)

        // Staying high must not re-fire.
        manager.evaluate(makeSnapshot(percentage: 98, isPluggedIn: true, isCharging: false))
        #expect(bubble.styles.count == 1)
    }
}

// MARK: - DeviceHistoryStore tests

@MainActor
@Suite("DeviceHistoryStore")
struct DeviceHistoryStoreTests {

    private func makeDevice(id: String, percent: Int, lastSeen: Date, connected: Bool = false)
        -> PeripheralDevice
    {
        PeripheralDevice(
            id: id,
            name: "Device \(id)",
            kind: .airpods,
            source: .bluetooth,
            batteries: [BatteryReading(id: "main", label: nil, percent: percent, isCharging: false)],
            lastSeen: lastSeen,
            isConnected: connected
        )
    }

    @Test("Entries older than the expiry window are pruned on load")
    func expiryPrunesStaleEntries() {
        let laterNow = Date(timeIntervalSince1970: 1_000_000)
        let suite = UserDefaults(suiteName: "test.history.expiry")!
        suite.removePersistentDomain(forName: "test.history.expiry")

        // Seed persisted history directly: `record` refreshes lastSeen on every
        // live device, so a genuinely stale entry can only arrive via storage.
        let fresh = makeDevice(
            id: "hid:fresh", percent: 50, lastSeen: laterNow.addingTimeInterval(-600)
        )
        let stale = makeDevice(
            id: "hid:stale", percent: 70, lastSeen: laterNow.addingTimeInterval(-7200)
        )
        let seeded: [String: PeripheralDevice] = [fresh.id: fresh, stale.id: stale]
        suite.set(try! JSONEncoder().encode(seeded), forKey: "history")

        // Constructing the store must prune the stale entry (1h expiry) and
        // persist the cleaned set.
        let store = DeviceHistoryStore(
            defaults: suite, key: "history", expiry: 3600, now: { laterNow }
        )
        #expect(store.remembered["hid:fresh"] != nil)
        #expect(store.remembered["hid:stale"] == nil)

        // Reload from the cleaned persisted data: still only the fresh entry.
        let reloaded = DeviceHistoryStore(
            defaults: suite, key: "history", expiry: 3600, now: { laterNow }
        )
        #expect(reloaded.remembered["hid:fresh"] != nil)
        #expect(reloaded.remembered["hid:stale"] == nil)
    }

    @Test("Injected clock drives the lastSeen flush interval")
    func injectedClockDrivesFlush() {
        var now = Date(timeIntervalSince1970: 2_000_000)
        let suite = UserDefaults(suiteName: "test.history.flush")!
        suite.removePersistentDomain(forName: "test.history.flush")

        var store = DeviceHistoryStore(
            defaults: suite, key: "history", expiry: 3600,
            lastSeenFlushInterval: 300, now: { now }
        )
        store.record([makeDevice(id: "hid:a", percent: 10, lastSeen: now)])
        var raw = suite.data(forKey: "history")
        #expect(raw != nil, "material change (new device) persists immediately")

        // Advance past the flush interval and bump lastSeen: must persist.
        now = now.addingTimeInterval(301)
        store.record([makeDevice(id: "hid:a", percent: 10, lastSeen: now)])
        let flushed = suite.data(forKey: "history")
        #expect(flushed != raw, "lastSeen-only refresh flushes after the interval")
        raw = flushed

        // Advance less than the interval: flush is deferred.
        now = now.addingTimeInterval(10)
        store.record([makeDevice(id: "hid:a", percent: 10, lastSeen: now)])
        #expect(suite.data(forKey: "history") == raw, "within the interval, no flush")
        #expect(store.remembered["hid:a"]?.lastSeen == now, "in-memory lastSeen still advances")
    }
}

// MARK: - Settings schema version

@MainActor
@Suite("AppSettings schema version")
struct SettingsSchemaVersionTests {

    @Test("First launch stamps the current schema version")
    func stampsVersionOnFirstLaunch() {
        let suite = UserDefaults(suiteName: "test.schema.first")!
        suite.removePersistentDomain(forName: "test.schema.first")

        #expect(suite.object(forKey: "settingsSchemaVersion") == nil)
        _ = AppSettings(defaults: suite)
        #expect(suite.integer(forKey: "settingsSchemaVersion") == AppSettings.currentSchemaVersion)
    }

    @Test("An existing stored version is preserved, not overwritten")
    func preservesStoredVersion() {
        let suite = UserDefaults(suiteName: "test.schema.stored")!
        suite.removePersistentDomain(forName: "test.schema.stored")
        suite.set(999, forKey: "settingsSchemaVersion")

        _ = AppSettings(defaults: suite)
        #expect(suite.integer(forKey: "settingsSchemaVersion") == 999)
    }
}
