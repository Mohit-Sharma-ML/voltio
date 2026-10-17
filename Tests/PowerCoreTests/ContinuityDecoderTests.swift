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
}
