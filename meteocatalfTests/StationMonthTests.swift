import XCTest
@testable import meteocatalf

final class StationMonthTests: XCTestCase {

    private let utcZone = TimeZone(identifier: "UTC")!
    private let madrid = TimeZone(identifier: "Europe/Madrid")!

    private func rows(temp: String? = nil, rain: String? = nil) -> [DTO.HomeStation] {
        var rows: [DTO.HomeStation] = []
        if let temp { rows.append(.init(name: "Orís", key: "Temperatura mitjana", value: temp, time: nil)) }
        rows.append(.init(name: "Orís", key: "Temperatura màxima", value: "99.9 °C", time: "13:36 TU"))
        if let rain { rows.append(.init(name: "Orís", key: "Precipitació acumulada", value: rain, time: nil)) }
        return rows
    }

    private func day(_ day: Int, temp: String? = nil, rain: String? = nil, complete: Bool = true) -> StationDayInfo {
        StationDayInfo(day: DayKey(year: 2026, month: 10, day: day), info: rows(temp: temp, rain: rain), isComplete: complete)
    }

    /// 4 Oct 2026, 09:00 UTC
    private let now = Date(timeIntervalSince1970: 1_791_104_400)

    // MARK: - Average

    func testAverageIsTheMeanOfTheDailyMeans() {
        let summary = [day(1, temp: "17.0 °C"), day(2, temp: "15.0 °C"), day(3, temp: "16.0 °C")]
            .summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertEqual(summary.averageTemp, 16.0)
        XCTAssertEqual(summary.averageTempText, "16.0 °C")
    }

    func testAverageLeavesOutTheDayInProgress() {
        let summary = [day(1, temp: "17.0 °C"), day(2, temp: "15.0 °C"), day(4, temp: "5.0 °C", complete: false)]
            .summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertEqual(summary.averageTemp, 16.0)
    }

    func testAverageWithOnlyTheDayInProgressIsUnknown() {
        let summary = [day(4, temp: "5.0 °C", complete: false)].summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertNil(summary.averageTemp)
        XCTAssertEqual(summary.averageTempText, "--")
    }

    func testAverageHandlesNegativeAndRounding() {
        XCTAssertEqual([day(1, temp: "-1.0 °C"), day(2, temp: "-2.0 °C")].summary(referenceDate: now, now: now, timeZone: utcZone).averageTemp, -1.5)
        // 0.0 rather than -0.0
        XCTAssertEqual([day(1, temp: "-0.04 °C")].summary(referenceDate: now, now: now, timeZone: utcZone).averageTempText, "0.0 °C")
        // 14.3 and 14.5 -> 14.4
        XCTAssertEqual([day(1, temp: "14.3 °C"), day(2, temp: "14.5 °C")].summary(referenceDate: now, now: now, timeZone: utcZone).averageTemp, 14.4)
    }

    // MARK: - Rain

    func testRainIsTheSumOfEveryDayIncludingTheDayInProgress() {
        let summary = [day(1, rain: "1.4 mm"), day(2, rain: "0.0 mm"), day(4, rain: "44.2 mm", complete: false)]
            .summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertEqual(summary.accumulatedRain, 45.6)
        XCTAssertEqual(summary.accumulatedRainText, "45.6 mm")
    }

    func testRainSumDoesNotDriftWithFloatingPoint() {
        let summary = [day(1, rain: "0.1 mm"), day(2, rain: "0.2 mm")].summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertEqual(summary.accumulatedRain, 0.3)
    }

    func testRainOfTenOrMoreIsNotMistakenForDry() {
        let summary = [day(1, rain: "10.0 mm"), day(2, rain: "20.0 mm")].summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertEqual(summary.accumulatedRain, 30.0)
    }

    func testDryMonthIsZeroNotUnknown() {
        let summary = [day(1, rain: "0.0 mm"), day(2, rain: "0.0 mm")].summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertEqual(summary.accumulatedRainText, "0.0 mm")
    }

    func testNoValuesIsUnknown() {
        let summary = [StationDayInfo]().summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertNil(summary.averageTemp)
        XCTAssertNil(summary.accumulatedRain)
        XCTAssertEqual(summary.accumulatedRainText, "--")
    }

    // MARK: - Parsing and keys

    func testNumberParsing() {
        XCTAssertEqual(StationValue.number(from: "17.0 °C"), 17.0)
        XCTAssertEqual(StationValue.number(from: "1,4 mm"), 1.4)
        XCTAssertEqual(StationValue.number(from: "-3.2 °C"), -3.2)
        XCTAssertEqual(StationValue.number(from: "0.0 mm"), 0.0)
        XCTAssertNil(StationValue.number(from: "--"))
        XCTAssertNil(StationValue.number(from: ""))
    }

    func testRowTitlesMatchIgnoringCaseAndAccents() {
        let items = [
            DTO.HomeStation(name: "", key: "PRECIPITACIÓ ACUMULADA", value: "2.0 mm", time: nil),
            DTO.HomeStation(name: "", key: "temperatura mitjana", value: "12.0 °C", time: nil)
        ]
        XCTAssertEqual(StationValue.text(forKeyContaining: StationValue.accumulatedRainKey, in: items), "2.0 mm")
        XCTAssertEqual(StationValue.text(forKeyContaining: StationValue.averageTempKey, in: items), "12.0 °C")
    }

    // MARK: - Coverage

    func testCountsDaysWithoutValues() {
        // 1...4 expected, 2 of them have values
        let summary = [day(1, temp: "10.0 °C"), day(3, temp: "12.0 °C")].summary(referenceDate: now, now: now, timeZone: utcZone)
        XCTAssertEqual(summary.daysExpected, 4)
        XCTAssertEqual(summary.daysWithData, 2)
        XCTAssertEqual(summary.missingDays, 2)
    }

    func testDayThatHasNotStartedOnTheServerIsNotMissing() {
        // 00:30 on the 5th in Madrid is 22:30 UTC on the 4th: it is the 5th for the user, but the 5th hasn't started.
        let lateNight = Date(timeIntervalSince1970: 1_791_153_000) // 2026-10-04 22:30 UTC
        let summary = [day(1, temp: "10.0 °C"), day(2, temp: "12.0 °C"), day(3, temp: "11.0 °C"), day(4, temp: "9.0 °C")]
            .summary(referenceDate: lateNight.addingTimeInterval(3600), now: lateNight, timeZone: madrid)
        XCTAssertEqual(summary.missingDays, 0)
    }

    // MARK: - Day list

    func testDayListHasOneEntryPerDayWithDashesForMissingOnes() {
        let list = [day(1, temp: "17.0 °C", rain: "1.4 mm"), day(3, temp: "15.0 °C", rain: "0.0 mm"), day(4, temp: "5.0 °C", rain: "3.0 mm", complete: false)]
            .monthDayValues(referenceDate: now, timeZone: utcZone)
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list.map(\.averageTemp), ["17.0 °C", "--", "15.0 °C", "5.0 °C"])
        XCTAssertEqual(list.map(\.accumulatedRain), ["1.4 mm", "--", "0.0 mm", "3.0 mm"])
        XCTAssertEqual(list.map(\.isPartial), [false, false, false, true])
    }

    func testDayListIsInOrderWhateverTheInputOrder() {
        let list = [day(3, temp: "3.0 °C"), day(1, temp: "1.0 °C"), day(2, temp: "2.0 °C")].monthDayValues(referenceDate: now, timeZone: utcZone)
        XCTAssertEqual(list.prefix(3).map(\.averageTemp), ["1.0 °C", "2.0 °C", "3.0 °C"])
    }
}
