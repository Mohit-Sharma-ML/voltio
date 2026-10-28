import Foundation
import os

/// Battery levels decoded from an Apple "Proximity Pairing" Continuity
/// advertisement (AirPods / Beats). Percentages are `nil` when the device
/// reports the "unavailable" sentinel (e.g. a pod still in the case).
public struct AirPodsBattery: Sendable, Equatable {
    public let model: UInt16
    public let left: Int?
    public let right: Int?
    public let caseBattery: Int?
    public let leftCharging: Bool
    public let rightCharging: Bool
    public let caseCharging: Bool

    public init(
        model: UInt16,
        left: Int?,
        right: Int?,
        caseBattery: Int?,
        leftCharging: Bool,
        rightCharging: Bool,
        caseCharging: Bool
    ) {
        self.model = model
        self.left = left
        self.right = right
        self.caseBattery = caseBattery
        self.leftCharging = leftCharging
        self.rightCharging = rightCharging
        self.caseCharging = caseCharging
    }

    /// True when no compartment reported a usable level.
    public var isEmpty: Bool { left == nil && right == nil && caseBattery == nil }
}

/// Decodes Apple BLE Continuity manufacturer data (unpublished; community reverse engineering, per-model calibration).
public enum ContinuityDecoder {
    /// Apple's Bluetooth company identifier (little-endian in advert data).
    private static let appleCompanyID: (UInt8, UInt8) = (0x4C, 0x00)
    /// TLV type for the Proximity Pairing (AirPods) message.
    private static let proximityPairingType: UInt8 = 0x07

    /// AirPods 4 (ANC) — the only model with calibrated precise level bytes.
    static let preciseLevelModel: UInt16 = 0x1B20

    /// Parse manufacturer data (including the 2-byte company id, as CoreBluetooth provides it).
    public static func decodeProximityPairing(manufacturerData data: Data) -> AirPodsBattery? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4,
              bytes[0] == appleCompanyID.0,
              bytes[1] == appleCompanyID.1
        else { return nil }

        // Walk the TLV stream that follows the company id.
        var index = 2
        while index + 1 < bytes.count {
            let type = bytes[index]
            let length = Int(bytes[index + 1])
            let payloadStart = index + 2
            let payloadEnd = payloadStart + length
            guard payloadEnd <= bytes.count else { break }

            if type == proximityPairingType {
                let payload = Array(bytes[payloadStart..<payloadEnd])
                guard let decoded = decodePayload(payload) else {
                    log.notice(
                        "Proximity pairing payload failed to parse (type 0x07, \(payload.count) byte(s), length field \(length)): \(payload.map { String(format: "%02x", $0) }.joined(), privacy: .private)"
                    )
                    return nil
                }
                return decoded
            }
            index = payloadEnd
        }
        return nil
    }

    /// Owner address suffix (last 3 bytes of the advert tail): the paired phone's address, constant per owner.
    public static func ownerAddressSuffix(manufacturerData data: Data) -> [UInt8]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4,
              bytes[0] == appleCompanyID.0, bytes[1] == appleCompanyID.1
        else { return nil }

        var index = 2
        while index + 1 < bytes.count {
            let type = bytes[index]
            let length = Int(bytes[index + 1])
            let payloadStart = index + 2
            let payloadEnd = payloadStart + length
            guard payloadEnd <= bytes.count else { return nil }
            if type == proximityPairingType {
                let payload = Array(bytes[payloadStart..<payloadEnd])
                guard payload.count >= 16 else { return nil }
                return Array(payload[13...15])
            }
            index = payloadEnd
        }
        return nil
    }

    /// Decode the proximity-pairing payload (excludes type + length bytes).
    /// Layout: [0]=prefix [1..2]=model [3]=status [4]=pods battery
    /// [5]=case battery (low nibble) + charging flags (high nibble).
    static func decodePayload(_ payload: [UInt8]) -> AirPodsBattery? {
        guard payload.count >= 6 else { return nil }

        let model = UInt16(payload[1]) << 8 | UInt16(payload[2])
        let status = payload[3]
        let podsByte = payload[4]
        let caseByte = payload[5]

        // The "flip" bit indicates which physical pod the nibbles map to.
        let flip = (status & 0x20) == 0
        let highNibble = podsByte >> 4
        let lowNibble = podsByte & 0x0F
        let leftRaw = flip ? highNibble : lowNibble
        let rightRaw = flip ? lowNibble : highNibble
        let caseRaw = caseByte & 0x0F
        let chargeFlags = caseByte >> 4

        // 0x1B20 broadcasts precise levels for all three compartments at bytes 10-12 with bit 7 as a charging flag.
        let precise: (left: Int?, right: Int?, caseBattery: Int?) = {
            guard model == preciseLevelModel, payload.count > 12 else { return (nil, nil, nil) }
            func level(_ raw: UInt8, band: UInt8) -> Int? {
                guard band <= 10 else { return nil }
                let value = Int(raw & 0x7F)  // bit 7 is a charging flag, not part of the level
                guard value <= 100, value / 10 == Int(band) else { return nil }  // only refine a value it agrees with
                return value
            }
            return (
                level(payload[10], band: leftRaw),
                level(payload[11], band: rightRaw),
                level(payload[12], band: caseRaw)
            )
        }()

        return AirPodsBattery(
            model: model,
            left: precise.left ?? percent(leftRaw),
            right: precise.right ?? percent(rightRaw),
            caseBattery: precise.caseBattery ?? percent(caseRaw),
            leftCharging: chargeFlags & 0b0001 != 0,
            rightCharging: chargeFlags & 0b0010 != 0,
            caseCharging: chargeFlags & 0b0100 != 0
        )
    }

    /// Battery nibbles are 0–10 (×10%); 15 (0xF) means "unavailable".
    private static func percent(_ raw: UInt8) -> Int? {
        raw > 10 ? nil : Int(raw) * 10
    }

    /// Parse-failure diagnostics: a malformed payload usually means per-model calibration is needed.
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Voltio", category: "continuity"
    )
}
