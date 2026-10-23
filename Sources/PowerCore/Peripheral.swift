import Foundation

/// A recognized class of connected accessory, used to pick an icon and label.
public enum PeripheralKind: String, Sendable, Equatable, Codable {
    case airpods
    case airpodsPro
    case airpodsMax
    case headphones
    case magicMouse
    case magicKeyboard
    case magicTrackpad
    case mouse
    case keyboard
    case trackpad
    case gameController
    case iphone
    case ipad
    case watch
    case mac
    case other

    /// True for devices whose battery is reported per compartment (left/right
    /// pod, case). Used to label a lone reading — with one pod in the case only
    /// the worn pod advertises, and a bare percentage would read as the whole
    /// device's charge.
    public var hasCompartments: Bool {
        switch self {
        case .airpods, .airpodsPro, .airpodsMax: return true
        default: return false
        }
    }

    /// Best-effort classification of a connected device by its advertised name,
    /// used for GATT devices (iPhone/iPad/Watch/Mac) where we only have the name.
    public static func classify(deviceName name: String) -> PeripheralKind {
        let n = name.lowercased()
        if n.contains("ipad") { return .ipad }
        if n.contains("iphone") { return .iphone }
        if n.contains("watch") { return .watch }
        if n.contains("macbook") || n.contains("imac") || n.contains("mac mini")
            || n.contains("mac studio") || n.hasSuffix("mac") { return .mac }
        // Pointing devices / input accessories (verified live 2026-10-17:
        // "MX Master 3 B" — Logitech BLE mice report battery over GATT but
        // their names contain neither "mouse" nor any Apple keyword).
        if n.contains("mouse") || n.contains("mx master") || n.contains("m720")
            || n.contains("anywhere") { return .mouse }
        if n.contains("keyboard") || n.contains("keys-to-go") || n.contains("k380")
            || n.contains("k480") { return .keyboard }
        if n.contains("trackpad") { return .trackpad }
        if n.contains("headphone") || n.contains("beats") { return .headphones }
        return .other
    }
}

/// Where a reading came from. HID is permission-free (IORegistry); Bluetooth
/// is decoded from BLE Continuity advertisements.
public enum PeripheralSource: String, Sendable, Equatable, Codable {
    case hid
    case bluetooth
}

/// A single battery compartment reading. Multi-cell devices (e.g. AirPods with
/// left/right/case) expose several of these.
public struct BatteryReading: Sendable, Equatable, Identifiable, Codable {
    /// Stable within a device; `label` for multi-cell, otherwise "main".
    public let id: String
    /// "Left" / "Right" / "Case" for multi-cell devices; `nil` for single-cell.
    public let label: String?
    public let percent: Int
    public let isCharging: Bool

    public init(id: String, label: String?, percent: Int, isCharging: Bool) {
        self.id = id
        self.label = label
        self.percent = percent
        self.isCharging = isCharging
    }
}

/// A connected accessory and its battery compartments.
public struct PeripheralDevice: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let kind: PeripheralKind
    public let source: PeripheralSource
    public let batteries: [BatteryReading]
    public let lastSeen: Date
    /// `true` while the device is currently reporting; `false` for a remembered
    /// reading shown after the device disconnected.
    public let isConnected: Bool

    public init(
        id: String,
        name: String,
        kind: PeripheralKind,
        source: PeripheralSource,
        batteries: [BatteryReading],
        lastSeen: Date = Date(),
        isConnected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.source = source
        self.batteries = batteries
        self.lastSeen = lastSeen
        self.isConnected = isConnected
    }

    /// Returns a copy with the connection state (and optionally `lastSeen`) changed.
    public func setting(isConnected: Bool, lastSeen: Date? = nil) -> PeripheralDevice {
        PeripheralDevice(
            id: id, name: name, kind: kind, source: source,
            batteries: batteries, lastSeen: lastSeen ?? self.lastSeen,
            isConnected: isConnected
        )
    }

    /// The most conservative (lowest) compartment level — what to surface as the
    /// device's headline percentage.
    public var minPercent: Int? {
        batteries.map(\.percent).min()
    }

    public var isAnyCharging: Bool {
        batteries.contains(where: \.isCharging)
    }

    /// Whether this device's `id` is stable across sessions and Bluetooth privacy
    /// address rotations, and therefore safe to remember offline. HID accessories
    /// (keyed by Bluetooth address) and GATT devices connected to this Mac are
    /// stable; BLE Continuity adverts ("ble:") rotate their UUID with the privacy
    /// MAC, so persisting them produces endless duplicates.
    public var hasStableIdentity: Bool {
        id.hasPrefix("hid:") || id.hasPrefix("gatt:")
    }
}
