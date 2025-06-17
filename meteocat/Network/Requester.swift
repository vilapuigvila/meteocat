//
//  Requester.swift
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
        case stations
        case requestStation(code: String, date: Date = Date())
    }
    static func request<D: Decodable>(_ service: Service) async throws -> D {
        let decodable: Decodable = try await {
            switch service {
            case .lastTemperature(let forStationCode):
                try await getLastTemperature(forStationCode: forStationCode)
            case .stations:
                await fetchStations()
            case .requestStation(let code, let date):
                try await requestStation(code: code, date: date)
            }
        }()
        return decodable as! D
    }
    
    private static let meteocatToken = "7r5zloC5zs2MjyxAfdnkd1cvuUeKpvWQ9cONyuPh"
    private static let xApiKey: Requester.HeaderParam =
        .custom(headerField: "x-api-key", value: meteocatToken)
    
    /// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
    // MARK: - Requests -
    /// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
    
    static func getLastTemperature(forStationCode stationCode: String) async throws -> DTO.LastTemperature {
        do {
            let data = try await Requester.request(
                "https://api.meteo.cat/xema/v1/variables/mesurades/32/ultimes?codiEstacio=\(stationCode)",
                headers: [ServerData.xApiKey]
            ).data
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lectures = json["lectures"] as? [[String: Any]],
                  let firstLecture = lectures.first,
                  let valor = firstLecture["valor"] as? Double
            else {
                assertionFailure()
                throw Requester.ErrorReason.dataCorrupted
            }
            return DTO.LastTemperature(lastTemp: valor, date: "")
        } catch {
            assertionFailure()
            throw Requester.ErrorReason.dataCorrupted
        }
    }
    
    static func fetchStations() async -> [DTO.Station] {
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
            let data = try await Requester.request("https://www.meteo.cat/observacions/xema").data
            guard let html = String(data: data, encoding: .utf8) else {
                assertionFailure()
                return []
            }
            return parseStations(from: html)
            
        } catch {
            assertionFailure(error.localizedDescription)
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
                assertionFailure()
                return []
            }
            
            if let jsonStart = json.range(of: "{"), let jsonEnd = json.range(of: "};") {
                let jsonSubstring = json[jsonStart.lowerBound..<jsonEnd.upperBound]
                var jsonString = String(jsonSubstring).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if jsonString.last == ";" {
                    jsonString = String(jsonString.dropLast())
                }
                guard let jsonData = jsonString.data(using: .utf8) else {
                    assertionFailure()
                    return []
                }
                do {
                    // ✅ Decode into a dictionary of stations
                    return try JSONDecoder().decode(Stations.self, from: jsonData).map { $0.value }
                } catch {
                    assertionFailure()
                    return []
                }
            } else {
                return []
            }
        } catch {
            assertionFailure()
            return []
        }
    }
}

/// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
// MARK: - Station Request -
/// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

extension ServerData {
    
    static func requestStation(code: String, date: Date) async throws -> [DTO.HomeStation] {
        assert(!code.isEmpty)
//        let value = await getLastTemperature(forStationCode: "CC")
//        print("avpv - \(value)")
        
        /*
        do {
            let data = try await Requester.request("https://www.meteo.cat/observacions/xema").data
            guard let htmlContent = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Invalid data encoding", code: 0, userInfo: nil)
            }
            let document = try SwiftSoup.parse(htmlContent)
            print("avpv - \(document)")
        } catch {
            assertionFailure()
        }*/
        
        let formattedDate = dateFormatterForRequestStation(date) // 2025-02-01T07:00Z
        
        do {
            let data = try await Requester
                .request("https://www.meteo.cat/observacions/xema/dades?codi=\(code)&dia=\(formattedDate)")
                .data
            guard let htmlContent = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Invalid data encoding", code: 0, userInfo: nil)
            }
            let document = try SwiftSoup.parse(htmlContent)
            
            let stationName: String = {
                guard let fitxa = try? document.select("#fitxa-ema").first(),
                      let value = try? fitxa.select("h2").first()?.text() ?? "not found"
                else {
                    return "not found"
                }
                return value
            }()
            
            // Step 4: Select the table with the "Resum diari" data (the first <table> element)
            guard let table = try document.select("table").first() else {
                throw NSError(domain: "Invalid HTML structure", code: 0, userInfo: nil)
            }
            var items: [DTO.HomeStation] = []
            
            // Step 5: Select all rows in the table (excluding the header)
            let rows = try table.select("tr")
            
            for row in rows {
                // Get the columns (either <th> for title or <td> for values)
                let columns = try row.select("th, td")
                
                // Skip rows with no useful data
                if columns.isEmpty() { continue }

                if columns.size() == 2 {
                    let title = try columns.get(0).text()
                    let value = try columns.get(1).text()
                    
                    // Step 6: Print the title and value in the desired format
//                    print("\(title)\t\(value)")
                    items.append(DTO.HomeStation(name: stationName, key: title, value: value, time: nil))
                }
                
                // Extract the title (first column) and value (second column)
                if columns.size() == 3 {
                    let title = try columns.get(0).text()
                    let value = try columns.get(1).text()
                    let value2 = try columns.get(2).text()
                    
                    items.append(DTO.HomeStation(name: stationName, key: title, value: value, time: value2))
                }
            }
            return items
        } catch {
            guard let urlError = error as? URLError else {
                assertionFailure()
                throw error
            }
            switch urlError.code {
            case .notConnectedToInternet:
                throw Requester.ErrorReason.noInternetConnection
            case .cancelled:
                assertionFailure()
                throw Requester.ErrorReason.generic(statusCode: 500)
            default:
                assertionFailure()
                throw Requester.ErrorReason.dataCorrupted
            }
        }
    }
}

// MARK: - DateFormatter Helpers -

extension ServerData {
    private static var dateFormatter: DateFormatter = {
        DateFormatter()
    }()
    private static let dateFormatterForRequestStation: (Date) -> String = { date in
        let currentDate = date
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return dateFormatter.string(from: currentDate)
    }
}
