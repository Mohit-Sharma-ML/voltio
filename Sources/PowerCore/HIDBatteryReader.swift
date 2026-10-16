import Foundation
import IOKit

/// Reads battery levels for HID accessories (Magic Mouse / Keyboard / Trackpad,
/// game controllers, …) from the IORegistry `BatteryPercent` property.
///
/// Permission-free: this walks the registry the same way `ioreg -k BatteryPercent`
/// does, so it needs no Bluetooth entitlement or user prompt.
public struct HIDBatteryReader: Sendable {
    public init() {}

    public func read() -> [PeripheralDevice] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        let options = IOOptionBits(kIORegistryIterateRecursively)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, options, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var seen = Set<String>()
        var devices: [PeripheralDevice] = []

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let device = Self.peripheral(from: entry), seen.insert(device.id).inserted {
                devices.append(device)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return devices
    }

    private static func peripheral(from entry: io_registry_entry_t) -> PeripheralDevice? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = props?.takeRetainedValue() as? [String: Any],
              let percent = (dictionary["BatteryPercent"] as? NSNumber)?.intValue
        else { return nil }

        let name = (dictionary["Product"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Accessory"
        let address = (dictionary["DeviceAddress"] as? String)
        let identity = address ?? name

        return PeripheralDevice(
            id: "hid:\(identity)",
            name: name,
            kind: classify(name: name),
            source: .hid,
            batteries: [
                BatteryReading(id: "main", label: nil, percent: percent, isCharging: false)
            ]
        )
    }

    private static func classify(name: String) -> PeripheralKind {
        let n = name.lowercased()
        if n.contains("trackpad") { return .magicTrackpad }
        if n.contains("keyboard") { return .magicKeyboard }
        if n.contains("mouse") { return .magicMouse }
        if n.contains("controller") { return .gameController }
        return .other
    }
}
