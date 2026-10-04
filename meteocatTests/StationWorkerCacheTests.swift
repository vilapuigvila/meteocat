import XCTest
import SwiftData
import Alfy
@testable import meteocat

/// A throwaway in-memory database with the app's schema.
@MainActor
private final class InMemoryDatabase: DatabaseManagerProtocol {
    let context: ModelContext
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: Schema([Model.Station.self, Model.InfoStationByDate.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
    }

    func insert<T: PersistentModel>(_ item: T) throws -> T {
        context.insert(item)
        try context.save()
        return item
    }
    func insert<T: PersistentModel>(_ sequenceOf: [T]) throws {
        sequenceOf.forEach { context.insert($0) }
        try context.save()
    }
    func fetchItems<T: PersistentModel>(_ item: T.Type, predicate: Predicate<T>?, sortBy: [SortDescriptor<T>]?) throws -> [T] {
        try context.fetch(FetchDescriptor<T>(predicate: predicate, sortBy: sortBy ?? []))
    }
    func removeItem<T: PersistentModel>(_ item: T) throws {
        context.delete(item)
        try context.save()
    }
    func remove<T: PersistentModel>(_ items: [T]) throws {
        items.forEach { context.delete($0) }
        try context.save()
    }
    func deleteAll<T: PersistentModel>(_ item: T.Type) throws {
        try context.fetch(FetchDescriptor<T>()).forEach { context.delete($0) }
        try context.save()
    }
    func save() throws { try context.save() }
}

@MainActor
final class StationWorkerCacheTests: XCTestCase {

    private var database: InMemoryDatabase!
    private var station: Model.Station!
    private let code = "CC"

    override func setUp() async throws {
        database = try InMemoryDatabase()
        station = try database.insert(Model.Station(code: code, codeCity: "1", name: "Orís", type: "A", lastUpdated: 0))
    }

    private func values(temp: String = "17.0 °C", rain: String = "1.4 mm") -> [Model.InfoStationByDate.Day] {
        [.init(name: "Orís", key: "Temperatura mitjana", value: temp, time: nil),
         .init(name: "Orís", key: "Precipitació acumulada", value: rain, time: nil)]
    }

    @discardableResult
    private func store(_ day: DayKey, fetchedAt: Date, temp: String = "17.0 °C") throws -> Model.InfoStationByDate {
        try database.insert(
            Model.InfoStationByDate(
                values: values(temp: temp),
                createdAt: fetchedAt.timeIntervalSince1970,
                dayKey: day.value,
                station: station
            )
        )
    }

    private func utc(_ day: DayKey, hour: Int) -> Date { day.utcStart.addingTimeInterval(Double(hour) * 3600) }

    // MARK: - Freshness

    func testDayInProgressIsServedFromTheDatabaseForAnHourOnly() throws {
        let day = DayKey(year: 2026, month: 10, day: 4)
        let fetched = utc(day, hour: 9)
        try store(day, fetchedAt: fetched)

        XCTAssertNotNil(StationWorker.fetchInfoStation(database, code: code, date: day.localNoon(), now: fetched.addingTimeInterval(1800)))
        XCTAssertNil(StationWorker.fetchInfoStation(database, code: code, date: day.localNoon(), now: fetched.addingTimeInterval(3600)))
    }

    /// The bug: today, downloaded at 09:00, was still served the next day.
    func testDayDownloadedWhileInProgressIsAskedAgainOnceItIsOver() throws {
        let day = DayKey(year: 2026, month: 10, day: 2)
        try store(day, fetchedAt: utc(day, hour: 9))

        let nextMorning = utc(day, hour: 33)
        XCTAssertNil(StationWorker.fetchInfoStation(database, code: code, date: day.localNoon(), now: nextMorning))
    }

    func testCompleteDayIsServedForEver() throws {
        let day = DayKey(year: 2026, month: 10, day: 2)
        try store(day, fetchedAt: utc(day, hour: 26))

        XCTAssertNotNil(StationWorker.fetchInfoStation(database, code: code, date: day.localNoon(), now: utc(day, hour: 24 * 90)))
    }

    func testNothingStoredForOtherStationsOrDays() throws {
        let day = DayKey(year: 2026, month: 10, day: 2)
        try store(day, fetchedAt: utc(day, hour: 26))

        XCTAssertNil(StationWorker.fetchInfoStation(database, code: "XX", date: day.localNoon(), now: utc(day, hour: 27)))
        let other = DayKey(year: 2026, month: 10, day: 3)
        XCTAssertNil(StationWorker.fetchInfoStation(database, code: code, date: other.localNoon(), now: utc(day, hour: 27)))
    }

