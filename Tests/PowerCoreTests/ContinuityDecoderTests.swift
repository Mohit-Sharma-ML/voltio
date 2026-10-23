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

    /// Real-world regression: advert captured live 2026-10-17 from AirPods 4
    /// ANC (model 0x1B20, previously untested byte) via a 30 s BLE scan.
    /// Tail bytes randomized per advert by Apple — masked with zeros; only
    /// the first 10 payload bytes are decoder-relevant.
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

    /// Real advert tail carried the paired iPhone's address suffix
    /// (iPhone 80:96:98:43:b3:52 → payload[13...15] = 43 b3 52). This is what
    /// lets ownership be proven without trusting a display name.
    func testOwnerAddressSuffixFromRealAdvert() {
        let data = Data([
            0x4C, 0x00, 0x07, 0x19,
            0x01, 0x1B, 0x20, 0x22, 0xF5, 0x8F, 0x12, 0x00, 0x09, 0x09, 0x3B,
            0xFF, 0xFF, 0x43, 0xB3, 0x52,
        ] + Array(repeating: 0, count: 9))
        XCTAssertEqual(ContinuityDecoder.ownerAddressSuffix(manufacturerData: data), [0x43, 0xB3, 0x52])
    }

    /// Classic short payloads do not carry the tail; return nil rather than
    /// fabricating a suffix from unrelated bytes.
    func testOwnerAddressSuffixAbsentOnShortPayload() {
        let data = Data([0x4C, 0x00, 0x07, 0x06, 0x01, 0x0E, 0x20, 0x20, 0x55, 0x05])
        XCTAssertNil(ContinuityDecoder.ownerAddressSuffix(manufacturerData: data))
    }

    func testOwnerAddressSuffixRejectsNonApple() {
        let data = Data([0x4D, 0x00, 0x07, 0x19] + Array(repeating: 0x43, count: 20))
        XCTAssertNil(ContinuityDecoder.ownerAddressSuffix(manufacturerData: data))
    }

    // MARK: - Precise left-ear refinement (AirPods 4, model 0x1B20)

    /// Real adverts captured 2026-10-23 from AirPods 4 (ANC) while macOS
    /// reported 57–59% left and 88% right. The classic nibble alone yields only
    /// the tens band (0xF5 → 50%), which is why the panel disagreed with the OS.
    /// Byte 10 carried the exact value.
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

    /// Consecutive real adverts as the left ear drained. Values and the pods
    /// byte are transcribed from the 2026-10-23 capture: 0xF5 accompanied
    /// 57/58/59 and 0xF6 accompanied 60 — in all 183 adverts the nibble's tens
    /// digit matched the precise byte, which is what the decoder's guard relies
    /// on.
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

    /// The refinement must never fire on a classic payload. The 100% fixture's
    /// nibble is 10 (100%) while its byte 10 holds an unrelated 0x32 (50) — the
    /// tens digits disagree, so the nibble value must be kept.
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

    /// A right ear that is genuinely present must still decode from its nibble;
    /// the refinement is left-only and must not disturb it.
    func testPreciseLeftDoesNotAffectPresentRightEar() throws {
        // status 0x22 → flip false → left=low nibble (5), right=high nibble (8)
        var payload: [UInt8] = [0x01, 0x1B, 0x20, 0x22, 0x85, 0x00]
        payload += Array(repeating: 0, count: 4)
        payload.append(57)                         // byte 10 agrees with 50s band
        payload += Array(repeating: 0, count: 14)
        let data = Data([UInt8(0x4C), 0x00, 0x07, UInt8(payload.count)] + payload)

        let battery = try XCTUnwrap(
            ContinuityDecoder.decodeProximityPairing(manufacturerData: data))
        XCTAssertEqual(battery.left, 57)           // refined
        XCTAssertEqual(battery.right, 80)          // untouched nibble value
    }
}
