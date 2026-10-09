//
//  HomeStationWidgetRefresher.swift
//  meteocatalf
//

import Foundation

/// Feeds the home-station widget from the app's own data.
@MainActor
protocol HomeStationWidgetRefreshing {
    func refresh() async
}

/// Loads today's table and the current weather of the home station the way My Station does, and hands them to the
/// updater. Both come from caches with a TTL, so it is cheap to run on every activation.
@MainActor
struct HomeStationWidgetRefresher: HomeStationWidgetRefreshing {
    let databaseManager: DatabaseManagerProtocol
    let updater: HomeStationWidgetUpdating

    func refresh() async {
        guard let home = UserSettings.homeStation else {
            updater.clear()
            return
        }
        let now = Date()
        updater.homeStationChanged(stationName: home.name, stationCode: home.code, now: now)

        // A day that can't be loaded yet (first hours after midnight) or a failed request leaves the snapshot as it is.
        if let rows = try? await todayRows(code: home.code, date: now) {
            updater.dayLoaded(stationName: home.name, stationCode: home.code, rows: rows, date: now, now: now)
        }
        if let weather: DTO.CurrentWeather = try? await ServerData.request(.curentWeather(code: home.codeCity)) {
            updater.currentWeatherLoaded(
                stationName: home.name,
                stationCode: home.code,
                rawTemp: weather.now.currentTemp,
                now: Date()
            )
        }
    }

    /// Stored values when still valid, the network otherwise: the same rule as `HomeStationInteractorImpl.loadDay`.
    private func todayRows(code: String, date: Date) async throws -> [(key: String, value: String)] {
        let dto: [DTO.HomeStation]
        if let stored = StationWorker.fetchInfoStation(databaseManager, code: code, date: date) {
            dto = stored
        } else {
            dto = try await StationWorker.requestInfoStation(databaseManager, code: code, date: date, store: true)
        }
        return dto.map { (key: $0.key, value: $0.value) }
    }
}
