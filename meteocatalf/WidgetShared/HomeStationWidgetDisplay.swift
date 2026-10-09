//
//  HomeStationWidgetDisplay.swift
//  meteocatalf
//

import Foundation

/// What the widget renders, worked out from a snapshot at a given time. Pure, so it is unit tested.
struct HomeStationWidgetDisplay: Equatable, Sendable {
    static let placeholderValue = "--"
    /// Current temperature older than this is not shown.
    static let currentTempMaxAge: TimeInterval = 3 * 3600
    /// The whole widget looks faded after this.
    static let staleAfter: TimeInterval = 2 * 3600

    let stationName: String
    /// "--" when missing or older than `currentTempMaxAge`.
    let currentTemp: String
    /// "--" unless the extremes belong to today.
    let maxTemp: String
    let minTemp: String
    /// "HH:mm" of `updatedAt`.
    let updatedTime: String
    let isStale: Bool

    init(snapshot: HomeStationWidgetSnapshot, now: Date, timeZone: TimeZone = .current) {
        let today = HomeStationWidgetSnapshot.dayValue(for: now, timeZone: timeZone)
        let isCurrentFresh = snapshot.currentTempAt.map { now.timeIntervalSince($0) <= Self.currentTempMaxAge } ?? false
        let isExtremesToday = snapshot.extremesDay == today

        stationName = snapshot.stationName
        currentTemp = (isCurrentFresh ? snapshot.currentTemp : nil) ?? Self.placeholderValue
        maxTemp = (isExtremesToday ? snapshot.maxTemp : nil) ?? Self.placeholderValue
        minTemp = (isExtremesToday ? snapshot.minTemp : nil) ?? Self.placeholderValue
        updatedTime = Self.formattedTime(snapshot.updatedAt, timeZone: timeZone)
        isStale = now.timeIntervalSince(snapshot.updatedAt) > Self.staleAfter
    }

    init(stationName: String, currentTemp: String, maxTemp: String, minTemp: String, updatedTime: String, isStale: Bool) {
        self.stationName = stationName
        self.currentTemp = currentTemp
        self.maxTemp = maxTemp
        self.minTemp = minTemp
        self.updatedTime = updatedTime
        self.isStale = isStale
    }

    /// Sample for the widget gallery and placeholders.
    static let preview = HomeStationWidgetDisplay(
        stationName: "Barcelona - Zona Universitària",
        currentTemp: "18 °C",
        maxTemp: "21.3 °C",
        minTemp: "12.4 °C",
        updatedTime: "10:30",
        isStale: false
    )

    // MARK: - Private -

    /// A formatter per call: DateFormatter isn't meant to be shared between threads.
    private static func formattedTime(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
