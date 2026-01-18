//
//  Stationworker.swift
//  meteocat
//
//  Created by albert vila on 18/1/26.
//

import Foundation
import Alfy

struct StationDayInfo: Equatable {
    let date: TimeInterval
    let info: [DTO.HomeStation]
}

struct StationWorker {

    /// Network
    static func requestInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        date: Date,
        store: Bool
    ) async throws -> [DTO.HomeStation] {
        let dto: [DTO.HomeStation] = try await ServerData.requestStation(code: code, date: date)
        if store {
            await insertInfoDay(database, dto: dto, code: code, forDate: date)
        }
        return dto
    }
    
    /// Database
    @MainActor static func fetchInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        date: Date
    ) -> [DTO.HomeStation]? {
        guard let info = fetchInfoDayFromDatabase(database, code: code, date: date) else {
            return nil
        }
        let dto = info.values.map {
            DTO.HomeStation(
                name: $0.name,
                key: $0.key,
                value: $0.value,
                time: $0.time,
                isFavorite: info.station?.isFavorite ?? false
            )
        }
        print("avpv - fetch InfoDay from cache")
        return dto
    }
    
    /// all entries from first month date
    @MainActor static func fetchMonthInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        referenceDate: Date = Date()
    ) async -> [StationDayInfo] {
//        try? database.deleteAll(Model.InfoStationByDate.self)
        
        let requestDates = monthToDateDates(referenceDate: referenceDate)
        var result: [StationDayInfo] = []
        result.reserveCapacity(requestDates.count)

        var missingDates: [Date] = []
        missingDates.reserveCapacity(requestDates.count)

        for date in requestDates {
            if let info = fetchInfoStation(database, code: code, date: date) {
                result.append(.init(date: date.timeIntervalSince1970, info: info))
            } else {
                missingDates.append(date)
            }
        }
        if !missingDates.isEmpty {
            let fetched: [StationDayInfo] = await withTaskGroup(of: StationDayInfo?.self) { group in
                for date in missingDates {
                    group.addTask {
                        guard let info = try? await StationWorker.requestInfoStation(
                            database,
                            code: code,
                            date: date,
                            store: true
                        ) else {
                            return nil
                        }
                        return .init(date: date.timeIntervalSince1970, info: info)
                    }
                }

                var fetched: [StationDayInfo] = []
                fetched.reserveCapacity(missingDates.count)

                for await dayInfo in group {
                    if let dayInfo {
                        fetched.append(dayInfo)
                    }
                }
                return fetched
            }

            result.append(contentsOf: fetched)
            result.sort { $0.date < $1.date }
        }
        return result
    }
}

// MARK: - fetch all station entries from current month -

extension StationWorker {
    
    @MainActor
    private static func fetchInfoDayFromDatabase(
        _ databaseManager: DatabaseManagerProtocol,
        code: String,
        date: Date
    ) -> Model.InfoStationByDate? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let startOfDayTI = startOfDay.timeIntervalSince1970
        let endOfDayTI = endOfDay.timeIntervalSince1970
        let threshold = date.addingTimeInterval(-60*60).timeIntervalSince1970
        
        let pred = #Predicate<Model.InfoStationByDate> { info in
            info.station?.code == code
            && info.createdAt >= startOfDayTI && info.createdAt < endOfDayTI
            && info.createdAt > threshold
        }
        do {
            let infos = try databaseManager.fetchItems(Model.InfoStationByDate.self, predicate: pred, sortBy: nil)
            guard let info = infos.first else {
                print("avp - outdated less than 60 minutes. Should request new one")
                return nil
            }
            return info
        } catch {
            nonFatalCrashlytics(false, error.localizedDescription)
            return nil
        }
    }
    
    @MainActor
    private static func insertInfoDay(
        _ databaseManager: DatabaseManagerProtocol,
        dto: [DTO.HomeStation],
        code: String,
        forDate date: Date
    ) {
        let predicateStation = #Predicate<Model.Station> { $0.code == code }
        let stations = try? databaseManager.fetchItems(Model.Station.self, predicate: predicateStation, sortBy: nil)
        guard let station = stations?.first else {
            nonFatalCrashlytics(false, "should not happen")
            return
        }
        
        pruneInfoStationsUnlessTheMostRecent(databaseManager, stationCode: code, forDate: date)
        
        let createdAt = date.timeIntervalSince1970
        let info = Model.InfoStationByDate(
            values: dto.map {
                Model.InfoStationByDate.Day(name: $0.name, key: $0.key, value: $0.value, time: $0.time)
            },
            createdAt: createdAt,
            station: station
        )
        do {
            try databaseManager.insert(info)
        } catch {
            nonFatalCrashlytics(false, error.localizedDescription)
        }
    }
    
    @MainActor
    private static func pruneInfoStationsUnlessTheMostRecent(
        _ databaseManager: DatabaseManagerProtocol,
        stationCode: String,
        forDate date: Date
    ) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let startOfDayTI = startOfDay.timeIntervalSince1970
        let endOfDayTI = endOfDay.timeIntervalSince1970
//        let threshold = Date().addingTimeInterval(-20).timeIntervalSince1970
        
        // 3. Build the predicate to fetch InfoStationByDate records created today for that station.
        let predicate = #Predicate<Model.InfoStationByDate> { info in
            info.station?.code == stationCode
            && info.createdAt >= startOfDayTI && info.createdAt < endOfDayTI
//            && info.createdAt < threshold
        }
        
        do {
            let results = try databaseManager.fetchItems(Model.InfoStationByDate.self, predicate: predicate, sortBy: nil)
            let sortedResults = results.sorted { $0.createdAt > $1.createdAt }
            
            guard let mostRecent = sortedResults.first else {
                print("avp - No records for today found.")
                return
            }
            let recordsToDelete = sortedResults.filter { $0 !== mostRecent }
            try databaseManager.remove(recordsToDelete)
            print("avp Deleted \(recordsToDelete.count) record(s).")
        } catch {
            print("Error during fetch or delete: \(error)")
            nonFatalCrashlytics(false, error.localizedDescription)
        }
    }
    
    private static func monthToDateDates(referenceDate: Date) -> [Date] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return []
        }

        return (1...day).compactMap { dayOfMonth in
            calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))
        }
    }
}
