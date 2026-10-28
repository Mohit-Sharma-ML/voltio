import XCTest
@testable import PowerCore

final class ContinuityDecoderTests: XCTestCase {

    /// Builds a proximity-pairing advert: Apple company id + a 0x07 TLV whose
    /// payload carries the given battery/status bytes (padded to length 25).
    private func advert(status: UInt8, pods: UInt8, caseByte: UInt8,
                        modelHi: UInt8 = 0x0E, modelLo: UInt8 = 0x20) -> Data {
        var payload: [UInt8] = [0x01, modelHi, modelLo, status, pods, caseByte]
        payload += Array(repeating: 0, count: 25 - payload.count)
        var bytes: [UInt8] = [0x4C, 0x00, 0x07, UInt8(payload.count)]
        bytes += payload
        return Data(bytes)
    }

    func testDecodesBatteryNibblesWhenNotFlipped() throws {
        // status 0x20 -> flip == false -> left = low nibble, right = high nibble.
        let pods = ContinuityDecoder.decodeProximityPairing(
            manufacturerData: advert(status: 0x20, pods: 0x53, caseByte: 0x29)
        )
        let battery = try XCTUnwrap(pods)
        XCTAssertEqual(battery.model, 0x0E20)
        XCTAssertEqual(battery.left, 30)
        XCTAssertEqual(battery.right, 50)
        XCTAssertEqual(battery.caseBattery, 90)
        XCTAssertFalse(battery.leftCharging)
        XCTAssertTrue(battery.rightCharging)   // charge flag bit 1
        XCTAssertFalse(battery.caseCharging)
    }

