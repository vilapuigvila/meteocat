import XCTest
@testable import meteocatalf

final class HomeStationWidgetTests: XCTestCase {

    /// Counts widget reloads; a class so the closure handed to the updater can change it.
    private final class ReloadCounter {
        var count = 0
    }

    private let madrid = TimeZone(identifier: "Europe/Madrid")!
    private let utc = TimeZone(identifier: "UTC")!
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HomeStationWidgetTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func snapshot(
        code: String = "CC",
        currentTemp: String? = nil,
        currentTempAt: Date? = nil,
        maxTemp: String? = nil,
        minTemp: String? = nil,
        extremesDay: Int? = nil,
        updatedAt: Date
    ) -> HomeStationWidgetSnapshot {
        return HomeStationWidgetSnapshot(
            stationName: "Orís",
            stationCode: code,
            currentTemp: currentTemp,
            currentTempAt: currentTempAt,
            maxTemp: maxTemp,
            minTemp: minTemp,
            extremesDay: extremesDay,
            updatedAt: updatedAt
        )
    }

    private func dailyRows() -> [(key: String, value: String)] {
        return [
            (key: "Temperatura mitjana", value: "16.8 °C"),
            (key: "Temperatura màxima", value: "21.3 °C"),
            (key: "Temperatura mínima", value: "12.4 °C")
        ]
    }

    private func makeUpdater(_ counter: ReloadCounter) -> HomeStationWidgetUpdater {
        return HomeStationWidgetUpdater(
            store: HomeStationWidgetStore(defaults: defaults),
            reload: { counter.count += 1 }
        )
    }

    // MARK: - Store

    func testStoreRoundTripsTheSnapshot() {
        let store = HomeStationWidgetStore(defaults: defaults)
        let now = date(2026, 10, 9, 10, 30, in: madrid)
        let saved = snapshot(
            currentTemp: "18 °C", currentTempAt: now, maxTemp: "21.3 °C", minTemp: "12.4 °C",
            extremesDay: 20261009, updatedAt: now
        )
        store.save(saved)
        XCTAssertEqual(store.load(), saved)
    }

    func testClearRemovesTheSnapshot() {
        let store = HomeStationWidgetStore(defaults: defaults)
        store.save(snapshot(updatedAt: date(2026, 10, 9, 10, 30, in: madrid)))
        store.clear()
        XCTAssertNil(store.load())
    }

    func testUndecodableDataLoadsAsNil() {
        defaults.set(Data("not a snapshot".utf8), forKey: HomeStationWidgetStore.key)
        XCTAssertNil(HomeStationWidgetStore(defaults: defaults).load())
    }

    func testStoreWithoutDefaultsDoesNothing() {
        let store = HomeStationWidgetStore(defaults: nil)
        store.save(snapshot(updatedAt: date(2026, 10, 9, 10, 30, in: madrid)))
        store.clear()
        XCTAssertNil(store.load())
    }

    // MARK: - Day value

    func testDayValueIsTheLocalDayInTheGivenZone() {
        let late = date(2026, 10, 9, 23, 30, in: madrid)
        XCTAssertEqual(HomeStationWidgetSnapshot.dayValue(for: late, timeZone: madrid), 20261009)
        // the same instant is 21:30 on the 9th in UTC
        XCTAssertEqual(date(2026, 10, 9, 21, 30, in: utc), late)
        XCTAssertEqual(HomeStationWidgetSnapshot.dayValue(for: late, timeZone: utc), 20261009)
    }

    func testJustAfterMidnightInMadridIsTheNextDay() {
        let early = date(2026, 10, 10, 0, 30, in: madrid)
        XCTAssertEqual(HomeStationWidgetSnapshot.dayValue(for: early, timeZone: madrid), 20261010)
        // 00:30 on the 10th in Madrid is still the 9th in UTC
        XCTAssertEqual(HomeStationWidgetSnapshot.dayValue(for: early, timeZone: utc), 20261009)
    }

    // MARK: - Values

    func testExtremesPickMaxAndMinAfterFolding() {
        let extremes = HomeStationWidgetValues.extremes(in: dailyRows())
        XCTAssertEqual(extremes.max, "21.3 °C")
        XCTAssertEqual(extremes.min, "12.4 °C")
    }

