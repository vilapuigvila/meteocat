//
//  HomeStationWidgetUpdater.swift
//  meteocatalf
//

import Foundation
import WidgetKit

/// Keeps the home-station snapshot the widget reads up to date.
protocol HomeStationWidgetUpdating {
    /// Today's table for the home station. Ignored when `date` isn't today (the user browsed another day).
    func dayLoaded(stationName: String, stationCode: String, rows: [(key: String, value: String)], date: Date, now: Date)
    func currentWeatherLoaded(stationName: String, stationCode: String, rawTemp: String?, now: Date)
    /// The home station changed: values of the previous one must not be shown under the new name.
    /// Same station with another city code: the values are kept and only the city code changes.
    func homeStationChanged(stationName: String, stationCode: String, cityCode: String, now: Date)
    func clear()
}

struct HomeStationWidgetUpdater: HomeStationWidgetUpdating {
    let store: HomeStationWidgetStore
    /// Asks WidgetKit to read the snapshot again.
    let reload: () -> Void

    init(
        store: HomeStationWidgetStore = HomeStationWidgetStore(),
        reload: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.homeStationKind) }
    ) {
        self.store = store
        self.reload = reload
    }

    func dayLoaded(stationName: String, stationCode: String, rows: [(key: String, value: String)], date: Date, now: Date) {
        let today = HomeStationWidgetSnapshot.dayValue(for: now)
        guard HomeStationWidgetSnapshot.dayValue(for: date) == today else { return }

        let extremes = HomeStationWidgetValues.extremes(in: rows)
        var snapshot = base(stationName: stationName, stationCode: stationCode, now: now)
        snapshot.maxTemp = extremes.max
        snapshot.minTemp = extremes.min
        snapshot.extremesDay = today
        save(snapshot)
    }

    func currentWeatherLoaded(stationName: String, stationCode: String, rawTemp: String?, now: Date) {
        guard let temperature = HomeStationWidgetValues.temperature(rawTemp) else { return }

        var snapshot = base(stationName: stationName, stationCode: stationCode, now: now)
        snapshot.currentTemp = temperature
        snapshot.currentTempAt = now
        save(snapshot)
    }

    func homeStationChanged(stationName: String, stationCode: String, cityCode: String, now: Date) {
        // Nothing stored yet, or another station: start empty.
        guard let stored = store.load(), stored.stationCode == stationCode else {
            save(HomeStationWidgetSnapshot(stationName: stationName, stationCode: stationCode, cityCode: cityCode, updatedAt: now))
            return
        }
        // Same station: keep what is shown, only the city code can be new.
        guard stored.cityCode != cityCode else { return }
        var snapshot = stored
        snapshot.cityCode = cityCode
        save(snapshot)
    }

    func clear() {
        store.clear()
        reload()
    }

    // MARK: - Private -

    /// The stored snapshot when it belongs to this station, otherwise an empty one. Stamped with the name and `now`.
    private func base(stationName: String, stationCode: String, now: Date) -> HomeStationWidgetSnapshot {
        guard let stored = store.load(), stored.stationCode == stationCode else {
            return HomeStationWidgetSnapshot(stationName: stationName, stationCode: stationCode, updatedAt: now)
        }
        return HomeStationWidgetSnapshot(
            stationName: stationName,
            stationCode: stationCode,
            cityCode: stored.cityCode,
            currentTemp: stored.currentTemp,
            currentTempAt: stored.currentTempAt,
            maxTemp: stored.maxTemp,
            minTemp: stored.minTemp,
            extremesDay: stored.extremesDay,
            updatedAt: now
        )
    }

    private func save(_ snapshot: HomeStationWidgetSnapshot) {
        store.save(snapshot)
        reload()
    }
}
