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

struct Requester {
    
    static func requestStation(code: String, date: Date? = nil) async throws -> [DTO.HomeStation] {
        assert(!code.isEmpty)
        
        let currentDate = date ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        let formattedDate = formatter.string(from: currentDate)
        // 2025-02-01T07:00Z
        let urlString = "https://www.meteo.cat/observacions/xema/dades?codi=\(code)&dia=\(formattedDate)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }
        
        do {
            let data = try await URLSession.shared.data(from: url).0
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
                    print("\(title)\t\(value)")
                    items.append(DTO.HomeStation(name: stationName, key: title, value: value, date: nil))
                }
                
                // Extract the title (first column) and value (second column)
                if columns.size() == 3 {
                    let title = try columns.get(0).text()
                    let value = try columns.get(1).text()
                    let value2 = try columns.get(2).text()
                    
                    items.append(DTO.HomeStation(name: stationName, key: title, value: value, date: value2))
                }
            }
            return items
        } catch {
            assertionFailure()
            throw error
        }
    }
    
    static func fetchStations() async -> [DTO.Station] {
        do {
            let data = try await URLSession.shared.data(from: URL(string: "https://www.meteo.cat/observacions/xema")!).0
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
    static func parseStations(from html: String) -> [DTO.Station] {
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