    func testExtremesAreNilWhenRowsAreMissingOrEmpty() {
        let missing: [(key: String, value: String)] = [(key: "Temperatura mitjana", value: "16.8 °C")]
        XCTAssertNil(HomeStationWidgetValues.extremes(in: missing).max)
        XCTAssertNil(HomeStationWidgetValues.extremes(in: missing).min)

        let empty: [(key: String, value: String)] = [
            (key: "Temperatura màxima", value: ""),
            (key: "Temperatura mínima", value: "")
        ]
        XCTAssertNil(HomeStationWidgetValues.extremes(in: empty).max)
        XCTAssertNil(HomeStationWidgetValues.extremes(in: empty).min)
    }

    func testTemperatureAddsTheUnit() {
        XCTAssertEqual(HomeStationWidgetValues.temperature("18"), "18 °C")
        XCTAssertEqual(HomeStationWidgetValues.temperature("18 °C"), "18 °C")
        XCTAssertNil(HomeStationWidgetValues.temperature(" "))
        XCTAssertNil(HomeStationWidgetValues.temperature(nil))
    }

    // MARK: - Display

    func testFreshSnapshotShowsEverything() {
        let updated = date(2026, 10, 9, 10, 30, in: madrid)
        let value = snapshot(
            currentTemp: "18 °C", currentTempAt: updated.addingTimeInterval(-600),
            maxTemp: "21.3 °C", minTemp: "12.4 °C", extremesDay: 20261009, updatedAt: updated
        )
        let display = HomeStationWidgetDisplay(
            snapshot: value, now: updated.addingTimeInterval(60), timeZone: madrid
        )
        XCTAssertEqual(display.stationName, "Orís")
        XCTAssertEqual(display.currentTemp, "18 °C")
        XCTAssertEqual(display.maxTemp, "21.3 °C")
        XCTAssertEqual(display.minTemp, "12.4 °C")
        XCTAssertEqual(display.updatedTime, "10:30")
        XCTAssertFalse(display.isStale)
    }

    func testCurrentTemperatureOlderThanThreeHoursIsHidden() {
        let updated = date(2026, 10, 9, 10, 30, in: madrid)
        let now = updated.addingTimeInterval(60)
        let tooOld = snapshot(
            currentTemp: "18 °C", currentTempAt: now.addingTimeInterval(-TimeInterval(3 * 3600 + 1)),
            maxTemp: "21.3 °C", minTemp: "12.4 °C", extremesDay: 20261009, updatedAt: updated
        )
        let display = HomeStationWidgetDisplay(snapshot: tooOld, now: now, timeZone: madrid)
        XCTAssertEqual(display.currentTemp, HomeStationWidgetDisplay.placeholderValue)
        XCTAssertEqual(display.maxTemp, "21.3 °C")

        let justRecent = snapshot(
            currentTemp: "18 °C", currentTempAt: now.addingTimeInterval(-TimeInterval(3 * 3600 - 1)),
            maxTemp: "21.3 °C", minTemp: "12.4 °C", extremesDay: 20261009, updatedAt: updated
        )
        let recentDisplay = HomeStationWidgetDisplay(snapshot: justRecent, now: now, timeZone: madrid)
        XCTAssertEqual(recentDisplay.currentTemp, "18 °C")
    }

    func testExtremesFromAnotherDayAreHidden() {
        let updated = date(2026, 10, 9, 10, 30, in: madrid)
        let yesterday = snapshot(
            currentTemp: "18 °C", currentTempAt: updated,
            maxTemp: "21.3 °C", minTemp: "12.4 °C", extremesDay: 20261008, updatedAt: updated
        )
        let display = HomeStationWidgetDisplay(snapshot: yesterday, now: updated, timeZone: madrid)
        XCTAssertEqual(display.maxTemp, HomeStationWidgetDisplay.placeholderValue)
        XCTAssertEqual(display.minTemp, HomeStationWidgetDisplay.placeholderValue)
        XCTAssertEqual(display.currentTemp, "18 °C")
    }

