//
//  FavoritesWorker.swift
//  meteocat
//
//  Created by albert vila on 18/1/26.
//

import Foundation
import Alfy

struct FavoritesWorker: Sendable {

    @MainActor
    private static func fetchAFavsFromDB() -> [(String, String)] {
        struct Favs {
            let code: String
            let name: String
        }
        do {
            let favorites: [Model.Station] = try DatabaseManager.shared.fetchItems(
                Model.Station.self,
                predicate: #Predicate<Model.Station> { $0.isFavorite },
                sortBy: [SortDescriptor(\Model.Station.name, order: .forward)]
            )
            return favorites.map { ($0.code, $0.name) }
        } catch {
            assertionFailure()
            return []
        }
    }

    /*
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

        let pred = #Predicate<Model.InfoStationByDate> { info in
            info.station?.code == code
            && info.createdAt >= startOfDayTI && info.createdAt < endOfDayTI
        }
        do {
            let infos = try databaseManager.fetchItems(
                Model.InfoStationByDate.self,
                predicate: pred,
                sortBy: [SortDescriptor(\Model.InfoStationByDate.createdAt, order: .reverse)]
            )
            return infos.first
        } catch {
            nonFatalCrashlytics(false, error.localizedDescription)
            return nil
        }
    }*/
}
