//
//  Stationworker.swift
//  meteocatalf
//
//  Created by albert vila on 18/1/26.
//

import Foundation
import Alfy

/// Day values already in the database, and when they were downloaded.
struct CachedStationDay: Sendable {
    let info: [DTO.HomeStation]
    let fetchedAt: Date
}

struct StationWorker {

    enum ErrorReason: Error, Equatable {
        /// meteo.cat has no daily summary for that day: the UTC day hasn't started yet, or the station sent nothing.
        case noData
    }

    /// Requests running at once for one station's month.
    static let maxConcurrentMonthRequests = 4

    /// Network
    ///
    /// Several screens ask for the same day at launch (Home tab, favourites prefetch); the second caller joins the
    /// request in flight instead of downloading the page again.
    static func requestInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        date: Date,
        store: Bool
    ) async throws -> [DTO.HomeStation] {
        let day = DayKey(date)
        guard day.hasStarted(at: Date()) else {
            throw ErrorReason.noData
        }
        return try await inFlight.value(for: "\(code)|\(day.value)|\(store)") {
            let dto: [DTO.HomeStation]
            do {
                dto = try await ServerData.requestStation(code: code, date: date)
            } catch ServerData.ResponseError.noDailyData {
                throw ErrorReason.noData
            }
            if store {
                await insertInfoDay(database, dto: dto, code: code, day: day)
            }
            return dto
        }
    }

    /// Database. `nil` when there is nothing stored for that day, or it is due a refresh (see `DayKey.needsRefresh`).
    @MainActor static func fetchInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        date: Date,
        now: Date = Date()
    ) -> [DTO.HomeStation]? {
        let day = DayKey(date)
        guard let cached = cachedDays(database, code: code, from: day, to: day)[day],
              !day.needsRefresh(fetchedAt: cached.fetchedAt, now: now)
        else {
            return nil
        }
        return cached.info
    }

    /// Every stored day of `referenceDate`'s month, whatever its age. No network: for showing something right away.
    @MainActor static func cachedMonthInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        referenceDate: Date = Date()
    ) -> [StationDayInfo] {
        let days = DayKey.monthToDate(referenceDate)
        guard let first = days.first, let last = days.last else { return [] }
        return cachedDays(database, code: code, from: first, to: last)
            .map { day, cached in
                StationDayInfo(day: day, info: cached.info, isComplete: day.isComplete(fetchedAt: cached.fetchedAt))
            }
            .sorted { $0.day < $1.day }
    }

    /// All entries from the first day of the month up to today, oldest first. Days the server can't serve yet are
    /// left out. A day that can't be refreshed (offline) keeps its stored values, flagged as not complete.
    static func fetchMonthInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        referenceDate: Date = Date()
    ) async -> [StationDayInfo] {
        let now = Date()
        let days = DayKey.monthToDate(referenceDate).filter { $0.hasStarted(at: now) }
        guard let first = days.first, let last = days.last else { return [] }

        let cached = await cachedDays(database, code: code, from: first, to: last)

        var result: [StationDayInfo] = []
        result.reserveCapacity(days.count)
        var missing: [DayKey] = []
        for day in days {
            if let stored = cached[day], !day.needsRefresh(fetchedAt: stored.fetchedAt, now: now) {
                result.append(StationDayInfo(day: day, info: stored.info, isComplete: day.isComplete(fetchedAt: stored.fetchedAt)))
            } else {
                missing.append(day)
            }
        }

        // Newest first: it's the one that changes. A cancelled run leaves only old days for next time.
        var pending = Array(missing.reversed())[...]
        let fetched: [StationDayInfo] = await withTaskGroup(of: StationDayInfo?.self) { group in
            func addNext(to group: inout TaskGroup<StationDayInfo?>) {
                guard !Task.isCancelled, let day = pending.popFirst() else { return }
                let stale = cached[day]
                group.addTask {
                    await refreshedDay(database, code: code, day: day, stale: stale)
                }
            }
            for _ in 0..<maxConcurrentMonthRequests {
                addNext(to: &group)
            }
            var fetched: [StationDayInfo] = []
            for await dayInfo in group {
                if let dayInfo {
                    fetched.append(dayInfo)
                }
                addNext(to: &group)
            }
            return fetched
        }

        return (result + fetched).sorted { $0.day < $1.day }
    }

    @MainActor static func isFavorite(_ database: DatabaseManagerProtocol, code: String) -> Bool {
        station(database, code: code)?.isFavorite ?? false
    }

    /// Rows stored before `dayKey` existed can't be trusted (their `createdAt` is the requested day, not the
    /// download time), so they are dropped once. They are only a cache.
    @MainActor static func purgeLegacyCache(_ database: DatabaseManagerProtocol) {
        do {
            let legacy = try database.fetchItems(
                Model.InfoStationByDate.self,
                predicate: #Predicate<Model.InfoStationByDate> { $0.dayKey == 0 },
                sortBy: nil
            )
            try database.remove(legacy)
        } catch {
            nonFatalCrashlytics(false, error.localizedDescription)
        }
    }

    // MARK: - Private -

    private static let inFlight = InFlightRequests()

    private static func refreshedDay(
        _ database: DatabaseManagerProtocol,
        code: String,
        day: DayKey,
        stale: CachedStationDay?
    ) async -> StationDayInfo? {
        do {
            let dto = try await requestInfoStation(database, code: code, date: day.localNoon(), store: true)
            return StationDayInfo(day: day, info: dto, isComplete: day.isComplete(fetchedAt: Date()))
        } catch {
            guard let stale else { return nil }
            return StationDayInfo(day: day, info: stale.info, isComplete: day.isComplete(fetchedAt: stale.fetchedAt))
        }
    }
}

