import CoreBluetooth
import Foundation
import IOBluetooth
import os
import PowerCore

private let btLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Voltio", category: "bluetooth")

/// Coarse Bluetooth availability used to drive the Connected Devices UI.
enum BluetoothAccess: Equatable {
    case scanning
    /// "Don't Allow" was answered (or policy blocks it); macOS never re-prompts, so callers offer a link.
    case denied
    /// The prompt has not been shown yet; nothing is broken and no remedy is needed.
    case awaitingPermission
    case poweredOff
    case unavailable
}

/// Cumulative diagnostic counters for the BLE scan pipeline, surfaced in
/// Settings → Devices when Developer Mode is on. Helps explain why a device
/// does (or doesn't) show up: weak RSSI, unknown model bytes, etc.
struct BLEDiagnostics: Equatable {
    var advertsSeen = 0              // every didDiscover callback
    var rejectedWeakRSSI = 0         // below proximity floor / RSSI unavailable
    var rejectedNotContinuity = 0    // no Apple manufacturer data
    var rejectedNoBatteries = 0      // decoded but zero battery entries
    /// Devices the ownership gate is hiding right now (gauge, recomputed per emit).
    var hiddenByOwnership = 0
    /// Paired-address suffixes the gate can match (gauge); zero here + hidden > 0 is the bug signature.
    var knownOwnerSuffixes = 0
    var advertsDecoded = 0           // yielded a usable device
    var gattDevicesSeen = 0          // connected devices exposing Battery Service
    var gattReads = 0                // battery values read over GATT
}

/// Scans BLE advertisements and decodes Apple Continuity proximity-pairing
/// messages into AirPods/Beats battery readings.
///
/// CoreBluetooth delegate callbacks are delivered on the main dispatch queue,
/// which is the main actor's executor, so the type is `@MainActor` with
/// `nonisolated` delegate shims that hop back via `assumeIsolated`.
@MainActor
final class BluetoothBatteryScanner: NSObject {
    /// Invoked whenever the BLE device set changes.
    var onUpdate: (([PeripheralDevice]) -> Void)?

    /// Continuity ownership gate (paired-name matching + connect-to-confirm),
    /// extracted to its own type (Phase 1.3).
    private let ownership = ContinuityOwnershipTracker()

    private var central: CBCentralManager?
    /// AirPods/Beats decoded from Continuity advertisements (no connection).
    private var devices: [UUID: PeripheralDevice] = [:]
    /// Owner-address suffix per Continuity device (transport metadata, not displayed).
    private var ownerSuffixes: [UUID: [UInt8]] = [:]
    private let staleAfter: TimeInterval = 60

    /// Devices read over a GATT connection (iPhone, iPad, Watch…), keyed by id.
    private var gattDevices: [UUID: PeripheralDevice] = [:]
    /// Strong refs to connected peripherals so CoreBluetooth keeps their delegates.
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    /// Cached battery-level characteristic per peripheral for cheap re-reads.
    private var batteryChars: [UUID: CBCharacteristic] = [:]

    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryCharUUID = CBUUID(string: "2A19")

    /// Continuity adverts are broadcast by *every* nearby Apple device, including
    /// strangers'. Only accept advertisements at least this strong (dBm) so the
    /// list stays limited to the user's own gear at the desk. Tunable.
    private nonisolated static let proximityRSSIFloor = -65

    /// Diagnostic counters (read by Settings → Devices in Developer Mode).
    private(set) var diagnostics = BLEDiagnostics()

    override init() {
        super.init()
        // No CBCentralManager yet: creating one triggers the Bluetooth TCC prompt, and that must
        // come after onboarding explains it, not during app launch.
    }

    /// Create the central manager, which is what raises the system permission prompt. Idempotent.
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    /// Whether the radio has been brought up. Before `activate()`, no `CBCentralManager` exists and
    /// macOS has not been asked for Bluetooth permission.
    var isActivated: Bool { central != nil }

    var access: BluetoothAccess {
        switch CBCentralManager.authorization {
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .awaitingPermission
        case .allowedAlways:
            break
        @unknown default:
            return .unavailable
        }
        switch central?.state ?? .unknown {
        case .poweredOn: return .scanning
        case .poweredOff: return .poweredOff
        default: return .unavailable
        }
    }