    /// Advert captured live 2026-10-17 from AirPods 4 ANC (0x1B20); tail masked with zeros.
    func testRealCapturedAirPods4ANC() throws {
        let data = Data([
            0x4C, 0x00, 0x07, 0x19,             // Apple, type 0x07, len 25
            0x01, 0x1B, 0x20, 0x73,             // prefix, model 0x1B20, status
            0xAA, 0x97, 0x32, 0x00, 0x08, 0x08, // pods/case nibbles + flags
        ] + Array(repeating: 0, count: 19))
        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(manufacturerData: data))
        XCTAssertEqual(battery.model, 0x1B20)
        XCTAssertEqual(battery.left, 100)
        XCTAssertEqual(battery.right, 100)
        XCTAssertEqual(battery.caseBattery, 70)
        XCTAssertTrue(battery.leftCharging)
        XCTAssertFalse(battery.rightCharging)
    }

    func testFlipSwapsLeftAndRight() throws {
        // status 0x00 -> flip == true -> left = high nibble, right = low nibble.
        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(
                manufacturerData: advert(status: 0x00, pods: 0x53, caseByte: 0x00)
            )
        )
        XCTAssertEqual(battery.left, 50)
        XCTAssertEqual(battery.right, 30)
    }

    func testUnavailableNibbleBecomesNil() throws {
        // High nibble 0xF (15) is the "unavailable" sentinel.
        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(
                manufacturerData: advert(status: 0x20, pods: 0xF3, caseByte: 0x05)
            )
        )
        XCTAssertEqual(battery.left, 30)     // low nibble
        XCTAssertNil(battery.right)          // high nibble 0xF
        XCTAssertEqual(battery.caseBattery, 50)
    }

    func testSkipsOtherContinuityMessagesBeforePairing() throws {
        // Prepend an unrelated TLV (type 0x10, len 2) before the 0x07 message.
        var bytes: [UInt8] = [0x4C, 0x00, 0x10, 0x02, 0xAA, 0xBB]
        let pairing = advert(status: 0x20, pods: 0x88, caseByte: 0x07)
        bytes += [UInt8](pairing)[2...]   // drop the duplicate company id
        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(manufacturerData: Data(bytes))
        )
        XCTAssertEqual(battery.left, 80)
        XCTAssertEqual(battery.right, 80)
        XCTAssertEqual(battery.caseBattery, 70)
    }

    func testRejectsNonAppleManufacturerData() {
        let data = Data([0x4C, 0x01, 0x07, 0x06, 0x01, 0x0E, 0x20, 0x20, 0x55, 0x05])
        XCTAssertNil(ContinuityDecoder.decodeProximityPairing(manufacturerData: data))
    }

    func testRejectsTooShortData() {
        XCTAssertNil(ContinuityDecoder.decodeProximityPairing(manufacturerData: Data([0x4C, 0x00])))
    }

    // MARK: - Owner address suffix

    /// Real advert tail: paired iPhone 80:96:98:43:b3:52 → payload[13...15] = 43 b3 52.
    func testOwnerAddressSuffixFromRealAdvert() {
        let data = Data([
            0x4C, 0x00, 0x07, 0x19,
            0x01, 0x1B, 0x20, 0x22, 0xF5, 0x8F, 0x12, 0x00, 0x09, 0x09, 0x3B,
            0xFF, 0xFF, 0x43, 0xB3, 0x52,
        ] + Array(repeating: 0, count: 9))
        XCTAssertEqual(ContinuityDecoder.ownerAddressSuffix(manufacturerData: data), [0x43, 0xB3, 0x52])
    }

    /// Classic short payloads carry no tail; nil, not a fabricated suffix.
    func testOwnerAddressSuffixAbsentOnShortPayload() {
        let data = Data([0x4C, 0x00, 0x07, 0x06, 0x01, 0x0E, 0x20, 0x20, 0x55, 0x05])
        XCTAssertNil(ContinuityDecoder.ownerAddressSuffix(manufacturerData: data))
    }

    func testOwnerAddressSuffixRejectsNonApple() {
        let data = Data([0x4D, 0x00, 0x07, 0x19] + Array(repeating: 0x43, count: 20))
        XCTAssertNil(ContinuityDecoder.ownerAddressSuffix(manufacturerData: data))
    }

    // MARK: - Precise levels (AirPods 4, model 0x1B20)

    /// Real adverts from AirPods 4 (ANC), macOS reading 57–59% left; the nibble alone yields only 50%.
    func testAirPods4UsesPreciseLeftByte() throws {
        // payload: 01 1b 20 22 f5 8f 12 00 09 09 3b ...
        let data = Data([
            0x4C, 0x00, 0x07, 0x19,
            0x01, 0x1B, 0x20, 0x22, 0xF5, 0x8F, 0x12, 0x00, 0x09, 0x09, 0x3B,
        ] + Array(repeating: 0, count: 14))
        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(manufacturerData: data))

        XCTAssertEqual(battery.model, 0x1B20)
        XCTAssertEqual(battery.left, 59)     // was 50 from the nibble alone
        XCTAssertNil(battery.right)          // 0xF sentinel — genuinely absent
        XCTAssertNil(battery.caseBattery)    // 0xF sentinel
    }

    /// Live capture 2026-10-28 with both pods connected and charging, macOS reporting
    /// Left 100%, Right 100%, Case 35%. Bytes 10-12 are the precise levels with bit 7
    /// set on the two charging pods; the case nibble alone reads 30%.
    func testLiveChargingCaptureDecodesAllCompartments() throws {
        let payload: [UInt8] = [
            0x01, 0x1B, 0x20, 0x55, 0xAA, 0xB3, 0x31, 0x00, 0x08, 0x48,
            0xE4, 0xE4, 0x23, 0x43, 0xB3, 0x52, 0x5E, 0x30, 0x44, 0x26,
            0x13, 0xC1, 0xE6, 0x12, 0x86,
        ]
        let battery = try XCTUnwrap(ContinuityDecoder.decodeProximityPairing(
            manufacturerData: Data([0x4C, 0x00, 0x07, 0x19] + payload)))

        XCTAssertEqual(battery.left, 100)
        XCTAssertEqual(battery.right, 100)
        XCTAssertEqual(battery.caseBattery, 35)   // was 30 from the nibble
        XCTAssertTrue(battery.leftCharging)
        XCTAssertTrue(battery.rightCharging)
        XCTAssertFalse(battery.caseCharging)
    }

    /// Bit 7 marks a charging compartment; a charging pod at 87% must not be rejected
    /// as out-of-range and fall back to the 80% tens band.
    func testChargingBitDoesNotHideThePreciseValue() throws {
        // pods 0x88 → left band 8; byte10 = 0x80 | 87
        var payload: [UInt8] = [0x01, 0x1B, 0x20, 0x22, 0x88, 0x00]
        payload += Array(repeating: 0, count: 4)
        payload += [0x80 | 87, 0, 0]
        payload += Array(repeating: 0, count: 25 - payload.count)
        let battery = try XCTUnwrap(ContinuityDecoder.decodeProximityPairing(
            manufacturerData: Data([0x4C, 0x00, 0x07, UInt8(payload.count)] + payload)))

        XCTAssertEqual(battery.left, 87)
    }

    /// The right ear has a precise byte too (byte 11) — the earlier single-pod capture
    /// only ever reported the 0xF sentinel there.
    func testRightEarUsesItsPreciseByte() throws {
        // pods 0x55 → left band 5, right band 5; byte11 = 0x80 | 57
        var payload: [UInt8] = [0x01, 0x1B, 0x20, 0x22, 0x55, 0x00]
        payload += Array(repeating: 0, count: 4)
        payload += [50, 0x80 | 57, 0]
        payload += Array(repeating: 0, count: 25 - payload.count)
        let battery = try XCTUnwrap(ContinuityDecoder.decodeProximityPairing(
            manufacturerData: Data([0x4C, 0x00, 0x07, UInt8(payload.count)] + payload)))

        XCTAssertEqual(battery.left, 50)
        XCTAssertEqual(battery.right, 57)          // not the 50% nibble value
    }

    /// Consecutive real adverts as the left ear drained: 0xF5 → 57/58/59, 0xF6 → 60.
    func testAirPods4PreciseLeftTracksDrain() throws {
        for (pods, byte10, expected) in [
            (0xF5, 0x39, 57), (0xF5, 0x3A, 58), (0xF5, 0x3B, 59), (0xF6, 0x3C, 60),
        ] {
            let data = Data([
                UInt8(0x4C), 0x00, 0x07, 0x19,
                0x01, 0x1B, 0x20, 0x22, UInt8(pods), 0x8F, 0x12, 0x00, 0x09, 0x09, UInt8(byte10),
            ] + Array(repeating: 0, count: 14))
            let battery = try XCTUnwrap(
                ContinuityDecoder.decodeProximityPairing(manufacturerData: data))
            XCTAssertEqual(
                battery.left, expected,
                "pods=0x\(String(pods, radix: 16)) byte10=\(byte10)")
        }
    }

    /// Classic payload guard: 100% nibble vs unrelated byte 10 = 50, so the nibble wins.
    func testPreciseByteDoesNotOverrideMismatchedClassicPayload() throws {
        var payload: [UInt8] = [0x01, 0x1B, 0x20, 0x73, 0xAA, 0x97]
        payload += Array(repeating: 0, count: 4)
        payload.append(0x32)                       // byte 10 = 50, disagrees
        payload += Array(repeating: 0, count: 14)
        let data = Data([UInt8(0x4C), 0x00, 0x07, UInt8(payload.count)] + payload)

        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(manufacturerData: data))
        XCTAssertEqual(battery.left, 100)          // unchanged classic decode
        XCTAssertEqual(battery.right, 100)
        XCTAssertEqual(battery.caseBattery, 70)
    }

    /// A compartment with no precise byte keeps its nibble value.
    func testCompartmentsWithoutPreciseEvidenceKeepNibbles() throws {
        // status 0x22 → flip false → left=low nibble (5), right=high nibble (8)
        var payload: [UInt8] = [0x01, 0x1B, 0x20, 0x22, 0x85, 0x00]
        payload += Array(repeating: 0, count: 4)
        payload.append(57)                         // byte 10 agrees with 50s band
        payload += Array(repeating: 0, count: 14)
        let data = Data([UInt8(0x4C), 0x00, 0x07, UInt8(payload.count)] + payload)

        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(manufacturerData: data))
        XCTAssertEqual(battery.left, 57)           // refined
        XCTAssertEqual(battery.right, 80)          // byte 11 empty → nibble value
    }

    /// Calibrated on 0x1B20 only, so another model's byte 10 must never be read as a percentage.
    func testPreciseByteIsScopedToItsCalibratedModel() throws {
        // Same payload as AirPods 4 but model 0x0E20; without the model gate this would decode as 57%.
        var payload: [UInt8] = [0x01, 0x0E, 0x20, 0x22, 0x85, 0x00]
        payload += Array(repeating: 0, count: 4)
        payload.append(57)
        payload += Array(repeating: 0, count: 14)
        let data = Data([UInt8(0x4C), 0x00, 0x07, UInt8(payload.count)] + payload)

        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(manufacturerData: data))
        XCTAssertEqual(battery.model, 0x0E20)
        XCTAssertEqual(battery.left, 50)           // classic nibble, not 57
        XCTAssertEqual(battery.right, 80)
    }

    /// Stated once in code, so widening the calibration is a deliberate edit.
    func testCalibratedModelMatchesAirPods4() {
        XCTAssertEqual(ContinuityDecoder.preciseLevelModel, 0x1B20)
    }
}