    func testSnapshotOlderThanTwoHoursIsStale() {
        let updated = date(2026, 10, 9, 10, 30, in: madrid)
        let value = snapshot(currentTemp: "18 °C", currentTempAt: updated, updatedAt: updated)

        let twoHoursOld = HomeStationWidgetDisplay(
            snapshot: value, now: updated.addingTimeInterval(2 * 3600), timeZone: madrid
        )
        XCTAssertFalse(twoHoursOld.isStale)

        let justOver = HomeStationWidgetDisplay(
            snapshot: value, now: updated.addingTimeInterval(TimeInterval(2 * 3600 + 1)), timeZone: madrid
        )
        XCTAssertTrue(justOver.isStale)
    }

    func testUpdatedTimeIsShownInTheGivenTimeZone() {
        let updated = date(2026, 10, 9, 10, 30, in: madrid)
        let value = snapshot(updatedAt: updated)
        XCTAssertEqual(
            HomeStationWidgetDisplay(snapshot: value, now: updated, timeZone: madrid).updatedTime, "10:30"
        )
        XCTAssertEqual(
            HomeStationWidgetDisplay(snapshot: value, now: updated, timeZone: utc).updatedTime, "08:30"
        )
    }

    func testMissingValuesShowPlaceholders() {
        let now = date(2026, 10, 9, 10, 30, in: madrid)
        let display = HomeStationWidgetDisplay(snapshot: snapshot(updatedAt: now), now: now, timeZone: madrid)
        XCTAssertEqual(display.currentTemp, HomeStationWidgetDisplay.placeholderValue)
        XCTAssertEqual(display.maxTemp, HomeStationWidgetDisplay.placeholderValue)
        XCTAssertEqual(display.minTemp, HomeStationWidgetDisplay.placeholderValue)
        XCTAssertEqual(display.updatedTime, "10:30")
    }

    // MARK: - Updater

    func testDayLoadedForTodaySavesExtremesAndReloadsOnce() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let now = date(2026, 10, 9, 12, in: madrid)

        makeUpdater(counter).dayLoaded(
            stationName: "Orís", stationCode: "CC", rows: dailyRows(), date: now, now: now
        )

