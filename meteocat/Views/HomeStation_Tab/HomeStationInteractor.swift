//
//  HomeStationInteractor.swift
//  meteocat
//
//  Created by albert vila on 6/2/25.
//

import Foundation
import Combine
import Alfy

protocol HomeStationInteractorProtocol {
    var domain: HomeStationStateDomain { get }
    var publisher: AnyPublisher<HomeStationStateDomain, Never> { get }
    func useCase(_ useCase: HomeStationInteractorImpl.UseCase)
}

final class HomeStationInteractorImpl: HomeStationInteractorProtocol {
    private var taskRequestStation: Task<Void, Never>?
    private let subject = CurrentValueSubject<HomeStationStateDomain, Never>(.idle)
    private var cancellable: AnyCancellable?

    var publisher: AnyPublisher<HomeStationStateDomain, Never> {
        subject.eraseToAnyPublisher()
    }
    var domain: HomeStationStateDomain { subject.value }
    
    let source: Source
    let databaseManager: DatabaseManagerProtocol
    
    init(source: Source, databaseManager: DatabaseManagerProtocol) {
        self.source = source
        self.databaseManager = databaseManager
    }
    
    private func cancel() {
        taskRequestStation?.cancel()
        taskRequestStation = nil
    }
    
    func useCase(_ useCase: UseCase) {
        switch useCase {
        case .cancelRequestStation:
            Task { @MainActor [weak self] in
                guard self?.taskRequestStation != nil else { return }
                self?.cancel()
            }
        case .requestStation(let date):
            guard let (stationCode, cityCode) = self.getCodesAccordingSource() else {
                subject.send(.error(.missingCode))
                return
            }
            
            Task { @MainActor [weak self] in
                guard let self else { nonFatalCrashlytics(false, "dataCorrupted"); return }
                self.subject.send(.loading)
                
                let summary = await StationWorker.fetchMonthInfoStation(databaseManager, code: stationCode)
                
                if let dto = StationWorker.fetchInfoStation(self.databaseManager, code: stationCode, date: date) {
                    self.subject.send(.loaded(
                        dto: dto,
                        stationCode: stationCode,
                        cityCode: cityCode,
                        isHome: self.isHomeStation,
                        summary: summary.stationDayInfoSummary()
                    ))
                } else {
                    do {
                        let dto = try await StationWorker.requestInfoStation(
                            self.databaseManager,
                            code: stationCode,
                            date: date,
                            store: true
                        )
                        self.subject.send(.loaded(
                            dto: dto,
                            stationCode: stationCode,
                            cityCode: cityCode,
                            isHome: self.isHomeStation,
                            summary: summary.stationDayInfoSummary()
                        ))
                    } catch {
                        if error is Requester.ErrorReason {
                            self.subject.send(.error(.unknown(error.localizedDescription)))
                        } else {
                            nonFatalCrashlytics(false, error.localizedDescription)
                            self.subject.send(.error(.unknown(error.localizedDescription)))
                        }
                    }
                }
            }
        case .addToFavs(let code, let isFav):
            Task {
                do {
                    try await addToFavs(code: code, isFavorite: isFav)
                    self.subject.send(domain.copy(isFavorite: isFav))
                } catch {
                    self.subject.send(domain.copy(isFavorite: !isFav))
                }
            }
        case .addAsHome(let stationName, let stationCode, let codeCity):
            if let stationCode, let stationName, let codeCity {
                UserSettings.homeStation = PREF.HomeStation(name: stationName, code: stationCode, codeCity: codeCity)
            } else {
                UserSettings.homeStation = nil
            }
            let _domain = domain.copy(isHome: isHomeStation)
            subject.send(_domain)
        }
    }
    
    @MainActor
    private func addToFavs(code: String, isFavorite: Bool) throws {
        let stations = try databaseManager.fetchItems(
            Model.Station.self,
            predicate: #Predicate<Model.Station> { $0.code == code },
            sortBy: nil
        )
        guard let station = stations.first else {
            return nonFatalCrashlytics(false, "dataCorrupted")
        }
        station.movedToFavorite(isFavorite)
        try databaseManager.save()
    }
    
    private func subscribeHomeStationPref() {
        cancellable = UserSettings.homeStationPublisher.sink { [weak self] _ in
            if case self?.source = Source.homeStation {
                self?.useCase(.requestStation(date: Date()))
            }
        }
    }
    
    private func getCodesAccordingSource() -> (stationCode: String, cityCode: String)? {
        switch source {
        case .homeStation:
            guard let homeStation = UserSettings.homeStation else {
                return nil
            }
            return (homeStation.code, homeStation.codeCity)
        case .detailStation(let code, let cityCode):
            return (code, cityCode)
        }
    }

    private var isHomeStation: Bool {
        guard let stationCode = UserSettings.homeStation?.code else {
            return false
        }
        guard case .detailStation(let code, _) = source else {
            return false
        }
        return stationCode == code
    }
    
    private enum ItemStatus {
        case upToDate(Model.InfoStationByDate)
        case outdated
        case noData
    }
}

extension HomeStationInteractorImpl {
    
    // MARK: - Init interactor from -
    
    enum Source: Equatable {
        case homeStation, detailStation(code: String, cityCode: String)
    }
    
    // MARK: - Action -
    
    enum UseCase {
        case requestStation(date: Date)
        case addToFavs(code: String, isFavorite: Bool)
        case addAsHome(stationName: String?, stationCode: String?, codeCity: String?)
        case cancelRequestStation
    }
    
    // MARK: - Error -
    
    enum ErrorReason: Error, Equatable {
        case noData
        case decodingFailed
        case missingCode
        case unknown(String)
        case noInternetConnection
        
        func asHomeStationErrorView() -> HomeStation.ErrorView {
            HomeStation.ErrorView(stationInteractorError: self)
        }
    }
}
