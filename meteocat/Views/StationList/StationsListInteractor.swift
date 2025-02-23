//
//  StationsListInteractor.swift
//  meteocat
//
//  Created by albert vila on 22/2/25.
//

import Foundation
//import SwiftUICore
//import SwiftData
//import _SwiftData_SwiftUI
import Combine

struct StationsListDomain {
    static let empty: StationsListDomain = .init(list: [], isLoading: false)
    
    let list: [DTO.Station]
    let isLoading: Bool
//    let error: EquatableError?
    
    func copy(list: [DTO.Station]? = nil, isLoading: Bool? = nil) -> StationsListDomain {
        .init(list: list ?? self.list, isLoading: isLoading ?? self.isLoading)
    }
}

protocol StationsListInteractorProtocol {
    var domain: StationsListDomain { get }
    var publisher: AnyPublisher<StationsListDomain, Never> { get }
    func useCase(_ useCase: StationsListInteractorImpl.UseCase)
}

final class StationsListInteractorImpl: StationsListInteractorProtocol {

    private var requestStationsTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private let subject = CurrentValueSubject<StationsListDomain, Never>(.empty)

    var publisher: AnyPublisher<StationsListDomain, Never> {
        subject.eraseToAnyPublisher()
    }
    var domain: StationsListDomain { subject.value }
    
    let databaseManager: DatabaseManagerProtocol
    
    init(databaseManager: DatabaseManagerProtocol) {
        self.databaseManager = databaseManager
    }
    
    func useCase(_ useCase: UseCase) {
        switch useCase {
        case .requestStations:
            Task {
                await requestStations()
            }
        case .cancelRequestStations:
            cancel()
        case .pullToRefresh:
            Task {
                await requestStations(pullToRefresh: true)
            }
        }
    }
    
    private func requestStations(pullToRefresh: Bool = false) async {
        guard requestStationsTask == nil else { return }

        if let storedStations = await getStoredStations(), !pullToRefresh {
            subject.send(StationsListDomain(list: storedStations.asStationsDTO(), isLoading: false))
        } else {
            subject.send(.init(list: [], isLoading: true))
            fetchAndStoreStations()
        }
    }
    
    /// Retrieves stored stations if they are not outdated
    private func getStoredStations() async -> Model.StationsList? {
        guard let model = await retrieveStation() else { return nil }
        let isOutdated = Date(timeIntervalSince1970: model.lastUpdated).differenceInSecondsFromNow > 60 * 60 * 24
        return isOutdated || model.stations.isEmpty ? nil : model
    }

    /// Fetches stations from the API and stores them in the database
    private func fetchAndStoreStations() {
        requestStationsTask = Task { [weak self] in
            let result = await Requester.fetchStations()
            if !result.isEmpty {
                let sortedStations = result.sorted {
                    $0.name.compare($1.name, locale: Locale(identifier: "ca")) == .orderedAscending
                }
                self?.subject.send(StationsListDomain(list: sortedStations, isLoading: false))
                await self?.storeInDatabase(sortedStations)
            }
            self?.requestStationsTask = nil
        }
    }
    /*
    private func requestStations(pullToRefresh: Bool = false) {
        guard requestStationsTask == nil else {
            return
        }
        let storedStations: Model.Station? = await {
            guard let model = await retrieveStation() else {
                return nil
            }
            let isOutdated = Date(timeIntervalSince1970: model.lastUpdated).differenceInSecondsFromNow > 60*60*24 ? true : false
            if isOutdated || model.values.isEmpty {
                return nil // request refreshed stations
            }
            print("avp - Stations from database")
            return model
        }()
        if let storedStations, !pullToRefresh {
            subject.send(
                StationsListDomain(
                    list: storedStations.asStationsDTO(),
                    isLoading: false
                )
            )
        } else {
            subject.send(.init(list: [], isLoading: true))
            
            requestStationsTask = Task { [weak self] in
                let result = await Requester.fetchStations()
                if result.isEmpty {
                } else {
                    let sortedStations = result.sorted {
                        $0.name.compare($1.name, locale: Locale(identifier: "ca")) == .orderedAscending
                    }
                    self?.subject.send(StationsListDomain(list: sortedStations, isLoading: false))
                    await self?.storeInDatabase(sortedStations)
                }
                self?.requestStationsTask = nil
            }
        }
    }
    */
    func cancel() {
        requestStationsTask?.cancel()
        requestStationsTask = nil
    }
    
    @MainActor
    private func retrieveStation() -> Model.StationsList? {
        do {
            let stationModel = try databaseManager.fetchItems(Model.StationsList.self)
            assert(stationModel.count <= 1, "Expected one station")
            guard let firstStationModel = stationModel.first else {
                return nil
            }
            return firstStationModel
        } catch {
            assertionFailure()
            return nil
        }
    }
    
    @MainActor
    private func storeInDatabase(_ stations: [DTO.Station]) {
        let stations = stations.map {
            Model.StationsList.Values(code: $0.code, name: $0.name, type: $0.type)
        }
        let model = Model.StationsList(stations: stations, lastUpdated: Date().timeIntervalSince1970)
        do {
            try databaseManager.deleteAll(Model.StationsList.self)
            try databaseManager.appendItem(item: model)
            print("avp - Stations updated from network && stored in database")
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
}

extension StationsListInteractorImpl {
    
    // MARK: - Action -
    
    enum UseCase {
        case requestStations
        case cancelRequestStations
        case pullToRefresh
    }
    
    // MARK: - Error -
    
    enum ErrorReason: Error, Equatable {
        case noData
        case decodingFailed
        case missingCode
        case unknown(String)
        
//        func asHomeStationErrorView() -> HomeStation.ErrorView {
//            HomeStation.ErrorView(stationInteractorError: self)
//        }
    }
}
