import XCTest
@testable import PowerCore

final class ChargeLimitReaderTests: XCTestCase {

    // MARK: - pmset output parsing

    func testParseNoLimitSentinel() {
        let output = "No battery level limits set\n"
        XCTAssertNil(ChargeLimitReader.parsePmsetOutput(output))
    }

    func testParseEmptyOutput() {
        XCTAssertNil(ChargeLimitReader.parsePmsetOutput(""))
        XCTAssertNil(ChargeLimitReader.parsePmsetOutput("\n\n"))
    }

    func testParseLimitRow() {
        // powerd prints rows carrying `level=NN` when a limit is configured.
        let output = """
        Battery level limits:
         level=80 0x2
        """
        XCTAssertEqual(ChargeLimitReader.parsePmsetOutput(output), 80)
    }

    func testParseLimitRowCaseInsensitiveSentinel() {
        XCTAssertNil(
            ChargeLimitReader.parsePmsetOutput("NO BATTERY LEVEL LIMITS SET\n")
        )
    }

    func testParseFirstOfMultipleRows() {
        let output = """
        Battery level limits:
         level=80 0x2
         level=95 0x1
        """
        XCTAssertEqual(ChargeLimitReader.parsePmsetOutput(output), 80)
    }

    func testParseIgnoresRowsWithoutDigits() {
        let output = """
        Battery level limits:
         level= 0x2
        """
        XCTAssertNil(ChargeLimitReader.parsePmsetOutput(output))
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(ChargeLimitReader.parsePmsetOutput("unrelated text"))
        XCTAssertNil(ChargeLimitReader.parsePmsetOutput("level=abc"))
    }

    // MARK: - State clamping

    func testStateClampsOutOfRangePercent() {
        XCTAssertEqual(ChargeLimitState(percent: 105).percent, 100)
        XCTAssertEqual(ChargeLimitState(percent: -5).percent, 0)
    }

    func testStateEnabledFlag() {
        XCTAssertTrue(ChargeLimitState(percent: 80).isEnabled)
        XCTAssertFalse(ChargeLimitState(percent: nil).isEnabled)
    }
}
