import XCTest
import Alfy
@testable import meteocatalf

/// The cache policy of every request: pure, no network and no Alfy cache involved.
final class ServerDataRequestPolicyTests: XCTestCase {

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // The day of the 2nd of October 2026 (UTC) ends at 00:00 on the 3rd and settles at 01:00.
    private let day = DayKey(year: 2026, month: 10, day: 2)

    // MARK: - DayKey.cacheTTL -

    func testDayInProgressIsCachedForTheRefreshInterval() {
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 2, 15)), 3600)
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 2, 15)), DayKey.refreshInterval)
    }

    /// meteo.cat can answer the first minutes of a day with an empty page; it must not be cached for an hour.
    func testFirstHourOfADayIsCachedForFiveMinutesOnly() {
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 2, 0, 0)), 300)
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 2, 0, 10)), DayKey.emptyPageTTL)
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 2, 0, 59)), 300)
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 2, 1, 0)), 3600)
    }

    func testFirstHourRuleDoesNotApplyToTheDayThatJustEnded() {
        // 00:10 on the 3rd is the first hour of the 3rd, not of the 2nd
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 3, 0, 10)), 3600)
    }

    func testDailyRequestInTheFirstHourUsesTheShortTTL() {
        let request = dailyRequest(now: utc(2026, 10, 2, 0, 10))
        XCTAssertEqual(request.ttl, 300)
        XCTAssertEqual(request.cacheControlBehavior, .ignoreServer)
        XCTAssertEqual(request.allowStaleOnError, false)
    }

    func testDayThatHasEndedButNotSettledIsStillInProgress() {
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 3, 0, 30)), 3600)
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 3, 0, 59)), 3600)
    }

    func testFinalDayIsCachedOnlyForThePageAgeAfterItSettled() {
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 3, 1, 0)), 0)
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 3, 3, 30)), 2.5 * 3600)
        XCTAssertEqual(day.cacheTTL(now: utc(2026, 10, 12, 1, 0)), 9 * 24 * 3600)
    }

    // MARK: - Daily summary -

    private func dailyRequest(now: Date, date: Date? = nil) -> Requester.Request {
        ServerData.makeRequest(for: .requestStation(code: "CC", date: date ?? day.localNoon()), now: now)
    }

    func testDailySummaryOfADayInProgress() {
        let request = dailyRequest(now: utc(2026, 10, 2, 15))
        XCTAssertEqual(request.urlString, "https://www.meteo.cat/observacions/xema/dades?codi=CC&dia=2026-10-02T12:00Z")
        XCTAssertEqual(request.ttl, 3600)
        XCTAssertEqual(request.cacheControlBehavior, .ignoreServer)
        XCTAssertEqual(request.allowStaleOnError, false)
        XCTAssertNil(request.cachePolicy)
        XCTAssertNil(request.isBypassCache)
        XCTAssertTrue(request.headers.isEmpty)
    }

    func testDailySummaryOfAFinalDayLastsFromItsSettleTimeToNow() {
        let settledAt = utc(2026, 10, 3, 1, 0)
        let now = utc(2026, 10, 5, 9, 30)
        let request = dailyRequest(now: now)
        XCTAssertEqual(request.ttl, now.timeIntervalSince(settledAt))
        XCTAssertEqual(request.cacheControlBehavior, .ignoreServer)
        XCTAssertEqual(request.allowStaleOnError, false, "a stale partial page would be stored as a final day for ever")
        XCTAssertNil(request.cachePolicy)
    }

    // MARK: - Stations -

    func testStationListIsCachedFor15DaysAndKeepsStaleOnError() {
        let request = ServerData.makeRequest(for: .stations(forceRefresh: false))
        XCTAssertEqual(request.urlString, "https://www.meteo.cat/observacions/xema")
        XCTAssertEqual(request.ttl, 15 * 24 * 3600)
        XCTAssertEqual(request.cacheControlBehavior, .ignoreServer)
        XCTAssertEqual(request.allowStaleOnError, true)
        XCTAssertNil(request.cachePolicy)
        XCTAssertTrue(request.headers.isEmpty)
    }

    func testStationListPullToRefreshForcesARefreshButKeepsTheRest() {
        let request = ServerData.makeRequest(for: .stations(forceRefresh: true))
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.ttl, 15 * 24 * 3600)
        XCTAssertEqual(request.cacheControlBehavior, .ignoreServer)
        XCTAssertEqual(request.allowStaleOnError, true)
    }

    // MARK: - Current weather -

    func testCurrentWeatherIsCachedFiveMinutes() {
        let request = ServerData.makeRequest(for: .curentWeather(code: "D5"))
        XCTAssertEqual(request.urlString, "https://m.meteo.cat/?codi=D5")
        XCTAssertEqual(request.ttl, 300)
        XCTAssertEqual(request.cacheControlBehavior, .ignoreServer)
        XCTAssertEqual(request.allowStaleOnError, true)
        XCTAssertNil(request.cachePolicy)
        XCTAssertTrue(request.headers.isEmpty)
    }

    // MARK: - Radar images -

    func testRadarMapsAreAskedOfRainViewerAndCachedThreeMinutes() {
        let request = ServerData.makeRequest(for: .radarMaps)
        XCTAssertEqual(request.urlString, "https://api.rainviewer.com/public/weather-maps.json")
        XCTAssertEqual(request.ttl, 180)
        XCTAssertEqual(request.cacheControlBehavior, .ignoreServer)
        XCTAssertEqual(request.allowStaleOnError, true)
        XCTAssertTrue(request.headers.isEmpty)
    }

    // MARK: - Last temperature -

    func testLastTemperatureIsCachedHalfAnHourAndKeepsItsApiKey() {
        let request = ServerData.makeRequest(for: .lastTemperature(forStationCode: "CC"))
        XCTAssertEqual(request.urlString, "https://api.meteo.cat/xema/v1/variables/mesurades/32/ultimes?codiEstacio=CC")
        XCTAssertEqual(request.ttl, 1800)
        XCTAssertEqual(request.cacheControlBehavior, .ignoreServer)
        XCTAssertEqual(request.allowStaleOnError, true)
        XCTAssertNil(request.cachePolicy)
        XCTAssertEqual(request.headers.count, 1)
        guard case .custom(let field, let value)? = request.headers.first else {
            return XCTFail("expected the x-api-key header")
        }
        XCTAssertEqual(field, "x-api-key")
        XCTAssertFalse(value.isEmpty)
    }

    // MARK: - Shared constants -

    func testSharedTTLsMatchTheDatabaseRules() {
        XCTAssertEqual(ServerData.CacheTTL.stations, 60 * 60 * 24 * 15)
        XCTAssertEqual(ServerData.CacheTTL.currentWeather, 60 * 5)
        XCTAssertEqual(ServerData.CacheTTL.lastTemperature, 60 * 30)
    }
}
