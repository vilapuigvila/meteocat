//
//  FavoritesInteractor.swift
//  meteocat
//
//  Created by albert vila on 27/2/25.
//

import Foundation
import Combine
import Alfy

struct FavoritesDomain {
    struct FavoriteValue: Identifiable {
        let id = UUID()
        let name: String
        let maxTemp: String
        let minTemp: String
        let rainAcc: String
        let code: String
        let isFavorite: Bool
    }
    static let empty: FavoritesDomain = .init(list: [], isLoading: false, error: nil)
    
    let list: [FavoriteValue]
    let isLoading: Bool
    let error: FavoritesInteractorImpl.ErrorReason?
    /*
    func copy(list: [FavoriteValue]? = nil, isLoading: Bool? = nil) -> StationsListDomain {
//        .init(list: list ?? self.list, isLoading: isLoading ?? self.isLoading)
    }*/ 
}

protocol FavoritesInteractorProtocol {
    var domain: FavoritesDomain { get }
    var publisher: AnyPublisher<FavoritesDomain, Never> { get }
    func useCase(_ useCase: FavoritesInteractorImpl.UseCase)
}

final class FavoritesInteractorImpl: FavoritesInteractorProtocol {
    private var requestStationsTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private let subject = CurrentValueSubject<FavoritesDomain, Never>(.empty)

    var publisher: AnyPublisher<FavoritesDomain, Never> {
        subject.eraseToAnyPublisher()
    }
    var domain: FavoritesDomain { subject.value }
    
    let databaseManager: DatabaseManagerProtocol
    
    init(databaseManager: DatabaseManagerProtocol) {
        self.databaseManager = databaseManager
    }
    
    func useCase(_ useCase: FavoritesInteractorImpl.UseCase) {
        switch useCase {
        case .fetchFavorites:
            Task {
                await fetchFavoritesFromData()
            }
        case .cancelRequestStations:
            break
        case .pullToRefresh:
            break
        }
    }
    
    fileprivate typealias Fav = FavoritesDomain.FavoriteValue
    
    @MainActor
    private func fetchFavoritesFromData() {
        subject.send(FavoritesDomain(list: domain.list, isLoading: true, error: nil))
        
        do {
            let stations = try databaseManager.fetchItems(
                Model.Station.self,
                predicate: #Predicate<Model.Station> { $0.isFavorite },
                sortBy: nil
            )
            let favs = stations.map {
                DTO.Station(code: $0.code, name: $0.name, type: $0.type, isFavorite: $0.isFavorite)
            }
            Task {
                do {
                    let result: [Fav] = try await withThrowingTaskGroup(of: Fav?.self) { group in
                        for fav in favs {
                            group.addTask {
                                try await self.requestInfoStation(code: fav.code)
                            }
                        }
                        var favsResult = [Fav]()
                        favsResult.reserveCapacity(favs.count)
                        do {
                            for try await result in group {
                                guard let fav = result else { continue }
                                favsResult.append(fav)
                            }
                            return favsResult
                        } catch {
                            throw error
                        }
                    }
                    subject.send(FavoritesDomain(list: result, isLoading: false, error: nil))
                } catch {
                    let domainError: FavoritesInteractorImpl.ErrorReason
                    switch error as? Requester.ErrorReason {
                    case .noInternetConnection:
                        domainError = .noInternetConnection
                    case let .some(requesterError):
                        domainError = .unknown(requesterError.localizedDescription)
                    default:
                        domainError = .unknown(error.localizedDescription)
                    }
                    subject.send(FavoritesDomain(list: [], isLoading: false, error: domainError))
                }
            }
        } catch {
            subject.send(FavoritesDomain(list: [], isLoading: false, error: .unknown(error.localizedDescription)))
        }
    }
    
    @MainActor
    private func requestInfoStation(code: String) async throws -> Fav? {
        if let dto = StationWorker.fetchInfoStation(databaseManager, code: code, date: Date()) {
            return Self.mapStationInfo(dto, code: code)
        }
        do {
            let dto = try await StationWorker.requestInfoStation(databaseManager, code: code, date: Date(), store: true)
            return Self.mapStationInfo(dto, code: code)
        } catch {
            if error is Requester.ErrorReason {
                guard case Requester.ErrorReason.noInternetConnection = error else {
                    assertionFailure(error.localizedDescription)
                    return nil
                }
                throw Requester.ErrorReason.noInternetConnection
            } else {
                assertionFailure(error.localizedDescription)
                return nil
            }
        }
    }
    
    private static func mapStationInfo(_ dto: [DTO.HomeStation], code: String) -> Fav {
        let maxTemp: String = {
            guard let max = dto.first(where: { Self.normalized($0.key).contains("temperatura maxima") }) else {
                assertionFailure()
                return "--"
            }
            return max.value
        }()
        let minTemp: String = {
            guard let min = dto.first(where: { Self.normalized($0.key).contains("temperatura minima") }) else {
                assertionFailure()
                return "--"
            }
            return min.value
        }()
        let rain: String = {
            guard let value = dto.first(where: { Self.normalized($0.key).contains("precipitacio acumulada") })?.value else {
                return "--"
            }
            return value.contains("0.0") ? "--" : value
        }()
        return Fav(
            name: dto.first?.name ?? "",
            maxTemp: maxTemp,
            minTemp: minTemp,
            rainAcc: rain,
            code: code,
            isFavorite: true
        )
    }
    
    private static func normalized(_ string: String) -> String {
        string.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}

extension FavoritesInteractorImpl {
    
    // MARK: - Action -
    
    enum UseCase {
        case fetchFavorites
        case cancelRequestStations
        case pullToRefresh
    }
    
    // MARK: - Error -
    
    enum ErrorReason: Error, Equatable {
        case noData
        case decodingFailed
        case missingCode
        case noInternetConnection
        case unknown(String)
    }
}
