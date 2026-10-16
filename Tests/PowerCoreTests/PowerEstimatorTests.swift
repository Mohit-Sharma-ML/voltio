import XCTest
@testable import PowerCore

final class PowerEstimatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFirstSampleSetsEstimateDirectly() {
        let e = PowerEstimator().updated(with: 12.0, at: t0)
        XCTAssertEqual(e.estimateWatts!, 12.0, accuracy: 0.0001)
    }

    func testEMAConvergesTowardNewSamples() {
        var e = PowerEstimator().updated(with: 20.0, at: t0)
        // One step at alpha 0.35: 20 + 0.35*(10-20) = 16.5
        e = e.updated(with: 10.0, at: t0.addingTimeInterval(60))
        XCTAssertEqual(e.estimateWatts!, 16.5, accuracy: 0.0001)

        // Repeated identical samples converge toward 10. Residual after 20
        // steps is 6.5 × 0.65^20 ≈ 0.0013, so tolerance must exceed that.
        for i in 1...20 {
            e = e.updated(with: 10.0, at: t0.addingTimeInterval(Double(60 * (i + 1))))
        }
        XCTAssertEqual(e.estimateWatts!, 10.0, accuracy: 0.01)
    }

    func testEstimateIsNilBeforeAnySample() {
        XCTAssertNil(PowerEstimator().estimateWatts)
    }

    func testStaleSampleDropsPriorEstimate() {
        var e = PowerEstimator().updated(with: 20.0, at: t0)
        e = e.updated(with: 5.0, at: t0.addingTimeInterval(PowerEstimator.sampleMaxAge + 1))
        // The stale 20 W estimate is discarded; 5 W becomes the fresh baseline.
        XCTAssertEqual(e.estimateWatts!, 5.0, accuracy: 0.0001)
    }

    func testSampleJustInsideMaxAgeIsBlended() {
        var e = PowerEstimator().updated(with: 20.0, at: t0)
        e = e.updated(with: 5.0, at: t0.addingTimeInterval(PowerEstimator.sampleMaxAge - 1))
        XCTAssertEqual(e.estimateWatts!, 20.0 + PowerEstimator.alpha * (5.0 - 20.0), accuracy: 0.0001)
    }

    func testResetClearsEstimate() {
        let e = PowerEstimator().updated(with: 7.0, at: t0).reset()
        XCTAssertNil(e.estimateWatts)
    }
}
