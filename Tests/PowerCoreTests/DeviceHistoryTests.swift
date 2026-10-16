import XCTest
@testable import PowerCore

final class DeviceHistoryTests: XCTestCase {

    private func device(
        _ id: String,
        _ name: String,
        percent: Int,
        lastSeen: Date = Date(),
        kind: PeripheralKind = .other,
        connected: Bool = true
    ) -> PeripheralDevice {
        PeripheralDevice(
            id: id, name: name, kind: kind, source: .bluetooth,
            batteries: [BatteryReading(id: "main", label: nil, percent: percent, isCharging: false)],
            lastSeen: lastSeen, isConnected: connected
        )
    }

    // MARK: - record

    func testRecordAddsDevicesAsConnectedAtNow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let result = DeviceHistory.record(live: [device("a", "A", percent: 50)], into: [:], now: now)

        let stored = result["a"]
        XCTAssertNotNil(stored)
        XCTAssertTrue(stored!.isConnected)
        XCTAssertEqual(stored!.lastSeen, now)
        XCTAssertEqual(stored!.minPercent, 50)
    }

    func testRecordRefreshesExistingEntry() {
        let old = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        var history = [String: PeripheralDevice]()
        history["a"] = device("a", "A", percent: 50, lastSeen: old)

        let result = DeviceHistory.record(live: [device("a", "A", percent: 30)], into: history, now: now)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["a"]?.lastSeen, now)
        XCTAssertEqual(result["a"]?.minPercent, 30)
    }

    func testRecordWithEmptyLiveLeavesHistoryUntouched() {
        var history = [String: PeripheralDevice]()
        history["a"] = device("a", "A", percent: 50)

        let result = DeviceHistory.record(live: [], into: history)

        XCTAssertEqual(result, history)
    }

    // MARK: - merge

    func testMergeMarksLiveConnectedAndRememberedOffline() {
        let live = [device("a", "A", percent: 80)]
        let remembered = [
            "a": device("a", "A", percent: 80),
            "b": device("b", "B", percent: 40),
        ]

        let merged = DeviceHistory.merge(live: live, remembered: remembered)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.id, "a")
        XCTAssertTrue(merged.first!.isConnected)
        let offline = merged.first { $0.id == "b" }
        XCTAssertNotNil(offline)
        XCTAssertFalse(offline!.isConnected)
    }

    func testMergeDeviceInBothAppearsOnceAsConnected() {
        let live = [device("a", "A", percent: 80)]
        let remembered = ["a": device("a", "A", percent: 80)]

        let merged = DeviceHistory.merge(live: live, remembered: remembered)

        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isConnected)
    }

    func testMergeRanksConnectedBeforeOfflineThenLowestBattery() {
        let live = [
            device("hi", "Connected-High", percent: 80),
            device("lo", "Connected-Low", percent: 20),
        ]
        let remembered = [
            "hi": device("hi", "Connected-High", percent: 80),
            "lo": device("lo", "Connected-Low", percent: 20),
            "off10": device("off10", "Offline-10", percent: 10),
            "off60": device("off60", "Offline-60", percent: 60),
        ]

        let merged = DeviceHistory.merge(live: live, remembered: remembered)

        // Connected (lowest first), then offline (lowest first).
        XCTAssertEqual(merged.map(\.id), ["lo", "hi", "off10", "off60"])
        XCTAssertEqual(merged.map(\.isConnected), [true, true, false, false])
    }

    func testMergeWithNoLiveReturnsAllOffline() {
        let remembered = [
            "a": device("a", "A", percent: 30),
            "b": device("b", "B", percent: 90),
        ]

        let merged = DeviceHistory.merge(live: [], remembered: remembered)

        XCTAssertEqual(merged.map(\.id), ["a", "b"]) // 30 before 90
        XCTAssertTrue(merged.allSatisfy { !$0.isConnected })
    }

    // MARK: - sameContent

    func testSameContentIgnoresLastSeen() {
        let a = ["x": device("x", "X", percent: 50, lastSeen: Date(timeIntervalSince1970: 1))]
        let b = ["x": device("x", "X", percent: 50, lastSeen: Date(timeIntervalSince1970: 9_999))]
        XCTAssertTrue(DeviceHistory.sameContent(a, b))
    }

    func testSameContentDetectsBatteryChange() {
        let a = ["x": device("x", "X", percent: 50)]
        let b = ["x": device("x", "X", percent: 49)]
        XCTAssertFalse(DeviceHistory.sameContent(a, b))
    }

    func testSameContentDetectsNameChange() {
        let a = ["x": device("x", "X", percent: 50)]
        let b = ["x": device("x", "Renamed", percent: 50)]
        XCTAssertFalse(DeviceHistory.sameContent(a, b))
    }

    func testSameContentDetectsAddedOrRemovedDevice() {
        let a = ["x": device("x", "X", percent: 50)]
        let b = [
            "x": device("x", "X", percent: 50),
            "y": device("y", "Y", percent: 80),
        ]
        XCTAssertFalse(DeviceHistory.sameContent(a, b))
        XCTAssertFalse(DeviceHistory.sameContent(b, a))
    }

    // MARK: - pruneExpired

    func testPruneDropsEntriesOlderThanExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expiry: TimeInterval = 7 * 24 * 3600
        let remembered = [
            "fresh": device("fresh", "Fresh", percent: 50, lastSeen: now.addingTimeInterval(-3600)),
            "stale": device("stale", "Stale", percent: 50, lastSeen: now.addingTimeInterval(-10 * 24 * 3600)),
        ]

        let pruned = DeviceHistory.pruneExpired(remembered, expiry: expiry, now: now)

        XCTAssertEqual(Set(pruned.keys), ["fresh"])
    }

    func testPruneKeepsEntryExactlyAtCutoff() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expiry: TimeInterval = 7 * 24 * 3600
        let remembered = [
            "edge": device("edge", "Edge", percent: 50, lastSeen: now.addingTimeInterval(-expiry)),
        ]

        let pruned = DeviceHistory.pruneExpired(remembered, expiry: expiry, now: now)

        XCTAssertEqual(Set(pruned.keys), ["edge"])
    }

    // MARK: - order

    func testOrderNameBreaksTies() {
        let a = device("1", "Alpha", percent: 50)
        let b = device("2", "Beta", percent: 50)
        XCTAssertTrue(DeviceHistory.order(a, b))
        XCTAssertFalse(DeviceHistory.order(b, a))
    }

    func testMergeUsesLowestCompartmentForMultiCellDevices() {
        let airpods = PeripheralDevice(
            id: "pods", name: "AirPods", kind: .airpods, source: .bluetooth,
            batteries: [
                BatteryReading(id: "left", label: "Left", percent: 70, isCharging: false),
                BatteryReading(id: "right", label: "Right", percent: 15, isCharging: false),
            ]
        )
        let other = device("x", "Other", percent: 40)

        let merged = DeviceHistory.merge(live: [airpods, other], remembered: [:])

        // AirPods rank by their lowest cell (15%), so they come before the 40% device.
        XCTAssertEqual(merged.map(\.id), ["pods", "x"])
    }
}
