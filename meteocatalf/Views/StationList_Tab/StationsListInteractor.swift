//
//  StationsListInteractor.swift
//  meteocatalf
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

    /// Resolves to `true` when the request ended with a non-empty list.
    private var requestStationsTask: Task<Bool, Never>?
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
    
    /// Makes sure the stations list is available: from the database when it is fresh, otherwise from the network.
    /// Shares the request in flight with the Stations tab, so the list is never requested twice.
    /// Returns `false` when no list could be obtained.
    func ensureStationsAvailable() async -> Bool {
        await loadStations()
    }

    private func requestStations(pullToRefresh: Bool = false) async {
        _ = await loadStations(pullToRefresh: pullToRefresh)
    }

    @discardableResult
    private func loadStations(pullToRefresh: Bool = false) async -> Bool {
        if let task = requestStationsTask {
            return await task.value
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
            return true
        }
        // another caller may have started the request while the database was being read
        if let task = requestStationsTask {
            return await task.value
        }
        return await fetchAndStoreStations(forceRefresh: pullToRefresh).value
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
            let isOutdated = Date(timeIntervalSince1970: lastUpdated).differenceInSecondsFromNow > Int(ServerData.CacheTTL.stations) // 15 days
            return isOutdated ? nil : stations
        } catch {
            return nil
        }
    }

    /// Fetches stations from the API and stores them in the database
    /// `forceRefresh` makes the request skip Alfy's cache, which also holds the list for 15 days.
    private func fetchAndStoreStations(forceRefresh: Bool) -> Task<Bool, Never> {
        subject.send(.init(list: [], isLoading: true))
        
        let task = Task { [weak self] () -> Bool in
            var didLoad = false
            do {
                let result: [DTO.Station] = try await ServerData.request(.stations(forceRefresh: forceRefresh))
                let sortedStations = result.sorted {
                    $0.name.compare($1.name, locale: Locale(identifier: "ca")) == .orderedAscending
                }
                self?.subject.send(StationsListDomain(list: sortedStations, isLoading: false))
                
                guard !result.isEmpty else {
                    return false
                }
                didLoad = true
                print("avpv 🛜 - stations from api")
                
                guard let self = self else {
                    nonFatalCrashlytics(false, "dataCorrupted")
                    return didLoad
                }
                try await self.refreshStationInDatabase(sortedStations, timeInterval: Date().timeIntervalSince1970)
            } catch {
                nonFatalCrashlytics(false, error.localizedDescription)
            }
            self?.requestStationsTask = nil
            return didLoad
        }
        requestStationsTask = task
        return task
    }

    func cancel() {
        requestStationsTask?.cancel()
        requestStationsTask = nil
    }
    
    @MainActor
    private func refreshStationInDatabase(_ stations: [DTO.Station], timeInterval: TimeInterval) throws {
        do {
            let storedStations = try databaseManager.fetchItems(Model.Station.self, predicate: nil, sortBy: nil)
            var storedByCode: [String: Model.Station] = [:]
            storedByCode.reserveCapacity(storedStations.count)
            storedStations.forEach { station in
                storedByCode[station.code] = station
            }

            var incomingCodes: Set<String> = []
            incomingCodes.reserveCapacity(stations.count)

            var stationsToInsert: [Model.Station] = []
            stationsToInsert.reserveCapacity(stations.count)

            stations.forEach { dto in
                incomingCodes.insert(dto.code)
                if let stored = storedByCode[dto.code] {
                    stored.update(codeCity: dto.city.codi, name: dto.name, type: dto.type, lastUpdated: timeInterval)
                } else {
                    stationsToInsert.append(
                        Model.Station(
                            code: dto.code,
                            codeCity: dto.city.codi,
                            name: dto.name,
                            type: dto.type,
                            lastUpdated: timeInterval
                        )
                    )
                }
            }

            if !stationsToInsert.isEmpty {
                try databaseManager.insert(stationsToInsert)
            }

            let stationsToDelete = storedStations.filter { !incomingCodes.contains($0.code) }
            if !stationsToDelete.isEmpty {
                try databaseManager.remove(stationsToDelete)
            }

            try databaseManager.save()
            print("avpv 🔋 - stations stored in database")
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
