//
//  StationsListInteractor.swift
//  meteocat
//
//  Created by albert vila on 22/2/25.
//

import Foundation
import Combine
import Alfy

struct StationsListDomain {
    static let empty: StationsListDomain = .init(list: [], isLoading: false)
    
    let list: [DTO.Station]
    let isLoading: Bool
    
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
        guard requestStationsTask == nil else {
            return
        }
        if let storedStations = await fetchStationsFromDatabase(), !pullToRefresh {
            subject.send(
                StationsListDomain(
                    list: storedStations.map {
                        DTO.Station(code: $0.code, name: $0.name, type: $0.type, isFavorite: $0.isFavorite)
                    },
                    isLoading: false)
            )
            print("avp 📊 - stations list updated from db")
        } else {
            fetchAndStoreStations()
        }
#warning("avpv check it out ⚠️ -> remove")
//        fetchAndStoreStations()
    }
    
    /// Retrieves stored stations if they are not outdated
    @MainActor
    private func fetchStationsFromDatabase() async -> [Model.Station]? {
        do {
            let stations = try databaseManager.fetchItems(
                Model.Station.self,
                predicate: nil,
                sortBy: [SortDescriptor(\Model.Station.name, order: .forward)]
            )
            if stations.count >= 1 {
                nonFatalCrashlytics(stations.first?.lastUpdated != nil, "")
            }
            guard let lastUpdated = stations.first?.lastUpdated else {
                return nil
            }
            let isOutdated = Date(timeIntervalSince1970: lastUpdated).differenceInSecondsFromNow > 60 * 60 * 24 * 15 // 15 days
            return isOutdated ? nil : stations
        } catch {
            return nil
        }
    }

    /// Fetches stations from the API and stores them in the database
    private func fetchAndStoreStations() {
        subject.send(.init(list: [], isLoading: true))
        
        requestStationsTask = Task { [weak self] in
            do {
                let result: [DTO.Station] = try await ServerData.request(.stations)
                let sortedStations = result.sorted {
                    $0.name.compare($1.name, locale: Locale(identifier: "ca")) == .orderedAscending
                }
                self?.subject.send(StationsListDomain(list: sortedStations, isLoading: false))
                
                guard !result.isEmpty else {
                    return
                }
                print("avpv 🛜 - stations from api")
                
                guard let self = self else {
                    return nonFatalCrashlytics(false, "dataCorrupted")
                }
                try await self.refreshStationInDatabase(sortedStations, timeInterval: Date().timeIntervalSince1970)
            } catch {
                nonFatalCrashlytics(false, error.localizedDescription)
            }
            self?.requestStationsTask = nil
        }
    }

    func cancel() {
        requestStationsTask?.cancel()
        requestStationsTask = nil
    }
    
    @MainActor
    private func refreshStationInDatabase(_ stations: [DTO.Station], timeInterval: TimeInterval) throws {
        // city.codi
        let stations = stations.map {
            Model.Station(
                code: $0.code,
                codeCity: $0.city.codi,
                name: $0.name,
                type: $0.type,
                lastUpdated: timeInterval
            )
        }
        do {
            try databaseManager.deleteAll(Model.Station.self)
            try databaseManager.insert(stations)
            print("avpv 🔋 - stations stored in daata base")
        } catch {
            throw error
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
