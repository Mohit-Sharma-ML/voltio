import AppKit
import SwiftUI
import PowerCore

/// The Connected Devices section: visibility gate, device rows with
/// multi-compartment batteries, and the Bluetooth-state placeholder.
/// Extracted from MenuPanelView.swift.
extension MenuPanelView {

    // MARK: - Connected Devices

    @ViewBuilder
    var devicesSection: some View {
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

    func deviceRow(_ device: PeripheralDevice) -> some View {
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

    func compartment(_ reading: BatteryReading) -> some View {
        HStack(spacing: 4) {
            Text(compartmentLabel(reading.label))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(reading.percent)%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(reading.tint.adaptiveTextTint(activeScheme))
            if reading.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
    }

    func compartmentLabel(_ label: String?) -> String {
        switch label {
        case "Left": return "L"
        case "Right": return "R"
        default: return label ?? ""
        }
    }

    var devicesPlaceholder: some View {
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

}