    // MARK: - One row per day

    func testStoringADayReplacesThePreviousRow() throws {
        let day = DayKey(year: 2026, month: 10, day: 4)
        try store(day, fetchedAt: utc(day, hour: 9), temp: "10.0 °C")

        StationWorker.insertInfoDay(
            database,
            dto: [.init(name: "Orís", key: "Temperatura mitjana", value: "12.0 °C", time: nil)],
            code: code,
            day: day
        )

        let rows = try database.fetchItems(Model.InfoStationByDate.self, predicate: nil, sortBy: nil)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.values.first?.value, "12.0 °C")
        XCTAssertEqual(rows.first?.dayKey, day.value)
        // stamped with the download time, not with the requested day
        XCTAssertEqual(rows.first!.createdAt, Date().timeIntervalSince1970, accuracy: 60)
    }

    func testStoringADayKeepsTheOtherDays() throws {
        let first = DayKey(year: 2026, month: 10, day: 3)
        let second = DayKey(year: 2026, month: 10, day: 4)
        try store(first, fetchedAt: utc(first, hour: 30))

        StationWorker.insertInfoDay(database, dto: [.init(name: "Orís", key: "k", value: "1", time: nil)], code: code, day: second)

        XCTAssertEqual(try database.fetchItems(Model.InfoStationByDate.self, predicate: nil, sortBy: nil).count, 2)
    }

    func testWhenSeveralRowsExistTheNewestWins() throws {
        let day = DayKey(year: 2026, month: 10, day: 4)
        try store(day, fetchedAt: utc(day, hour: 9), temp: "old")
        try store(day, fetchedAt: utc(day, hour: 10), temp: "new")

        let stored = StationWorker.fetchInfoStation(database, code: code, date: day.localNoon(), now: utc(day, hour: 10).addingTimeInterval(60))
        XCTAssertEqual(stored?.first(where: { $0.key == "Temperatura mitjana" })?.value, "new")
    }

    // MARK: - Legacy rows

    func testLegacyRowsAreIgnoredAndPurged() throws {
        let day = DayKey(year: 2026, month: 10, day: 4)
        _ = try database.insert(
            Model.InfoStationByDate(values: values(), createdAt: day.localNoon().timeIntervalSince1970, dayKey: 0, station: station)
        )
        try store(DayKey(year: 2026, month: 10, day: 2), fetchedAt: utc(DayKey(year: 2026, month: 10, day: 2), hour: 26))

        XCTAssertNil(StationWorker.fetchInfoStation(database, code: code, date: day.localNoon(), now: Date()))

        StationWorker.purgeLegacyCache(database)

        let rows = try database.fetchItems(Model.InfoStationByDate.self, predicate: nil, sortBy: nil)
        XCTAssertEqual(rows.map(\.dayKey), [20261002])
    }

    // MARK: - Month

    func testCachedMonthFlagsWhichDaysAreFinal() throws {
        let reference = DayKey(year: 2026, month: 10, day: 3).localNoon()
        let first = DayKey(year: 2026, month: 10, day: 1)
        let second = DayKey(year: 2026, month: 10, day: 2)
        let third = DayKey(year: 2026, month: 10, day: 3)
        try store(first, fetchedAt: utc(first, hour: 30))
        try store(second, fetchedAt: utc(second, hour: 10))   // downloaded during the day: not final
        try store(third, fetchedAt: utc(third, hour: 10))

        let month = StationWorker.cachedMonthInfoStation(database, code: code, referenceDate: reference)

        XCTAssertEqual(month.map(\.day), [first, second, third])
        XCTAssertEqual(month.map(\.isComplete), [true, false, false])
    }

    func testMonthWithEveryDayStoredAndFinalNeedsNoNetwork() async throws {
        // a month in the past, every day final: if anything were requested this would hit meteo.cat
        let days = (1...15).map { DayKey(year: 2026, month: 8, day: $0) }
        for day in days {
            try store(day, fetchedAt: utc(day, hour: 30), temp: "\(day.day).0 °C")
        }
        let reference = days.last!.localNoon()

        let month = await StationWorker.fetchMonthInfoStation(database, code: code, referenceDate: reference)

        XCTAssertEqual(month.map(\.day), days)
        XCTAssertTrue(month.allSatisfy(\.isComplete))
        let summary = month.summary(referenceDate: reference, now: utc(days.last!, hour: 48))
        XCTAssertEqual(summary.averageTemp, 8.0)
        XCTAssertEqual(summary.accumulatedRain, 21.0) // 15 days of 1.4 mm
        XCTAssertEqual(summary.missingDays, 0)
    }
}