        let saved = store.load()
        XCTAssertEqual(saved?.stationName, "Orís")
        XCTAssertEqual(saved?.stationCode, "CC")
        XCTAssertEqual(saved?.maxTemp, "21.3 °C")
        XCTAssertEqual(saved?.minTemp, "12.4 °C")
        XCTAssertEqual(saved?.extremesDay, 20261009)
        XCTAssertEqual(saved?.updatedAt, now)
        XCTAssertEqual(counter.count, 1)
    }

    func testDayLoadedForAnotherDayIsIgnored() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let now = date(2026, 10, 9, 12, in: madrid)
        let yesterday = date(2026, 10, 8, 12, in: madrid)

        makeUpdater(counter).dayLoaded(
            stationName: "Orís", stationCode: "CC", rows: dailyRows(), date: yesterday, now: now
        )

        XCTAssertNil(store.load())
        XCTAssertEqual(counter.count, 0)
    }

    func testCurrentWeatherKeepsTheExtremesOfTheSameStation() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let widget = makeUpdater(counter)
        let now = date(2026, 10, 9, 12, in: madrid)
        let later = now.addingTimeInterval(600)

        widget.dayLoaded(stationName: "Orís", stationCode: "CC", rows: dailyRows(), date: now, now: now)
        widget.currentWeatherLoaded(stationName: "Orís", stationCode: "CC", rawTemp: "18", now: later)

        let saved = store.load()
        XCTAssertEqual(saved?.currentTemp, "18 °C")
        XCTAssertEqual(saved?.currentTempAt, later)
        XCTAssertEqual(saved?.maxTemp, "21.3 °C")
        XCTAssertEqual(saved?.minTemp, "12.4 °C")
        XCTAssertEqual(saved?.extremesDay, 20261009)
        XCTAssertEqual(counter.count, 2)
    }

    func testCurrentWeatherOfAnotherStationDropsTheOldValues() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let widget = makeUpdater(counter)
        let now = date(2026, 10, 9, 12, in: madrid)

        widget.dayLoaded(stationName: "Orís", stationCode: "CC", rows: dailyRows(), date: now, now: now)
        widget.currentWeatherLoaded(stationName: "Sant Cugat", stationCode: "XX", rawTemp: "18", now: now)

        let saved = store.load()
        XCTAssertEqual(saved?.stationCode, "XX")
        XCTAssertEqual(saved?.currentTemp, "18 °C")
        XCTAssertNil(saved?.maxTemp)
        XCTAssertNil(saved?.minTemp)
        XCTAssertNil(saved?.extremesDay)
    }

    func testSameHomeStationKeepsTheValues() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let widget = makeUpdater(counter)
        let now = date(2026, 10, 9, 12, in: madrid)

        widget.dayLoaded(stationName: "Orís", stationCode: "CC", rows: dailyRows(), date: now, now: now)
        widget.homeStationChanged(stationName: "Orís", stationCode: "CC", now: now.addingTimeInterval(60))

        let saved = store.load()
        XCTAssertEqual(saved?.stationCode, "CC")
        XCTAssertEqual(saved?.maxTemp, "21.3 °C")
        XCTAssertEqual(saved?.minTemp, "12.4 °C")
        XCTAssertEqual(saved?.extremesDay, 20261009)
    }

    func testAnotherHomeStationEmptiesTheValues() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let widget = makeUpdater(counter)
        let now = date(2026, 10, 9, 12, in: madrid)

        widget.dayLoaded(stationName: "Orís", stationCode: "CC", rows: dailyRows(), date: now, now: now)
        widget.currentWeatherLoaded(stationName: "Orís", stationCode: "CC", rawTemp: "18", now: now)
        widget.homeStationChanged(stationName: "Sant Cugat", stationCode: "XX", now: now)

        let saved = store.load()
        XCTAssertEqual(saved?.stationName, "Sant Cugat")
        XCTAssertEqual(saved?.stationCode, "XX")
        XCTAssertNil(saved?.currentTemp)
        XCTAssertNil(saved?.maxTemp)
        XCTAssertNil(saved?.minTemp)
        XCTAssertNil(saved?.extremesDay)
        XCTAssertEqual(counter.count, 3)
    }

    func testHomeStationChangedWithNothingStoredSavesAnEmptySnapshot() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let now = date(2026, 10, 9, 12, in: madrid)

        makeUpdater(counter).homeStationChanged(stationName: "Orís", stationCode: "CC", now: now)

        let saved = store.load()
        XCTAssertEqual(saved?.stationCode, "CC")
        XCTAssertEqual(saved?.stationName, "Orís")
        XCTAssertNil(saved?.maxTemp)
        XCTAssertNil(saved?.minTemp)
        XCTAssertEqual(saved?.updatedAt, now)
        XCTAssertEqual(counter.count, 1)
    }

    func testBlankTemperatureChangesNothing() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let widget = makeUpdater(counter)
        let now = date(2026, 10, 9, 12, in: madrid)

        widget.dayLoaded(stationName: "Orís", stationCode: "CC", rows: dailyRows(), date: now, now: now)
        let before = store.load()

        widget.currentWeatherLoaded(stationName: "Orís", stationCode: "CC", rawTemp: " ", now: now.addingTimeInterval(600))
        widget.currentWeatherLoaded(stationName: "Orís", stationCode: "CC", rawTemp: nil, now: now.addingTimeInterval(600))

        XCTAssertEqual(store.load(), before)
        XCTAssertEqual(counter.count, 1)
    }

    func testClearRemovesTheSnapshotAndReloads() {
        let counter = ReloadCounter()
        let store = HomeStationWidgetStore(defaults: defaults)
        let widget = makeUpdater(counter)
        let now = date(2026, 10, 9, 12, in: madrid)

        widget.dayLoaded(stationName: "Orís", stationCode: "CC", rows: dailyRows(), date: now, now: now)
        widget.clear()

        XCTAssertNil(store.load())
        XCTAssertEqual(counter.count, 2)
    }
}
