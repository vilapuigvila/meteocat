//
//  StationMonth.swift
//  meteocatalf
//
//  Date keys, cache rules and the month maths behind the "Mitjana (mes)" and "Acumulada (mes)" tiles.
//  Pure logic: no network, no database, no UI.
//

import Foundation

// MARK: - DayKey -

/// A calendar day (Gregorian, device time zone) as the user sees it.
///
/// meteo.cat summarises *UTC* days and ignores the time part of `dia`, so the app asks for the UTC day
/// with the same year-month-day. That makes a `DayKey` both the day shown in the app and the key of the
/// daily summary on the server. The two only disagree for the first hours of a local day, when the UTC
/// day hasn't started yet (see `hasStarted`).
struct DayKey: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Always read through the Gregorian calendar: the user's calendar may be Buddhist, Japanese…
    init(_ date: Date, timeZone: TimeZone = .current) {
        let c = Self.gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    /// From the persisted `value`.
    init(value: Int) {
        self.init(year: value / 10_000, month: value / 100 % 100, day: value % 100)
    }

    /// yyyymmdd, the form stored in `Model.InfoStationByDate.dayKey`.
    var value: Int { year * 10_000 + month * 100 + day }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.value < rhs.value }

    /// The `dia` query parameter. Built by hand: a `DateFormatter` follows the user's calendar and digits
    /// (`0008-10-04` in a Japanese calendar, Arabic digits in `ar`) and isn't safe to share between tasks.
    var requestParameter: String {
        String(format: "%04d-%02d-%02dT12:00Z", year, month, day)
    }

    // MARK: UTC day

    var utcStart: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantFuture
    }
    var utcEnd: Date { utcStart.addingTimeInterval(24 * 3600) }

    /// `false` for the first hours of a local day: the server has no page for the UTC day yet.
    func hasStarted(at now: Date) -> Bool { now >= utcStart }

    // MARK: Cache rules

    /// The last half-hour of a day can show up on the server a bit after midnight UTC.
    static let settleDelay: TimeInterval = 3600
    /// How long a day that can still change is served from the cache.
    static let refreshInterval: TimeInterval = 3600

    /// `true` when the values were downloaded after the day ended and settled, so they can't change anymore.
    func isComplete(fetchedAt: Date) -> Bool {
        fetchedAt >= utcEnd.addingTimeInterval(Self.settleDelay)
    }

    /// A complete day is never downloaded again. Any other is refreshed once it's `refreshInterval` old.
    func needsRefresh(fetchedAt: Date, now: Date) -> Bool {
        !isComplete(fetchedAt: fetchedAt) && now.timeIntervalSince(fetchedAt) >= Self.refreshInterval
    }

    /// How long Alfy may serve the downloaded page of this day. A day that can still change lives
    /// `refreshInterval`, like its database row. A final day gets `now - (utcEnd + settleDelay)`: Alfy treats a page
    /// as fresh only while it's younger than that, so only a page downloaded after the day settled can be reused,
    /// and one downloaded earlier (a partial day) is fetched again.
    ///
    /// The first hour of a day is the exception: meteo.cat can answer it with a page that has no table yet, and
    /// Alfy caches that like any other 200, so the "no data yet" state would outlive the data by up to an hour.
    func cacheTTL(now: Date) -> TimeInterval {
        let settledAt = utcEnd.addingTimeInterval(Self.settleDelay)
        if now >= settledAt {
            return now.timeIntervalSince(settledAt)
        }
        if now < utcStart.addingTimeInterval(Self.emptyPageWindow) {
            return Self.emptyPageTTL
        }
        return Self.refreshInterval
    }

    /// How long into a day meteo.cat may still answer with an empty page, and how long that page may be cached.
    /// 5 minutes is the `max-age` the server itself sends.
    static let emptyPageWindow: TimeInterval = 3600
    static let emptyPageTTL: TimeInterval = 300

    // MARK: Helpers

    /// Local noon, a stable moment inside the day for display and for requests.
    func localNoon(timeZone: TimeZone = .current) -> Date {
        Self.gregorian(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    /// Every day from the 1st of `reference`'s month up to `reference`'s day, inclusive.
    static func monthToDate(_ reference: Date, timeZone: TimeZone = .current) -> [DayKey] {
        let today = DayKey(reference, timeZone: timeZone)
        guard today.day >= 1 else { return [] }
        return (1...today.day).map { DayKey(year: today.year, month: today.month, day: $0) }
    }

    private static let utc: Calendar = gregorian(TimeZone(identifier: "UTC") ?? .gmt)

    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

// MARK: - Month values -

struct StationDayInfo: Hashable, Sendable {
    let day: DayKey
    let info: [DTO.HomeStation]
    /// The day had ended on the server when these values were downloaded, so they are final.
    let isComplete: Bool
}

struct StationDayInfoSummary: Equatable, Sendable {
    /// Mean of the daily means. Complete days only: the daily mean of a day in progress
    /// is biased by the hour it was downloaded (a morning mean is mostly night readings).
    let averageTemp: Double?
    /// Month-to-date rain, including the day in progress.
    let accumulatedRain: Double?
    /// Days with values, among the days that have started on the server.
    let daysWithData: Int
    let daysExpected: Int

    var missingDays: Int { max(0, daysExpected - daysWithData) }

    static let empty = StationDayInfoSummary(averageTemp: nil, accumulatedRain: nil, daysWithData: 0, daysExpected: 0)

    /// One decimal and a `.`, like the values meteo.cat sends, whatever the user's locale.
    var averageTempText: String { averageTemp.map { String(format: "%.1f °C", $0) } ?? "--" }
    var accumulatedRainText: String { accumulatedRain.map { String(format: "%.1f mm", $0) } ?? "--" }
}

enum StationValue {
    static let averageTempKey = "temperatura mitjana"
    static let accumulatedRainKey = "precipitacio acumulada"

    static func normalize(_ string: String) -> String {
        string.folding(options: .diacriticInsensitive, locale: nil).lowercased()
    }

    /// First number in `string`: `"17.0 °C"` → 17, `"1,4 mm"` → 1.4, `"-3.2 °C"` → -3.2, `"--"` → nil.
    static func number(from string: String) -> Double? {
        guard let range = string.range(of: #"-?\d+(?:[.,]\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(string[range].replacingOccurrences(of: ",", with: "."))
    }

    /// The text of the first row whose title contains `keyFragment`, ignoring case and accents.
    static func text(forKeyContaining keyFragment: String, in items: [DTO.HomeStation]) -> String? {
        let fragment = normalize(keyFragment)
        return items.first { normalize($0.key).contains(fragment) }?.value
    }

    fileprivate static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10 + 0 // `+ 0` turns -0.0 into 0.0
    }
}

extension Array where Element == StationDayInfo {

    func summary(referenceDate: Date = Date(), now: Date = Date(), timeZone: TimeZone = .current) -> StationDayInfoSummary {
        let daysExpected = DayKey.monthToDate(referenceDate, timeZone: timeZone).filter { $0.hasStarted(at: now) }.count

        let temps = filter(\.isComplete).compactMap { dayInfo in
            StationValue.text(forKeyContaining: StationValue.averageTempKey, in: dayInfo.info)
                .flatMap(StationValue.number(from:))
        }
        let rains = compactMap { dayInfo in
            StationValue.text(forKeyContaining: StationValue.accumulatedRainKey, in: dayInfo.info)
                .flatMap(StationValue.number(from:))
        }
        return StationDayInfoSummary(
            averageTemp: temps.isEmpty ? nil : StationValue.rounded(temps.reduce(0, +) / Double(temps.count)),
            accumulatedRain: rains.isEmpty ? nil : StationValue.rounded(rains.reduce(0, +)),
            daysWithData: count,
            daysExpected: daysExpected
        )
    }

    /// One entry per day of the month so far, in order. Days without values show `--`.
    func monthDayValues(referenceDate: Date = Date(), timeZone: TimeZone = .current) -> [HomeStation.Representable.MonthDayValue] {
        let byDay = Dictionary(map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        return DayKey.monthToDate(referenceDate, timeZone: timeZone).map { key in
            let entry = byDay[key]
            return HomeStation.Representable.MonthDayValue(
                date: key.localNoon(timeZone: timeZone),
                averageTemp: entry.flatMap {
                    StationValue.text(forKeyContaining: StationValue.averageTempKey, in: $0.info)
                } ?? "--",
                accumulatedRain: entry.flatMap {
                    StationValue.text(forKeyContaining: StationValue.accumulatedRainKey, in: $0.info)
                } ?? "--",
                isPartial: entry.map { !$0.isComplete } ?? false
            )
        }
    }
}
