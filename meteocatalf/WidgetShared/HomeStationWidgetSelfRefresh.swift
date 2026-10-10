//
//  HomeStationWidgetSelfRefresh.swift
//  meteocatalf
//

import Foundation

/// What the widget does on each timeline reload: refreshes the snapshot from meteo.cat when it is old enough.
struct HomeStationWidgetSelfRefresh {
    /// The app may have just written it: don't download again before this.
    static let minInterval: TimeInterval = 10 * 60

    let store: HomeStationWidgetStore
    let fetcher: HomeStationWidgetFetcher
    /// Saves without asking WidgetKit to reload: the widget must not reload its own timeline from `getTimeline`.
    let updater: HomeStationWidgetUpdater

    init(
        store: HomeStationWidgetStore = HomeStationWidgetStore(),
        fetcher: HomeStationWidgetFetcher = HomeStationWidgetFetcher()
    ) {
        self.store = store
        self.fetcher = fetcher
        self.updater = HomeStationWidgetUpdater(store: store, reload: {})
    }

    /// Does nothing when there is no snapshot, no city code, or the snapshot is younger than `minInterval`.
    /// A failed page leaves its values as they are, so the next reload tries again.
    func refreshIfNeeded(now: Date) async {
        guard let snapshot = store.load(),
              let cityCode = snapshot.cityCode, !cityCode.isEmpty,
              now.timeIntervalSince(snapshot.updatedAt) >= Self.minInterval
        else { return }

        let result = await fetcher.fetch(stationCode: snapshot.stationCode, cityCode: cityCode, now: now)

        // The app may have switched station while the pages loaded: its snapshot wins.
        guard let latest = store.load(), latest.stationCode == snapshot.stationCode else { return }

        if let rows = result.rows {
            updater.dayLoaded(
                stationName: latest.stationName,
                stationCode: latest.stationCode,
                rows: rows,
                date: now,
                now: now
            )
        }
        if let rawTemp = result.rawTemp {
            updater.currentWeatherLoaded(
                stationName: latest.stationName,
                stationCode: latest.stationCode,
                rawTemp: rawTemp,
                now: now
            )
        }
    }
}
