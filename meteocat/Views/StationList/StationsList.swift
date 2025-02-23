//
//  StationDetail.swift
//  meteocat
//
//  Created by albert vila on 10/2/25.
//

import Foundation
import SwiftData

//enum ViewState<T: Sendable & Equatable, E: Error>: Equatable {
//    case idle
//    case loading
//    case loaded(T)
//    case error(E)
//    var result: T? {
//        guard case .loaded(let result) = self else {
//            return nil
//        }
//        return result
//    }
//}

enum StationsList: Sendable {
    
    enum ViewState: Sendable, Hashable {
        case idle
        case loading
        case loaded([DTO.Station])
        case error(ErrorView)
        
        var result: Representable {
            guard case .loaded(let result) = self else {
                return .init(stations: [])
            }
            return Representable(stations: result )
        }
    }
    
    struct Representable: Hashable {
        let stations: [DTO.Station]
        
        static let empty: Representable = .init(stations: [])
    }
    
    enum Action: Sendable {
        case onAppear
        case onDisappear
        case pullToRefresh
//        case homeStationSelected(Station)
    }
    
    enum ErrorView: Error {
        case unknown
        case emptyList
        case networkFailure
    }
}

extension String {
    var firstLetterUppercased: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}
