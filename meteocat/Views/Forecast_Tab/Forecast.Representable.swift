//
//  Forecast.Representable.swift
//  meteocat
//
//  Created by albert vila on 4/7/25.
//

import Foundation

extension Forecast {
    
    enum ErrrorView: Hashable {
        case noInternet
        case emptyData
    }
    
    struct Representable: Hashable {
        struct Now: Hashable {
            let currentTemp: String
            let maxTemp: String
            let minTemp: String
            let weatherDescription: String
            let iconWeather: URL?
            
            static let empty: Now = .init(currentTemp: "", maxTemp: "", minTemp: "", weatherDescription: "", iconWeather: nil)
        }
        struct Source: Hashable {
            let station: String
            let time: String
            let datetime: String
            
            static let empty: Source = .init(station: "", time: "", datetime: "")
        }
        
        struct Row: Hashable {
            let title: String
            let weatherValue: String
        }
        let now: Now
        let source: Source
        let rows: [Row]
        
        static let empty: Representable = .init(
            now: .empty,
            source: .empty,
            rows: []
        )
    }
    
    enum StateView: Hashable {
        case idle
        case loading
        case loaded(Representable)
        case error(ErrrorView)
        
        var result: Representable {
            guard case .loaded(let result) = self else {
                return .empty
            }
            return result
        }
    }
    
    enum ActionView: Hashable {
        case onAppear
        case onDisappear
    }
}