// MARK: - Database -

extension StationWorker {

    /// The newest stored row of each day in `from...to`.
    @MainActor
    fileprivate static func cachedDays(
        _ database: DatabaseManagerProtocol,
        code: String,
        from: DayKey,
        to: DayKey
    ) -> [DayKey: CachedStationDay] {
        let lowerBound = from.value
        let upperBound = to.value
        let predicate = #Predicate<Model.InfoStationByDate> { info in
            info.station?.code == code && info.dayKey >= lowerBound && info.dayKey <= upperBound
        }
        do {
            let rows = try database.fetchItems(Model.InfoStationByDate.self, predicate: predicate, sortBy: nil)
            var result: [DayKey: CachedStationDay] = [:]
            for row in rows {
                let day = DayKey(value: row.dayKey)
                let fetchedAt = Date(timeIntervalSince1970: row.createdAt)
                if let existing = result[day], existing.fetchedAt >= fetchedAt {
                    continue
                }
                let isFavorite = row.station?.isFavorite ?? false
                result[day] = CachedStationDay(
                    info: row.values.map {
                        DTO.HomeStation(name: $0.name, key: $0.key, value: $0.value, time: $0.time, isFavorite: isFavorite)
                    },
                    fetchedAt: fetchedAt
                )
            }
            return result
        } catch {
            nonFatalCrashlytics(false, error.localizedDescription)
            return [:]
        }
    }

    @MainActor
    fileprivate static func station(_ database: DatabaseManagerProtocol, code: String) -> Model.Station? {
        let stations = try? database.fetchItems(
            Model.Station.self,
            predicate: #Predicate<Model.Station> { $0.code == code },
            sortBy: nil
        )
        return stations?.first
    }

    /// Replaces whatever is stored for that station and day: one row each, stamped with the download time.
    @MainActor
    static func insertInfoDay(
        _ database: DatabaseManagerProtocol,
        dto: [DTO.HomeStation],
        code: String,
        day: DayKey
    ) {
        guard let station = station(database, code: code) else {
            nonFatalCrashlytics(false, "should not happen")
            return
        }
        let dayValue = day.value
        do {
            let previous = try database.fetchItems(
                Model.InfoStationByDate.self,
                predicate: #Predicate<Model.InfoStationByDate> { info in
                    info.station?.code == code && info.dayKey == dayValue
                },
                sortBy: nil
            )
            try database.remove(previous)
            try database.insert(
                Model.InfoStationByDate(
                    values: dto.map {
                        Model.InfoStationByDate.Day(name: $0.name, key: $0.key, value: $0.value, time: $0.time)
                    },
                    createdAt: Date().timeIntervalSince1970,
                    dayKey: day.value,
                    station: station
                )
            )
        } catch {
            nonFatalCrashlytics(false, error.localizedDescription)
        }
    }
}

// MARK: - In flight requests -

/// Lets callers asking for the same page at the same time share one download. The download itself is not tied to
/// any caller, so a cancelled screen doesn't throw away a response that is useful for the next one.
private actor InFlightRequests {
    private var tasks: [String: Task<[DTO.HomeStation], Error>] = [:]

    func value(
        for key: String,
        _ work: @escaping @Sendable () async throws -> [DTO.HomeStation]
    ) async throws -> [DTO.HomeStation] {
        if let running = tasks[key] {
            return try await running.value
        }
        let task = Task { try await work() }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}
