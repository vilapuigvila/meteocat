//
//  FavoritesInteractor.swift
//  meteocat
//
//  Created by albert vila on 27/2/25.
//

import Foundation
import Combine
import Alfy

protocol FavoritesInteractorProtocol {
    var domain: FavoritesDomain { get }
    var publisher: AnyPublisher<FavoritesDomain, Never> { get }
    func useCase(_ useCase: FavoritesInteractorImpl.UseCase)
    func fetchFavoritesMonthToDate(referenceDate: Date) async throws -> [FavoritesDomain.StationValues]
}

final class FavoritesInteractorImpl: FavoritesInteractorProtocol {
    private var requestStationsTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private let subject = CurrentValueSubject<FavoritesDomain, Never>(.empty)

    var publisher: AnyPublisher<FavoritesDomain, Never> {
        subject.eraseToAnyPublisher()
    }
    var domain: FavoritesDomain { subject.value }
    
//    print("avpv - \(String(describing: interval))")
    private let throttle = RequestThrottleController(minimumInterval: 1, extraRequestsLimit: 2)
    let databaseManager: DatabaseManagerProtocol
    
    init(databaseManager: DatabaseManagerProtocol) {
        self.databaseManager = databaseManager
    }
    
    func useCase(_ useCase: FavoritesInteractorImpl.UseCase) {
        switch useCase {
        case .fetchFavorites:
            guard throttle.startRequestIfAllowed(at: Date()) else {
                return
            }
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
        requestStationsTask?.cancel()
        
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
            requestStationsTask = Task {
                
                do {
                    let result: [Fav] = try await withThrowingTaskGroup(of: Fav?.self) { group in
                        for fav in favs {
                            group.addTask {
                                try await self.requestInfoStation(code: fav.code, date: Date())
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
                    throttle.registerOutcome(isFailure: false)
                    subject.send(FavoritesDomain(list: result, isLoading: false, error: nil))
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    let domainError: FavoritesInteractorImpl.ErrorReason
                    switch error as? Requester.ErrorReason {
                    case .noInternetConnection:
                        domainError = .noInternetConnection
                    case let .some(requesterError):
                        domainError = .unknown(requesterError.localizedDescription)
                    default:
                        domainError = .unknown(error.localizedDescription)
                    }
                    nonFatalCrashlytics(false, error.localizedDescription, domain: .fetch_favorites)
                    throttle.registerOutcome(isFailure: true)
                    subject.send(FavoritesDomain(list: [], isLoading: false, error: domainError))
                }
            }
        } catch {
            if Task.isCancelled {
                return
            }
            nonFatalCrashlytics(false, error.localizedDescription, domain: .fetch_favorites)
            throttle.registerOutcome(isFailure: true)
            subject.send(FavoritesDomain(list: [], isLoading: false, error: .unknown(error.localizedDescription)))
        }
    }
    
    /// Returns the station values for a specific date, using cached DB data when possible.
    private func requestInfoStation(code: String, date: Date) async throws -> Fav? {
        if let dto = await MainActor.run(body: {
            StationWorker.fetchInfoStation(databaseManager, code: code, date: date)
        }) {
            return Self.mapStationInfo(dto, code: code)
        }
        do {
            let dto = try await StationWorker.requestInfoStation(databaseManager, code: code, date: date, store: true)
            return Self.mapStationInfo(dto, code: code)
        } catch {
            if error is Requester.ErrorReason {
                guard case Requester.ErrorReason.noInternetConnection = error else {
                    nonFatalCrashlytics(false, error.localizedDescription)
                    return nil
                }
                throw Requester.ErrorReason.noInternetConnection
            } else {
                nonFatalCrashlytics(false, error.localizedDescription)
                return nil
            }
        }
    }

    /// Returns the list of favorite stations with day-by-day values from the start of the current month until today.
    /// Example: on 2026-01-17 it requests days 1...17 (inclusive).
    func fetchFavoritesMonthToDate(referenceDate: Date = Date()) async throws -> [FavoritesDomain.StationValues] {
        struct FavoriteStationInfo: Sendable {
            let code: String
            let name: String
        }
        let favorites: [FavoriteStationInfo] = try await MainActor.run(body: {
            let stations = try databaseManager.fetchItems(
                Model.Station.self,
                predicate: #Predicate<Model.Station> { $0.isFavorite },
                sortBy: [SortDescriptor(\Model.Station.name, order: .forward)]
            )
            return stations.map { .init(code: $0.code, name: $0.name) }
        })

        let requestDates = Self.monthToDateDates(referenceDate: referenceDate)

        return try await withThrowingTaskGroup(of: FavoritesDomain.StationValues.self) { group in
            for station in favorites {
                group.addTask {
                    var days: [Fav] = []
                    days.reserveCapacity(requestDates.count)

                    for date in requestDates {
                        if let dayValue = try await self.requestInfoStation(code: station.code, date: date) {
                            days.append(dayValue)
                        } else {
                            days.append(
                                Fav(
                                    name: station.name,
                                    maxTemp: "--",
                                    minTemp: "--",
                                    rainAcc: "--",
                                    code: station.code,
                                    isFavorite: true
                                )
                            )
                        }
                    }
                    return FavoritesDomain.StationValues(code: station.code, name: station.name, days: days)
                }
            }

            var results: [FavoritesDomain.StationValues] = []
            results.reserveCapacity(favorites.count)
            for try await stationValues in group {
                results.append(stationValues)
            }
            return results
        }
    }
    
    private static func mapStationInfo(_ dto: [DTO.HomeStation], code: String) -> Fav {
        let maxTemp: String = {
            guard let max = dto.first(where: { Self.normalized($0.key).contains("temperatura maxima") }) else {
                nonFatalCrashlytics(false, "dataCorrupted")
                return "--"
            }
            return max.value
        }()
        let minTemp: String = {
            guard let min = dto.first(where: { Self.normalized($0.key).contains("temperatura minima") }) else {
                nonFatalCrashlytics(false, "dataCorrupted")
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

    private static func monthToDateDates(referenceDate: Date) -> [Date] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return []
        }

        return (1...day).compactMap { dayOfMonth in
            calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))
        }
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
