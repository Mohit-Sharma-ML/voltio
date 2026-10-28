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

/// Decodes Apple BLE Continuity manufacturer data. This format is not published
/// by Apple; the layout below follows widely-used community reverse engineering
/// (OpenPods / furiousMAC) and may need per-model calibration.
public enum ContinuityDecoder {
    /// Apple's Bluetooth company identifier (little-endian in advert data).
    private static let appleCompanyID: (UInt8, UInt8) = (0x4C, 0x00)
    /// TLV type for the Proximity Pairing (AirPods) message.
    private static let proximityPairingType: UInt8 = 0x07

    /// AirPods 4 (ANC) — the only model whose precise left-ear byte is
    /// calibrated. Other models keep the classic nibble decode until someone
    /// captures adverts from them and correlates against a system reading.
    static let preciseLeftEarModel: UInt16 = 0x1B20

    /// Parse the manufacturer-data blob (including the 2-byte company id, as
    /// CoreBluetooth provides it) and return AirPods battery if present.
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

    /// Owner address suffix carried in the advert tail (last 3 bytes), when
    /// present. Apple's proximity-pairing advert for an owned device embeds the
    /// paired phone's Bluetooth address here; it is constant per owner and is
    /// what makes ownership checking possible without trusting display names.
    ///
    /// Observed on AirPods 4 (0x1B20): payload bytes 13–15 were `43 b3 52`,
    /// matching the last three bytes of the paired iPhone's address. Returns
    /// `nil` for payloads too short to carry it (classic 17-byte layouts).
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

        // Model 0x1B20 (AirPods 4) broadcasts a precise percentage in byte 10;
        // its nibble then only carries the tens digit. Confirmed for the LEFT
        // ear from 183 adverts correlated against macOS's own reading:
        // byte[10] tracked the system value while the nibble supplied only the
        // tens band (0xF5 → 57/58/59, 0xF6 → 60).
        //
        // Three deliberate restrictions, each because the evidence supports
        // exactly this much and no more:
        //  - Scoped to the model it was measured on. Other models were never
        //    captured, and byte 10 in the classic layout is unrelated data — a
        //    different model whose tens digit happened to agree would be
        //    silently rewritten by a rule with no evidence behind it.
        //  - Only the left ear. In every captured advert the right ear reported
        //    the 0xF "unavailable" sentinel, so no right-ear byte has evidence
        //    behind it. Guessing one would be worse than omitting it.
        //  - Guarded so it can only refine a value it already agrees with: adopt
        //    the byte only when its tens digit matches the nibble's. Payloads
        //    that keep the classic layout — including the 100% fixture, whose
        //    nibble is 10 while byte 10 holds an unrelated 50 — fail this check
        //    and keep the nibble-derived value.
        let preciseLeft: Int? = {
            guard model == preciseLeftEarModel, payload.count > 10 else { return nil }
            let candidate = Int(payload[10])
            guard candidate <= 100 else { return nil }
            let band = Int(leftRaw)
            guard band <= 10 else { return nil }
            // Require exact agreement with the nibble's tens digit. Every one of
            // 183 captured adverts satisfied this (0xF5 → 57/58/59, 0xF6 → 60),
            // so the nibble and the precise byte advance together. Anything that
            // disagrees belongs to a different field.
            guard candidate / 10 == band else { return nil }
            return candidate
        }()

        return AirPodsBattery(
            model: model,
            // The precise left byte refines the nibble's tens band when the
            // guard accepted it; the right ear keeps the nibble value only.
            left: preciseLeft ?? percent(leftRaw),
            right: percent(rightRaw),
            caseBattery: percent(caseRaw),
            leftCharging: chargeFlags & 0b0001 != 0,
            rightCharging: chargeFlags & 0b0010 != 0,
            caseCharging: chargeFlags & 0b0100 != 0
        )
    }

    /// Battery nibbles are 0–10 (×10%); 15 (0xF) means "unavailable".
    private static func percent(_ raw: UInt8) -> Int? {
        raw > 10 ? nil : Int(raw) * 10
    }

    /// Parse-failure diagnostics: a malformed payload here usually means the
    /// community-reverse-engineered layout needs per-model calibration.
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Voltio", category: "continuity"
    )
}
