//
//  HomeStationWidgetFetcher.swift
//  meteocatalf
//

import Foundation
import SwiftSoup

/// Downloads and reads the two meteo.cat pages the widget needs. Same pages and selectors as `ServerData`.
struct HomeStationWidgetFetcher: Sendable {
    typealias Load = @Sendable (URL) async throws -> Data

    struct Result: Sendable {
        /// Rows of today's daily table; nil when it couldn't be loaded or read.
        let rows: [(key: String, value: String)]?
        /// "18", as the page has it; nil when missing.
        let rawTemp: String?
    }

    static let timeout: TimeInterval = 10

    let load: Load

    init(load: @escaping Load = HomeStationWidgetFetcher.urlSessionLoad) {
        self.load = load
    }

    /// Both pages at once; a failure of one leaves its field nil and never throws.
    func fetch(stationCode: String, cityCode: String, now: Date, timeZone: TimeZone = .current) async -> Result {
        async let daily = loadHTML(Self.dailyURL(stationCode: stationCode, date: now, timeZone: timeZone))
        async let current = loadHTML(Self.currentWeatherURL(cityCode: cityCode))
        let dailyHTML = await daily
        let currentHTML = await current
        return Result(
            rows: dailyHTML.flatMap { Self.parseDailyRows(html: $0) },
            rawTemp: currentHTML.flatMap { Self.parseCurrentTemp(html: $0) }
        )
    }

    /// https://m.meteo.cat/?codi=<cityCode>
    static func currentWeatherURL(cityCode: String) -> URL? {
        URL(string: "https://m.meteo.cat/?codi=\(cityCode)")
    }

    /// https://www.meteo.cat/observacions/xema/dades?codi=<code>&dia=yyyy-MM-ddT12:00Z, the day of `date` in `timeZone`.
    static func dailyURL(stationCode: String, date: Date, timeZone: TimeZone = .current) -> URL? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(
            format: "%04d-%02d-%02dT12:00Z",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return URL(string: "https://www.meteo.cat/observacions/xema/dades?codi=\(stationCode)&dia=\(day)")
    }

    /// First non-empty text node directly inside `div.temp`, as `ServerData.getCurrentWeather` reads it. nil when missing.
    static func parseCurrentTemp(html: String) -> String? {
        guard let document = try? SwiftSoup.parse(html),
              let tempDiv = try? document.select("div.temp").first()
        else { return nil }
        return tempDiv.getChildNodes()
            .compactMap { $0 as? TextNode }
            .map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    /// Rows of the daily table, as `ServerData.parseDailySummary` reads them. nil when the page has no table or its
    /// caption says it is the station metadata one.
    static func parseDailyRows(html: String) -> [(key: String, value: String)]? {
        guard let document = try? SwiftSoup.parse(html),
              let table = try? document.select("table").first(),
              let caption = try? table.select("caption").text(),
              !caption.localizedCaseInsensitiveContains("metadades"),
              let rowElements = try? table.select("tr")
        else { return nil }

        var rows: [(key: String, value: String)] = []
        for row in rowElements {
            guard let cells = try? row.select("th, td") else { continue }
            if cells.size() == 2 || cells.size() == 3,
               let key = try? cells.get(0).text(),
               let value = try? cells.get(1).text() {
                rows.append((key: key, value: value))
            }
        }
        return rows
    }

    /// Ephemeral session with a timeout; throws on anything but a 200.
    static let urlSessionLoad: Load = { url in
        let (data, response) = try await HomeStationWidgetFetcher.session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Private -

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = HomeStationWidgetFetcher.timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// nil for a URL that couldn't be built; nil text when the request or the decoding fails.
    private func loadHTML(_ url: URL?) async -> String? {
        guard let url, let data = try? await load(url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
