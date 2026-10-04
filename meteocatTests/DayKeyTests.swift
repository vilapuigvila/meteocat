import XCTest
@testable import meteocat

final class DayKeyTests: XCTestCase {

    private let madrid = TimeZone(identifier: "Europe/Madrid")!

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testKeyFollowsTheDeviceTimeZone() {
        // 00:30 on the 5th in Madrid (CEST) is still the 4th in UTC
        let instant = utc(2026, 10, 4, 22, 30)
        XCTAssertEqual(DayKey(instant, timeZone: madrid), DayKey(year: 2026, month: 10, day: 5))
        XCTAssertEqual(DayKey(instant, timeZone: TimeZone(identifier: "UTC")!), DayKey(year: 2026, month: 10, day: 4))
    }

    func testRequestParameterIsPlainGregorianDigits() {
        XCTAssertEqual(DayKey(year: 2026, month: 10, day: 5).requestParameter, "2026-10-05T12:00Z")
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 31).requestParameter, "2026-01-31T12:00Z")
    }

    func testValueRoundTrips() {
        let key = DayKey(year: 2026, month: 3, day: 9)
        XCTAssertEqual(key.value, 20260309)
        XCTAssertEqual(DayKey(value: key.value), key)
    }

    func testFirstLocalHoursOfADayHaveNoServerDataYet() {
        let day = DayKey(year: 2026, month: 10, day: 5)
        XCTAssertFalse(day.hasStarted(at: utc(2026, 10, 4, 22, 30)))   // 00:30 in Madrid
        XCTAssertTrue(day.hasStarted(at: utc(2026, 10, 5, 0, 0)))
    }

    func testDayIsCompleteOnlyWhenDownloadedAfterItEndedAndSettled() {
        let day = DayKey(year: 2026, month: 10, day: 2)
        let end = utc(2026, 10, 3)
        XCTAssertFalse(day.isComplete(fetchedAt: utc(2026, 10, 2, 12)))                   // during the day
        XCTAssertFalse(day.isComplete(fetchedAt: end.addingTimeInterval(3599)))            // not settled
        XCTAssertTrue(day.isComplete(fetchedAt: end.addingTimeInterval(3600)))
    }

    func testDayInProgressIsRefreshedAfterAnHour() {
        let day = DayKey(year: 2026, month: 10, day: 4)
        let fetched = utc(2026, 10, 4, 9, 0)
        XCTAssertFalse(day.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(3599)))
        XCTAssertTrue(day.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(3600)))
    }

    /// The bug this guards: a day downloaded while it was in progress was served for ever.
    func testPartialDayDownloadedLongAgoIsRefreshedEvenWhenTheDayIsOver() {
        let day = DayKey(year: 2026, month: 10, day: 2)
        let fetchedDuringTheDay = utc(2026, 10, 2, 9, 0)
        XCTAssertTrue(day.needsRefresh(fetchedAt: fetchedDuringTheDay, now: utc(2026, 10, 4, 9, 0)))
    }

    func testCompleteDayIsNeverRefreshed() {
        let day = DayKey(year: 2026, month: 10, day: 2)
        let fetched = utc(2026, 10, 3, 6, 0)
        XCTAssertFalse(day.needsRefresh(fetchedAt: fetched, now: utc(2027, 1, 1)))
    }

    func testMonthToDateRunsFromTheFirstToToday() {
        let days = DayKey.monthToDate(utc(2026, 10, 4, 10), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(days.map(\.day), [1, 2, 3, 4])
        XCTAssertEqual(Set(days.map(\.month)), [10])
    }

    func testMonthToDateOnTheFirstIsOneDay() {
        let days = DayKey.monthToDate(utc(2026, 11, 1, 10), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(days, [DayKey(year: 2026, month: 11, day: 1)])
    }

    func testLocalNoonIsInsideTheDay() {
        let day = DayKey(year: 2026, month: 10, day: 5)
        XCTAssertEqual(DayKey(day.localNoon(timeZone: madrid), timeZone: madrid), day)
    }
}
