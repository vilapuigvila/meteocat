//
//  ServerData.swift
//  meteocat
//
//  Created by albert vila on 31/10/24.
//

import Foundation
#if canImport(FoundationXML)
import FoundationXML // Necessary for XML parsing on certain platforms
#endif
import `SwiftSoup` // Add SwiftSoup for HTML parsing
import Alfy

// DOCU ****
// https://apidocs.meteocat.gencat.cat/section/referencia-tecnica/operacions/xema/
// DOCU ****

// max Temp  -> code 40
// min Temp  -> code 42
// last Temp -> code 32
// https://api.meteo.cat/xema/v1/variables/mesurades/40/ultimes\?codiEstacio\=CC

struct ServerData {
    enum Service {
        case lastTemperature(forStationCode: String)
        /// `forceRefresh` skips the cached list (pull-to-refresh) but still stores the response.
        case stations(forceRefresh: Bool)
        case requestStation(code: String, date: Date = Date())
        case curentWeather(code: String)
        /// When the newest radar image was taken, read from the radar page.
        case radarLatest
        /// When the newest Meteosat image was taken, read from the WMS capabilities of EUMETView.
        case satelliteLatest
    }
    static func request<D: Decodable>(_ service: Service) async throws -> D {
        let decodable: Decodable = try await {
            switch service {
            case .lastTemperature(let forStationCode):
                try await getLastTemperature(forStationCode: forStationCode)
            case .stations(let forceRefresh):
                await fetchStations(forceRefresh: forceRefresh)
            case .requestStation(let code, let date):
                try await requestStation(code: code, date: date)
            case .curentWeather(let code):
                try await getCurrentWeather(code: code)
            case .radarLatest:
                try await getRadarLatest()
            case .satelliteLatest:
                try await getSatelliteLatest()
            }
        }()
        return decodable as! D
    }
    
    /// How long Alfy's cache may answer each request, mirroring how long the app already keeps that data
    /// (see `makeRequest`). Shared with the code that owns the database rule, so they can't drift apart.
    enum CacheTTL {
        /// `StationsListInteractorImpl` reuses the stored station list for 15 days.
        static let stations: TimeInterval = 60 * 60 * 24 * 15
        /// `Forecast.MainView` asks again after 5 minutes.
        static let currentWeather: TimeInterval = 60 * 5
        /// XEMA readings are half-hourly. No caller yet, so no database rule to mirror.
        static let lastTemperature: TimeInterval = 60 * 30
        /// Radar images arrive every 6 minutes.
        static let radarLatest: TimeInterval = 60 * 3
        /// Meteosat adds an image every 10 minutes.
        static let satelliteLatest: TimeInterval = 60 * 3
    }

    private static let meteocatToken = "7r5zloC5zs2MjyxAfdnkd1cvuUeKpvWQ9cONyuPh"
    private static let xApiKey: Requester.HeaderParam =
        .custom(headerField: "x-api-key", value: meteocatToken)
    
    /// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
    // MARK: - Requests -
    /// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
    ///
    
    /// The request for `service`, with the cache policy that mirrors the app's own database times.
    ///
    /// meteo.cat lets clients cache its pages for only 3-5 minutes, and Alfy follows that unless told otherwise,
    /// so every policy here uses `.ignoreServer`: without it a `ttl` longer than the server's `max-age` does nothing.
    /// Pure (no network, no clock but `now`), so the policy is unit tested.
    static func makeRequest(for service: Service, now: Date = Date()) -> Requester.Request {
        switch service {
        case .requestStation(let code, let date):
            // A cached page must never make a day look finished when it isn't, so stale-on-error is off:
            // a partial page served after a network failure would be stored as a final day for ever.
            return Requester
                .makeRequest("https://www.meteo.cat/observacions/xema/dades?codi=\(code)&dia=\(DayKey(date).requestParameter)")
                .cacheControlBehavior(.ignoreServer)
                .ttl(DayKey(date).cacheTTL(now: now))
                .allowStaleOnError(false)
        case .stations(let forceRefresh):
            // An old station list beats none, so stale-on-error stays on.
            let request = Requester
                .makeRequest("https://www.meteo.cat/observacions/xema")
                .cacheControlBehavior(.ignoreServer)
                .ttl(CacheTTL.stations)
                .allowStaleOnError(true)
            return forceRefresh ? request.forceRefresh() : request
        case .curentWeather(let code):
            return Requester
                .makeRequest("https://m.meteo.cat/?codi=\(code)")
                .cacheControlBehavior(.ignoreServer)
                .ttl(CacheTTL.currentWeather)
                .allowStaleOnError(true)
        case .radarLatest:
            return Requester
                .makeRequest("https://www.meteo.cat/observacions/radar")
                .cacheControlBehavior(.ignoreServer)
                .ttl(CacheTTL.radarLatest)
                .allowStaleOnError(true)
        case .satelliteLatest:
            return Requester
                .makeRequest("https://view.eumetsat.int/geoserver/mtg_fd/wms?service=WMS&version=1.3.0&request=GetCapabilities")
                .cacheControlBehavior(.ignoreServer)
                .ttl(CacheTTL.satelliteLatest)
                .allowStaleOnError(true)
        case .lastTemperature(let stationCode):
            return Requester
                .makeRequest("https://api.meteo.cat/xema/v1/variables/mesurades/32/ultimes?codiEstacio=\(stationCode)")
                .header(xApiKey)
                .cacheControlBehavior(.ignoreServer)
                .ttl(CacheTTL.lastTemperature)
                .allowStaleOnError(true)
        }
    }

