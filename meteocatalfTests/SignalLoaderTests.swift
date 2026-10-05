import XCTest
@testable import meteocatalf

/// The drops of the loader: where each one is at a given time.
final class SignalLoaderTests: XCTestCase {

    func testADropFadesInAtTheTopAndOutAtTheLine() {
        XCTAssertEqual(Rain.state(at: 0, delay: 0).opacity, 0, accuracy: 0.001)
        XCTAssertEqual(Rain.state(at: Rain.period * 0.5, delay: 0).opacity, 1, accuracy: 0.001)
        XCTAssertEqual(Rain.state(at: Rain.period * 0.999, delay: 0).opacity, 0, accuracy: 0.01)
    }

    func testProgressRepeatsEveryPeriod() {
        let first = Rain.state(at: 0.4, delay: 0).progress
        let later = Rain.state(at: 0.4 + Rain.period * 3, delay: 0).progress
        XCTAssertEqual(first, later, accuracy: 0.0001)
    }

    func testADelayedDropStartsLater() {
        // before its delay a drop is still in the previous turn, well along its fall
        XCTAssertEqual(Rain.state(at: 0.1, delay: 0.5).progress, 1.1 / Rain.period, accuracy: 0.0001)
        XCTAssertEqual(Rain.state(at: 0.5, delay: 0.5).progress, 0, accuracy: 0.0001)
    }

    func testEveryColumnHasADropInTheAirAtTheStillTime() {
        for delay in Rain.delays {
            XCTAssertEqual(Rain.state(at: Rain.stillTime, delay: delay).opacity, 1, accuracy: 0.001, "delay \(delay)")
        }
    }

    func testLayoutsHaveTheDesignedColumnsAndFitTheirDrops() {
        let regular = Rain.Layout(.regular)
        XCTAssertEqual(regular.columns, 5)
        XCTAssertEqual(regular.width, 112)
        XCTAssertLessThan(regular.drop * CGFloat(regular.columns), regular.width)

        let compact = Rain.Layout(.compact)
        XCTAssertEqual(compact.columns, 3)
        XCTAssertLessThan(compact.width, regular.width)
    }
}
