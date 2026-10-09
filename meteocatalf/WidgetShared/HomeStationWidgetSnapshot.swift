//
//  HomeStationWidgetSnapshot.swift
//  meteocatalf
//

import Foundation

/// What the home-station widget shows. Written by the app, read by the widget extension.
struct HomeStationWidgetSnapshot: Codable, Equatable, Sendable {
    let stationName: String
    let stationCode: String
    /// "18 °C", nil until a reading arrived.
    var currentTemp: String?
    var currentTempAt: Date?
    /// "21.3 °C"
    var maxTemp: String?
    var minTemp: String?
    /// Local day (yyyymmdd) `maxTemp`/`minTemp` belong to.
    var extremesDay: Int?
    var updatedAt: Date

    /// yyyymmdd of `date` in `timeZone`, through the Gregorian calendar.
    static func dayValue(for date: Date, timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }
}
