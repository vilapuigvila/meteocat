//
//  HomeStation.swift
//  meteocatalf
//
//  Created by albert vila on 5/2/25.
//

import Foundation

enum HomeStation: Hashable, Sendable {
    
    enum ViewState: Hashable, Sendable {
        case idle
        case loading
        case loaded(Representable)
        case error(ErrorView)
        case suggestion(NearestStation.Suggestion)
        
        var values: [Representable.Values] {
            guard case .loaded(let result) = self else {
                return []
            }
            return result.values
        }
        var representable: Representable? {
            guard case .loaded(let result) = self else {
                return nil
            }
            return result
        }
    }
    struct Representable: Hashable, Sendable {
        struct Values: Hashable, Sendable {
            let key: String
            let value: String
            let time: String?
        }

        struct MonthDayValue: Hashable, Sendable {
            let date: Date
            let averageTemp: String
            let accumulatedRain: String
            /// The day is still in progress: its values can change.
            let isPartial: Bool
        }

        let values: [Values]
        let name: String
        let code: String
        let cityCode: String
        let isFavorite: Bool
        let isHome: Bool
        let averageTemp: String
        let accumulatedRain: String
        let monthValues: [MonthDayValue]
        /// Days of the month so far with no values, so the tiles are read as covering fewer days.
        let missingDays: Int
        /// The latest reading of the station ("18 °C"), once it has arrived.
        let currentTemp: String?
        /// The sky icon that goes with `currentTemp`.
        let currentWeatherIcon: URL?
    }
}

extension HomeStation {
    
    enum Action: Hashable, Sendable {
        case onAppear
        case onDisappear
        case request(date: Date)
        case addToFavs(code: String, isFavorite: Bool)
        case addAsHome(stationName: String?, code: String?, codeCity: String?)
    }
    
    enum ErrorView: Error {
        case missingStationCode
        case networkFailure
        case noData
        
        init(stationInteractorError: HomeStationInteractorImpl.ErrorReason) {
            switch stationInteractorError {
            case .missingCode:
                self = .missingStationCode
            case .noData:
                self = .noData
            default:
                self = .networkFailure
            }
        }
    }
}

protocol DecoupledView {
    associatedtype Representable: Sendable
    associatedtype Action: Sendable
    var representable: Representable { get }
    var action: (Action) -> Void { get }
}

/*
@propertyWrapper
struct DefaultEmpty<T> where T: ExpressibleByNilLiteral & Equatable {
    var wrappedValue: T
    init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
    static var empty: T {
        return T.self.init(nilLiteral: ())
    }
}
*/