    /// Start scanning if powered on and authorized. Safe to call repeatedly.
    /// Duplicate filtering is left *on* (the default): leaving it off keeps the
    /// BLE radio fully active and floods us with redundant advertisements — a real
    /// battery drain. We re-sample on a cadence via `rescan()` instead.
    func startIfPossible() {
        guard let central, central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Re-arm the scan so each nearby device reports a fresh advertisement. With
    /// duplicate filtering on, CoreBluetooth reports a device only once per scan
    /// session, so we restart the scan each poll to refresh readings rather than
    /// holding the radio open continuously.
    func rescan() {
        guard let central, central.state == .poweredOn else { return }
        if central.isScanning { central.stopScan() }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Read battery from already-connected, paired devices that expose the GATT
    /// Battery Service — iPhone, iPad, Apple Watch, etc. (AirPods come through the
    /// advertisement path instead). Safe to call every poll.
    func refreshConnectedDevices() {
        guard let central, central.state == .poweredOn else { return }
        // Refresh the paired-names cache lazily (≥10 min between IOBluetooth
        // queries); drives the Continuity ownership gate.
        let bleNames = Set(devices.values.compactMap { ContinuityOwnershipTracker.normalizedName($0.name) })
        var ownershipChanged = ownership.refreshPairedNamesIfStale(visibleNames: bleNames)
        // Ownership confirmation (connect-to-confirm): the full set of
        // Bluetooth devices the SYSTEM has connected to this Mac — no service
        // filter. Continuity devices (AirPods) are only trusted once their
        // name appears here; strangers broadcasting nearby never connect.
        let allConnected = central.retrieveConnectedPeripherals(withServices: [])
        let systemConnectedNames = Set(
            allConnected.compactMap { ContinuityOwnershipTracker.normalizedName($0.name) }
        )
        ownershipChanged.formUnion(ownership.confirmVisible(bleNames, connectedTo: systemConnectedNames))
        if !ownershipChanged.isEmpty { emit() }

        let connected = central.retrieveConnectedPeripherals(withServices: [batteryServiceUUID])
        btLog.debug("GATT refresh: \(connected.count) connected device(s) expose the Battery Service")
        diagnostics.gattDevicesSeen = max(diagnostics.gattDevicesSeen, connected.count)
        let currentIDs = Set(connected.map(\.identifier))

        // Drop devices that are no longer connected.
        var changed = false
        for id in Array(gattDevices.keys) where !currentIDs.contains(id) {
            gattDevices[id] = nil
            batteryChars[id] = nil
            connectedPeripherals[id] = nil
            changed = true
        }
        if changed { emit() }

        for peripheral in connected {
            connectedPeripherals[peripheral.identifier] = peripheral   // retain
            peripheral.delegate = self
            switch peripheral.state {
            case .connected:
                if let char = batteryChars[peripheral.identifier] {
                    peripheral.readValue(for: char)
                } else {
                    peripheral.discoverServices([batteryServiceUUID])
                }
            case .connecting:
                break
            default:
                central.connect(peripheral, options: nil)
            }
        }
    }

    /// Drop devices we haven't seen recently (called from the model's poll).
    func pruneStale() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let before = devices.count
        devices = devices.filter { $0.value.lastSeen >= cutoff }
        // Bounded: drop suffixes for devices no longer tracked as privacy addresses rotate.
        ownerSuffixes = ownerSuffixes.filter { devices[$0.key] != nil }
        if devices.count != before { emit() }
    }

    private func emit() {
        let merged = Array(devices.values) + Array(gattDevices.values)
        ownership.refreshPairedAddressesIfStale()
        // Keyed by name: one physical device under rotated privacy addresses is still one hidden device.
        var hiddenNames = Set<String>()
        let owned = merged.filter { device in
            let uuid = UUID(uuidString: String(device.id.dropFirst("ble:".count)))
            let visible = ownership.isVisible(
                deviceID: device.id,
                name: device.name,
                suffix: uuid.flatMap { ownerSuffixes[$0] }
            )
            if !visible { hiddenNames.insert(device.name) }
            return visible
        }
        diagnostics.hiddenByOwnership = hiddenNames.count
        diagnostics.knownOwnerSuffixes = ownership.knownAddressSuffixCount
        // Collapse duplicate rows (e.g. the same AirPods under a rotated privacy address).
        var seen = Set<String>()
        var collapsedSignatures = Set<String>()
        let unique = owned.filter { device in
            let signature = "\(device.kind.rawValue)|\(device.name)|"
                + device.batteries.map { "\($0.id):\($0.percent):\($0.isCharging)" }.joined(separator: ",")
            let inserted = seen.insert(signature).inserted
            if !inserted { collapsedSignatures.insert(signature) }
            return inserted
        }
        // Surface near-collisions: two live ble: entries collapsed into one row.
        // Usually the same AirPods seen under a rotated privacy MAC, but if it
        // happens persistently it can hide a genuinely distinct device.
        if !collapsedSignatures.isEmpty {
            let bleIDs = merged.filter { $0.id.hasPrefix("ble:") }.map(\.id)
            btLog.info("Collapsed \(collapsedSignatures.count) duplicate device signature(s) among \(bleIDs.count) BLE device(s): \(collapsedSignatures.joined(separator: " ;; "), privacy: .private)")
        }
        // Rank by battery level, lowest first (so what needs charging is on top),
        // then by name for stable ordering.
        let list = unique.sorted {
            ($0.minPercent ?? Int.max, $0.name) < ($1.minPercent ?? Int.max, $1.name)
        }
        MainActorIsolation.assume { onUpdate?(list) }
    }

    /// Same displayed reading (ignoring `lastSeen`)? Suppresses redundant emits
    /// from repeated advertisements when the battery hasn't actually moved.
    private static func sameContent(_ a: PeripheralDevice, _ b: PeripheralDevice) -> Bool {
        a.id == b.id && a.name == b.name && a.batteries == b.batteries
    }

    private static func makeGATTDevice(uuid: UUID, name: String, percent: Int) -> PeripheralDevice {
        PeripheralDevice(
            id: "gatt:\(uuid.uuidString)",
            name: name.isEmpty ? "Bluetooth Device" : name,
            kind: PeripheralKind.classify(deviceName: name),
            source: .bluetooth,
            batteries: [BatteryReading(id: "main", label: nil, percent: percent, isCharging: false)]
        )
    }

    // MARK: - Classification

    private static func classify(model: UInt16, name: String) -> PeripheralKind {
        let n = name.lowercased()
        if n.contains("max") { return .airpodsMax }
        if n.contains("pro") { return .airpodsPro }
        if n.contains("airpod") { return .airpods }
        if n.contains("beats") || n.contains("powerbeats") || n.contains("studio") { return .headphones }
        switch model {
        case 0x0A20, 0x1F20: return .airpodsMax
        case 0x0E20, 0x1420, 0x2420: return .airpodsPro
        case 0x0220, 0x0F20, 0x1320, 0x1920, 0x1B20: return .airpods
        default: return .headphones
        }
    }

    private static func defaultName(_ kind: PeripheralKind) -> String {
        switch kind {
        case .airpodsPro: return "AirPods Pro"
        case .airpodsMax: return "AirPods Max"
        case .headphones: return "Headphones"
        default: return "AirPods"
        }
    }

    private static func makeDevice(uuid: UUID, advertisedName: String?, pods: AirPodsBattery) -> PeripheralDevice? {
        var batteries: [BatteryReading] = []
        if let left = pods.left {
            batteries.append(BatteryReading(id: "left", label: "Left", percent: left, isCharging: pods.leftCharging))
        }
        if let right = pods.right {
            batteries.append(BatteryReading(id: "right", label: "Right", percent: right, isCharging: pods.rightCharging))
        }
        if let caseBattery = pods.caseBattery {
            batteries.append(BatteryReading(id: "case", label: "Case", percent: caseBattery, isCharging: pods.caseCharging))
        }
        guard !batteries.isEmpty else { return nil }

        let kind = classify(model: pods.model, name: advertisedName ?? "")
        let name = advertisedName?.isEmpty == false ? advertisedName! : defaultName(kind)

        return PeripheralDevice(
            id: "ble:\(uuid.uuidString)",
            name: name,
            kind: kind,
            source: .bluetooth,
            batteries: batteries
        )
    }
}

extension BluetoothBatteryScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActorIsolation.assume {
            self.startIfPossible()
            self.refreshConnectedDevices()
            self.emit()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Delegate callbacks are delivered on `queue: .main`, so the peripheral is
        // already on the main thread; the unsafe binding documents that contract.
        nonisolated(unsafe) let p = peripheral
        MainActorIsolation.assume {
            p.delegate = self
            p.discoverServices([self.batteryServiceUUID])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let uuid = peripheral.identifier
        let name = peripheral.name ?? "?"
        let reason = error?.localizedDescription ?? "unknown"
        btLog.error("GATT connect failed for \(name, privacy: .private): \(reason, privacy: .public)")
        MainActorIsolation.assume { self.connectedPeripherals[uuid] = nil }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let uuid = peripheral.identifier
        MainActorIsolation.assume {
            self.gattDevices[uuid] = nil
            self.batteryChars[uuid] = nil
            self.connectedPeripherals[uuid] = nil
            self.emit()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Ignore distant advertisers (strangers across the room). 127 is
        // CoreBluetooth's "RSSI unavailable" sentinel. Counter mutations run
        // via MainActor.assume: CoreBluetooth delegate callbacks are delivered
        // on the main dispatch queue, so the hop is sound.
        MainActorIsolation.assume { self.diagnostics.advertsSeen += 1 }
        let rssi = RSSI.intValue
        guard rssi != 127, rssi >= Self.proximityRSSIFloor else {
            MainActorIsolation.assume { self.diagnostics.rejectedWeakRSSI += 1 }
            return
        }

        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let pods = ContinuityDecoder.decodeProximityPairing(manufacturerData: manufacturerData),
              !pods.isEmpty
        else {
            MainActorIsolation.assume { self.diagnostics.rejectedNotContinuity += 1 }
            return
        }

        // Extract Sendable values before hopping to the main actor.
        let uuid = peripheral.identifier
        let advertisedName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        let ownerSuffix = ContinuityDecoder.ownerAddressSuffix(manufacturerData: manufacturerData)

        MainActorIsolation.assume {
            guard let device = Self.makeDevice(uuid: uuid, advertisedName: advertisedName, pods: pods) else {
                self.diagnostics.rejectedNoBatteries += 1
                return
            }
            self.diagnostics.advertsDecoded += 1
            let suffixChanged = ownerSuffix != nil && self.ownerSuffixes[uuid] != ownerSuffix
            if let ownerSuffix { self.ownerSuffixes[uuid] = ownerSuffix }
            // A newly-learned owner suffix can flip the device from gated-out to visible.
            if let existing = self.devices[uuid], Self.sameContent(existing, device) {
                self.devices[uuid] = device
                if suffixChanged { self.emit() }
                return
            }
            self.devices[uuid] = device
            self.emit()
        }
    }
}

extension BluetoothBatteryScanner: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        nonisolated(unsafe) let p = peripheral
        MainActorIsolation.assume {
            guard let services = p.services else { return }
            for service in services where service.uuid == self.batteryServiceUUID {
                p.discoverCharacteristics([self.batteryCharUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let s = service
        MainActorIsolation.assume {
            guard let characteristics = s.characteristics else { return }
            for characteristic in characteristics where characteristic.uuid == self.batteryCharUUID {
                self.batteryChars[p.identifier] = characteristic
                p.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    p.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let c = characteristic
        MainActorIsolation.assume {
            guard c.uuid == self.batteryCharUUID,
                  let data = c.value, let raw = data.first else { return }
            self.diagnostics.gattReads += 1
            let percent = min(100, max(0, Int(raw)))
            let uuid = p.identifier
            let name = p.name ?? ""
            let device = Self.makeGATTDevice(uuid: uuid, name: name, percent: percent)
            if let existing = self.gattDevices[uuid], Self.sameContent(existing, device) {
                self.gattDevices[uuid] = device
                return
            }
            btLog.debug("GATT battery: \(name, privacy: .private) = \(percent)%")
            self.gattDevices[uuid] = device
            self.emit()
        }
    }
}
