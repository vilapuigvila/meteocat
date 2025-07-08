//
//  DTO.Forecast.swift
//  meteocat
//
//  Created by albert vila on 8/7/25.
//

import Foundation

extension DTO {
    struct CurrentWeather: Decodable, Hashable {
        struct Now: Hashable, Decodable {
            let currentTemp: String?
            let maxTemp: String?
            let minTemp: String?
            let weatherDescription: String?
            let iconWeather: URL?
        }
        struct Source: Hashable, Decodable {
            let station: String?
            let time: String?
            let datetime: String?
        }
        let now: Now
        let source: Source
        
        let humidity: String?
        let rain: String?
        let pressure: String?
        let wind: String?
        
        var rows: [(title: String, content: String)] {
            [
                ("Humidity:",     humidity    ?? "–"),
                ("Rain:",         rain        ?? "–"),
                ("Pressure:",     pressure    ?? "–"),
                ("Wind:",         wind        ?? "–"),
            ]
        }
    }
}
