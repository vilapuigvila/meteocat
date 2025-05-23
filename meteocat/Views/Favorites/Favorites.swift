//
//  Favorites.swift
//  meteocat
//
//  Created by albert vila on 27/2/25.
//

import Foundation

enum Favorites: Hashable, Sendable {
    
    enum ViewState: Hashable, Sendable {
        case idle
        case loading
        case loaded([Representable])
        case error(ErrorView)
        
        var result: [Representable] {
            guard case .loaded(let result) = self else {
                return []
            }
            return result
        }
    }
    
    struct Representable: Hashable, Sendable, Identifiable {
        var id: String { stationCode + name }
        let name: String
        let maxTemp: String
        let minTemp: String
        let stationCode: String
        let isFAvorite: Bool
    }
}

extension Favorites {
    
    enum Action: Hashable, Sendable {
        case onAppear
        case onDisappear
//        case request(date: Date)
//        case selectedHomeStation(name: String, code: String)
    }
    
    enum ErrorView: Error {
        case empty
        case networkFailure
        /*
        init(stationInteractorError: HomeStationInteractorImpl.ErrorReason) {
            switch stationInteractorError {
            case .missingCode:
                self = .empty
            default:
                self = .networkFailure
            }
        }*/
    }
}
