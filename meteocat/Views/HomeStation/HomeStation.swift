//
//  HomeStation.swift
//  meteocat
//
//  Created by albert vila on 5/2/25.
//

import Foundation

enum HomeStation: Hashable, Sendable {
    
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
    
    struct Representable: Hashable, Sendable {
        let name: String
        let key: String
        let value: String
        let date: String?
    }
}

extension HomeStation {
    
    enum Action: Hashable, Sendable {
        case onAppear
        case onDisappear
        case request(date: Date)
        case selectedHomeStation(String)
    }
    
    enum ErrorView: Error {
        case missingStationCode
        case networkFailure
        
        init(stationInteractorError: HomeStationInteractorImpl.ErrorReason) {
            switch stationInteractorError {
            case .missingCode:
                self = .missingStationCode
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