    private static func getRadarLatest() async throws -> Date {
        let data = try await makeRequest(for: .radarLatest)
            .send()
            .data
        guard let html = String(data: data, encoding: .utf8), let date = parseRadarTime(html: html) else {
            nonFatalCrashlytics(false, "radarTimeNotFound")
            throw Requester.ErrorReason.dataCorrupted
        }
        return date
    }

    /// The radar page carries the time of its newest image in a script: `dataDarreraRadar: '10/04/2026 18:06Z'`
    /// (month/day/year, UTC).
    static func parseRadarTime(html: String) -> Date? {
        let pattern = #"dataDarreraRadar:\s*'(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2})Z'"#
        guard let match = html.range(of: pattern, options: .regularExpression) else { return nil }
        let numbers = html[match].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 5 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(
            year: numbers[2], month: numbers[0], day: numbers[1], hour: numbers[3], minute: numbers[4]
        ))
    }

    private static func getSatelliteLatest() async throws -> Date {
        let data = try await makeRequest(for: .satelliteLatest)
            .send()
            .data
        guard let xml = String(data: data, encoding: .utf8), let date = parseSatelliteTime(capabilities: xml) else {
            nonFatalCrashlytics(false, "satelliteTimeNotFound")
            throw Requester.ErrorReason.dataCorrupted
        }
        return date
    }

    /// The `time` dimension of the GeoColour layer reads `start/end/PT10M`; the end is the newest image.
    static func parseSatelliteTime(capabilities: String) -> Date? {
        guard let layer = capabilities.range(of: "<Name>rgb_geocolour</Name>") else { return nil }
        let rest = capabilities[layer.upperBound...]
        let pattern = #"<Dimension[^>]*name="time"[^>]*>[^<]*/(\d{4}-\d{2}-\d{2}T[\d:.]+Z)/PT\d+M</Dimension>"#
        guard let dimension = rest.range(of: pattern, options: .regularExpression),
              let end = rest[dimension].range(of: #"\d{4}-\d{2}-\d{2}T[\d:.]+Z(?=/PT)"#, options: .regularExpression)
        else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: String(rest[dimension][end]))
            ?? ISO8601DateFormatter().date(from: String(rest[dimension][end]))
    }

    private static func getCurrentWeather(code: String) async throws -> DTO.CurrentWeather {
        let data = try await makeRequest(for: .curentWeather(code: code))
            .send()
            .data
        guard let html = String(data: data, encoding: .utf8) else {
            nonFatalCrashlytics(false, "dataCorrupted")
            throw Requester.ErrorReason.dataCorrupted
        }
        do {
            let doc = try SwiftSoup.parse(html)
            guard let tempDiv = try? doc.select("div.temp").first() else {
                throw Requester.ErrorReason.dataCorrupted
            }
            let currentTemp = tempDiv.getChildNodes()
                 .compactMap({ $0 as? TextNode })
                 .map({ $0.text().trimmingCharacters(in: .whitespacesAndNewlines) })
                 .first(where: { !$0.isEmpty })
            let (tmax, tmin): (String?, String?) = {
                guard let textremDiv = try? doc.select("div.textrem").first() else {
                    return (nil, nil)
                }

                let max = try? textremDiv.select("span.tmax").first()?.text()
                let min = try? textremDiv.select("span.tmin").first()?.text()
                return (max, min)
            }()
            let (humidity, rain, pressure, wind): (String?, String?, String?, String?) = {
                guard let table = try? doc.select("section.variables table").first() else {
                    return (nil, nil, nil, nil)
                }

                let rows = try? table.select("tr")
                var humidity: String?
                var rain: String?
                var preassure: String?
                var wind: String?

                rows?.forEach { row in
                    let th = try? row.select("th").text()
                    let value = try? row.select("td").text().trimmingCharacters(in: .whitespacesAndNewlines)

                    switch th {
                    case "Humitat relativa":
                        humidity = value
                    case _ where th?.contains("Precipitació") == true:
                        rain = value
                    case _ where th?.contains("Pressió atmosfèrica") == true:
                        preassure = value
                    case "Vent":
                        wind = value
                    default:
                        break
                    }
                }

                return (humidity, rain, preassure, wind)
            }()
            let desc: String? = {
                try? doc.select("div.descripcio").first()?.text()
            }()
            let iconWeatherURL: URL? = {
                guard let meteorDiv = try? doc.select("div.meteor").first(),
                   let imgElement = try? meteorDiv.select("img").first(),
                   let src = try? imgElement.attr("src")
                else {
                    return nil
                }
                return URL(string: src)
            }()
            let (station, time, dateTime): (String?, String?, String?) = {
                guard let div = try? doc.select("div.fontdades").first(),
                      let abbr = try? div.select("abbr").first()?.text(),
                      let time = try? div.select("time").first()?.text(),
                      let sheetText = try? div.text()
                else {
                    return (nil, nil, nil)
                }
                let station = sheetText
                    .replacingOccurrences(of: abbr, with: "")
                    .replacingOccurrences(of: time, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let datetime = try? div.select("time").first()?.attr("datetime")
                
                return (station, time, datetime)
            }()
            return DTO.CurrentWeather(
                now: DTO.CurrentWeather.Now(
                    currentTemp: currentTemp,
                    maxTemp: tmax,
                    minTemp: tmin,
                    weatherDescription: desc,
                    iconWeather: iconWeatherURL
                ),
                source: DTO.CurrentWeather.Source(
                    station: station,
                    time: time,
                    datetime: dateTime
                ),
                humidity: humidity,
                rain: rain,
                pressure: pressure,
                wind: wind
            )
        } catch {
            throw error
        }
    }
    
    static func getLastTemperature(forStationCode stationCode: String) async throws -> DTO.LastTemperature {
        do {
            let data = try await makeRequest(for: .lastTemperature(forStationCode: stationCode))
                .send()
                .data
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lectures = json["lectures"] as? [[String: Any]],
                  let firstLecture = lectures.first,
                  let valor = firstLecture["valor"] as? Double
            else {
                nonFatalCrashlytics(false, "dataCorrupted")
                throw Requester.ErrorReason.dataCorrupted
            }
            return DTO.LastTemperature(lastTemp: valor, date: "")
        } catch {
            nonFatalCrashlytics(false, "dataCorrupted")
            throw Requester.ErrorReason.dataCorrupted
        }
    }
    
    private static func fetchStations(forceRefresh: Bool) async -> [DTO.Station] {
        /*
        do {
            let result = try await Requester.request(
                "https://api.meteo.cat/xema/v1/estacions/metadades",
                headers: [.custom(headerField: "x-api-key", value: meteocatToken)]
            )
            print("avpv - \(result)")
        } catch {
            print("avpv - \(error.localizedDescription)")
            return []
        }
        */
        do {
            let data = try await makeRequest(for: .stations(forceRefresh: forceRefresh))
                .send()
                .data
            guard let html = String(data: data, encoding: .utf8) else {
                nonFatalCrashlytics(false, "dataCorrupted")
                return []
            }
            return parseStations(from: html)
            
        } catch {
            nonFatalCrashlytics(false, error.localizedDescription)
            return []
        }
    }

    // Function to parse the stations from the HTML using SwiftSoup
    private static func parseStations(from html: String) -> [DTO.Station] {
        do {
            let doc = try SwiftSoup.parse(html)
            
            let scripts = try doc.select("script").array()
            var jsonString: String?

            for script in scripts {
                let scriptText = try script.html()
                if scriptText.contains("var meta =") {
                    if let range = scriptText.range(of: #"var meta ="#, options: .regularExpression) {
                        jsonString = String(scriptText[range.upperBound...])
                    }
                }
            }
            guard let json = jsonString else {
                nonFatalCrashlytics(false, "dataCorrupted")
                return []
            }
            
            if let jsonStart = json.range(of: "{"), let jsonEnd = json.range(of: "};") {
                let jsonSubstring = json[jsonStart.lowerBound..<jsonEnd.upperBound]
                var jsonString = String(jsonSubstring).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if jsonString.last == ";" {
                    jsonString = String(jsonString.dropLast())
                }
                guard let jsonData = jsonString.data(using: .utf8) else {
                    nonFatalCrashlytics(false, "dataCorrupted")
                    return []
                }
                do {
                    // ✅ Decode into a dictionary of stations
                    return try JSONDecoder().decode(Stations.self, from: jsonData).map { $0.value }
                } catch {
                    nonFatalCrashlytics(false, "dataCorrupted")
                    return []
                }
            } else {
                return []
            }
        } catch {
            nonFatalCrashlytics(false, "dataCorrupted")
            return []
        }
    }
}

/// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
// MARK: - Station Request -
/// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

extension ServerData {

    enum ResponseError: Error, Equatable {
        /// The page has no daily summary table: the server has nothing for that day (yet).
        case noDailyData
    }

    /// The daily summary of the UTC day with the same year-month-day as `date`'s (see `DayKey`).
    static func requestStation(code: String, date: Date, now: Date = Date()) async throws -> [DTO.HomeStation] {
        nonFatalCrashlytics(!code.isEmpty, "")

        do {
            // The cache lifetime comes from `DayKey.cacheTTL`, so a page served from the cache
            // can't make a day look finished when it isn't (see `makeRequest`).
            let data = try await makeRequest(for: .requestStation(code: code, date: date), now: now)
                .send()
                .data
            guard let htmlContent = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Invalid data encoding", code: 0, userInfo: nil)
            }
            return try parseDailySummary(html: htmlContent)
        } catch {
            if error is Requester.ErrorReason || error is ResponseError || error is CancellationError {
                throw error
            } else {
                guard let urlError = error as? URLError else {
                    nonFatalCrashlytics(false, "dataCorrupted")
                    throw error
                }
                switch urlError.code {
                case .notConnectedToInternet:
                    throw Requester.ErrorReason.noInternetConnection
                case .cancelled:
                    // A screen went away or a newer request replaced this one: not a failure.
                    throw CancellationError()
                default:
                    nonFatalCrashlytics(false, "dataCorrupted")
                    throw Requester.ErrorReason.dataCorrupted
                }
            }
        }
    }

    /// Rows of the "Dades diàries" table of `/observacions/xema/dades`: title, value and, for some rows, the time.
    static func parseDailySummary(html: String) throws -> [DTO.HomeStation] {
        let document = try SwiftSoup.parse(html)

        let stationName: String = {
            guard let fitxa = try? document.select("#fitxa-ema").first(),
                  let value = try? fitxa.select("h2").first()?.text() ?? "not found"
            else {
                return "not found"
            }
            return value
        }()

        // The daily summary is the first table. When the server has nothing for the day the page has no table
        // or, at most, the station metadata one, which must not be read as measurements.
        guard let table = try document.select("table").first(),
              !(try table.select("caption").text().localizedCaseInsensitiveContains("metadades"))
        else {
            throw ResponseError.noDailyData
        }
        var items: [DTO.HomeStation] = []

        for row in try table.select("tr") {
            // Either <th> for the title or <td> for values
            let columns = try row.select("th, td")

            if columns.size() == 2 {
                let title = try columns.get(0).text()
                let value = try columns.get(1).text()
                items.append(DTO.HomeStation(name: stationName, key: title, value: value, time: nil))
            }

            if columns.size() == 3 {
                let title = try columns.get(0).text()
                let value = try columns.get(1).text()
                let time = try columns.get(2).text()
                items.append(DTO.HomeStation(name: stationName, key: title, value: value, time: time))
            }
        }
        return items
    }
}
