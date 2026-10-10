import XCTest
@testable import meteocatalf

final class HomeStationWidgetFetcherTests: XCTestCase {

    /// Records the URLs a stub `load` receives. A class so the `@Sendable` closure can capture it; `fetch` calls the
    /// stub from two child tasks at once, hence the lock.
    private final class LoadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func record(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return urls.count
        }

        var absoluteStrings: Set<String> {
            lock.lock()
            defer { lock.unlock() }
            return Set(urls.map(\.absoluteString))
        }
    }

    private enum StubError: Error {
        case unavailable
    }

    /// Shaped like the pages `ServerData` scrapes: the daily table comes first, the metadata table after it.
    private enum Page {
        static let daily = """
        <html><body><div id="fitxa-ema"><h2>Orís</h2></div>
        <table><caption>Dades diàries de l'estació meteorològica</caption><tbody>
          <tr><th scope="row">Temperatura mitjana</th><td colspan="2"> 17.0 °C </td></tr>
          <tr><th scope="row">Temperatura màxima</th><td>20.1 °C</td><td>13:36 TU</td></tr>
          <tr><th scope="row">Temperatura mínima</th><td>12.4 °C</td><td>06:10 TU</td></tr>
          <tr><th scope="row">Precipitació acumulada</th><td colspan="2">1.4 mm</td></tr>
        </tbody></table>
        <table><caption>Metadades estació meteorològica</caption>
          <tr><th scope="row">Municipi</th><td>Orís</td></tr></table>
        </body></html>
        """

        static let current = """
        <html><body><div class="temp"> 18 <abbr>°C</abbr></div></body></html>
        """
    }

    private let madrid = TimeZone(identifier: "Europe/Madrid")!
    private let expectedRows = [
        "Temperatura mitjana = 17.0 °C",
        "Temperatura màxima = 20.1 °C",
        "Temperatura mínima = 12.4 °C",
        "Precipitació acumulada = 1.4 mm"
    ]
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HomeStationWidgetFetcherTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = madrid
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Serves the fixtures by host (`m.meteo.cat` is the current weather, anything else the daily page).
    /// A host listed in `failing` throws.
    private func routedLoad(_ log: LoadLog, failing: Set<String> = []) -> HomeStationWidgetFetcher.Load {
        return { url in
            log.record(url)
            guard !failing.contains(url.host ?? "") else { throw StubError.unavailable }
            let html = url.host == "m.meteo.cat" ? Page.current : Page.daily
            return Data(html.utf8)
        }
    }

    /// "title = value" per row, so the rows can be compared with XCTAssertEqual (tuples aren't Equatable).
    private func pairs(_ rows: [(key: String, value: String)]?) -> [String]? {
        return rows?.map { "\($0.key) = \($0.value)" }
    }

    private func snapshot(cityCode: String?, updatedAt: Date) -> HomeStationWidgetSnapshot {
        return HomeStationWidgetSnapshot(
            stationName: "Orís", stationCode: "CC", cityCode: cityCode, updatedAt: updatedAt
        )
    }

    private func selfRefresh(load: @escaping HomeStationWidgetFetcher.Load) -> HomeStationWidgetSelfRefresh {
        return HomeStationWidgetSelfRefresh(
            store: HomeStationWidgetStore(defaults: defaults),
            fetcher: HomeStationWidgetFetcher(load: load)
        )
    }

    // MARK: - Parsing

    func testCurrentTemperatureIsTheTextBeforeTheUnit() {
        XCTAssertEqual(HomeStationWidgetFetcher.parseCurrentTemp(html: Page.current), "18")
    }

    func testCurrentTemperatureIsNilWithoutTheTempDiv() {
        let html = "<html><body><div class=\"other\">18</div></body></html>"
        XCTAssertNil(HomeStationWidgetFetcher.parseCurrentTemp(html: html))
    }

    func testCurrentTemperatureIsNilWhenTheDivHasNoNumber() {
        XCTAssertNil(HomeStationWidgetFetcher.parseCurrentTemp(html: "<div class=\"temp\"><abbr>°C</abbr></div>"))
    }

    func testDailyRowsAreTitleAndValueOfEachRow() {
        XCTAssertEqual(pairs(HomeStationWidgetFetcher.parseDailyRows(html: Page.daily)), expectedRows)
    }

    func testMetadataOnlyPageHasNoDailyRows() {
        let html = """
        <html><body><table><caption>Metadades estació</caption>
        <tr><th>Municipi</th><td>Orís</td></tr></table></body></html>
        """
        XCTAssertNil(HomeStationWidgetFetcher.parseDailyRows(html: html))
    }

    func testPageWithoutTableHasNoDailyRows() {
        XCTAssertNil(HomeStationWidgetFetcher.parseDailyRows(html: "<html><body><h2>Orís</h2></body></html>"))
    }

    // MARK: - URLs

    func testDailyURLUsesTheDayInTheGivenZone() {
        let url = HomeStationWidgetFetcher.dailyURL(
            stationCode: "CC", date: date(2026, 10, 9, 23, 30), timeZone: madrid
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.meteo.cat/observacions/xema/dades?codi=CC&dia=2026-10-09T12:00Z"
        )
    }

    func testDailyURLJustAfterMidnightIsTheNewDay() {
        // 00:30 on the 10th in Madrid is still the 9th in UTC; the page asks for the Madrid day.
        let url = HomeStationWidgetFetcher.dailyURL(
            stationCode: "CC", date: date(2026, 10, 10, 0, 30), timeZone: madrid
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.meteo.cat/observacions/xema/dades?codi=CC&dia=2026-10-10T12:00Z"
        )
    }

    func testCurrentWeatherURLUsesTheCityCode() {
        XCTAssertEqual(
            HomeStationWidgetFetcher.currentWeatherURL(cityCode: "080193")?.absoluteString,
            "https://m.meteo.cat/?codi=080193"
        )
    }

    // MARK: - Fetch

    func testFetchReadsBothPages() async {
        let log = LoadLog()
        let fetcher = HomeStationWidgetFetcher(load: routedLoad(log))

        let result = await fetcher.fetch(
            stationCode: "CC", cityCode: "080193", now: date(2026, 10, 9, 23, 30), timeZone: madrid
        )

        XCTAssertEqual(pairs(result.rows), expectedRows)
        XCTAssertEqual(result.rawTemp, "18")
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log.absoluteStrings, Set([
            "https://www.meteo.cat/observacions/xema/dades?codi=CC&dia=2026-10-09T12:00Z",
            "https://m.meteo.cat/?codi=080193"
        ]))
    }

    func testFailingDailyPageLeavesOnlyTheTemperature() async {
        let fetcher = HomeStationWidgetFetcher(load: routedLoad(LoadLog(), failing: ["www.meteo.cat"]))

        let result = await fetcher.fetch(
            stationCode: "CC", cityCode: "080193", now: date(2026, 10, 9, 23, 30), timeZone: madrid
        )

        XCTAssertNil(result.rows)
        XCTAssertEqual(result.rawTemp, "18")
    }

    func testFailingCurrentWeatherLeavesOnlyTheRows() async {
        let fetcher = HomeStationWidgetFetcher(load: routedLoad(LoadLog(), failing: ["m.meteo.cat"]))

        let result = await fetcher.fetch(
            stationCode: "CC", cityCode: "080193", now: date(2026, 10, 9, 23, 30), timeZone: madrid
        )

        XCTAssertEqual(pairs(result.rows), expectedRows)
        XCTAssertNil(result.rawTemp)
    }

    func testBothPagesFailingLeavesBothEmpty() async {
        let fetcher = HomeStationWidgetFetcher(
            load: routedLoad(LoadLog(), failing: ["www.meteo.cat", "m.meteo.cat"])
        )

        let result = await fetcher.fetch(
            stationCode: "CC", cityCode: "080193", now: date(2026, 10, 9, 23, 30), timeZone: madrid
        )

        XCTAssertNil(result.rows)
        XCTAssertNil(result.rawTemp)
    }

    // MARK: - Self refresh

    func testWithoutASnapshotNothingIsDownloadedOrSaved() async {
        let now = date(2026, 10, 9, 12, 0)
        let log = LoadLog()

        await selfRefresh(load: routedLoad(log)).refreshIfNeeded(now: now)

        XCTAssertEqual(log.count, 0)
        XCTAssertNil(HomeStationWidgetStore(defaults: defaults).load())
    }

    func testSnapshotWithoutACityCodeIsNotRefreshed() async {
        let now = date(2026, 10, 9, 12, 0)
        let store = HomeStationWidgetStore(defaults: defaults)
        let log = LoadLog()

        for cityCode in [nil, ""] as [String?] {
            let old = snapshot(cityCode: cityCode, updatedAt: now.addingTimeInterval(-3600))
            store.save(old)
            await selfRefresh(load: routedLoad(log)).refreshIfNeeded(now: now)
            XCTAssertEqual(store.load(), old)
        }

        XCTAssertEqual(log.count, 0)
    }

    func testSnapshotUpdatedFiveMinutesAgoIsNotRefreshed() async {
        let now = date(2026, 10, 9, 12, 0)
        let store = HomeStationWidgetStore(defaults: defaults)
        let recent = snapshot(cityCode: "080193", updatedAt: now.addingTimeInterval(-5 * 60))
        store.save(recent)
        let log = LoadLog()

        await selfRefresh(load: routedLoad(log)).refreshIfNeeded(now: now)

        XCTAssertEqual(log.count, 0)
        XCTAssertEqual(store.load(), recent)
    }

    func testSnapshotUpdatedElevenMinutesAgoIsRefreshed() async {
        let now = date(2026, 10, 9, 12, 0)
        let store = HomeStationWidgetStore(defaults: defaults)
        store.save(snapshot(cityCode: "080193", updatedAt: now.addingTimeInterval(-11 * 60)))
        let log = LoadLog()

        await selfRefresh(load: routedLoad(log)).refreshIfNeeded(now: now)

        XCTAssertEqual(log.count, 2)
        let saved = store.load()
        XCTAssertEqual(saved?.stationCode, "CC")
        XCTAssertEqual(saved?.cityCode, "080193")
        XCTAssertEqual(saved?.currentTemp, "18 °C")
        XCTAssertEqual(saved?.currentTempAt, now)
        XCTAssertEqual(saved?.maxTemp, "20.1 °C")
        XCTAssertEqual(saved?.minTemp, "12.4 °C")
        XCTAssertEqual(saved?.updatedAt, now)
    }

    func testBothPagesFailingKeepsTheSnapshot() async {
        let now = date(2026, 10, 9, 12, 0)
        let store = HomeStationWidgetStore(defaults: defaults)
        let before = snapshot(cityCode: "080193", updatedAt: now.addingTimeInterval(-11 * 60))
        store.save(before)
        let log = LoadLog()

        await selfRefresh(
            load: routedLoad(log, failing: ["www.meteo.cat", "m.meteo.cat"])
        ).refreshIfNeeded(now: now)

        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(store.load(), before)
    }

    func testStationChangedDuringTheDownloadIsLeftAlone() async {
        let now = date(2026, 10, 9, 12, 0)
        let store = HomeStationWidgetStore(defaults: defaults)
        store.save(snapshot(cityCode: "080193", updatedAt: now.addingTimeInterval(-11 * 60)))
        let log = LoadLog()
        let otherStation = HomeStationWidgetSnapshot(
            stationName: "Sant Cugat", stationCode: "XX", cityCode: "080194", updatedAt: now
        )
        let base = routedLoad(log)
        // The app switches the home station while the widget is downloading.
        let load: HomeStationWidgetFetcher.Load = { url in
            store.save(otherStation)
            return try await base(url)
        }

        await selfRefresh(load: load).refreshIfNeeded(now: now)

        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(store.load(), otherStation)
    }
}
