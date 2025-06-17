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
            guard let code = self.getCodeAccordingSource() else {
                subject.send(.error(.missingCode))
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { assertionFailure(); return }
                
                self.subject.send(.loading)
                
                if let dto = StationWorker.fetchInfoStation(self.databaseManager, code: code, date: date) {
                    self.subject.send(.loaded(dto: dto, stationCode: code, isHome: self.isHomeStation))
                } else {
                    
                    do {
                        let dto = try await StationWorker.requestInfoStation(
                            self.databaseManager,
                            code: code,
                            date: date,
                            store: true
                        )
                        self.subject.send(.loaded(dto: dto, stationCode: code, isHome: self.isHomeStation))
                    } catch {
                        if error is Requester.ErrorReason {
                            self.subject.send(.error(.unknown(error.localizedDescription)))
                        } else {
                            assertionFailure(error.localizedDescription)
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
        case .addAsHome(let stationName, let stationCode):
            if let stationCode, let stationName {
                UserSettings.homeStation = PREF.HomeStation(name: stationName, code: stationCode)
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
            return assertionFailure()
        }
        station.movedToFavorite(isFavorite)
        try databaseManager.save()
    }
    /*
    private func requestInfo(code: String, date: Date, station: Model.Station? = nil) async {
        guard taskRequestStation == nil else {
            return
        }
        subject.send(.loading)
        
        taskRequestStation = Task { [weak self] in
            defer {
                self?.taskRequestStation = nil
            }
            guard let self else {
                return assertionFailure()
            }
            do {
                let dto = try await Requester.requestStation(code: code, date: date)
                await insertInfoDay(dto, stationCode: code, forDate: date)
                self.subject.send(.loaded(dto: dto, stationCode: code, isHome: isHomeStation))
            } catch {
                self.subject.send(.error(.unknown(error.localizedDescription)))
            }
        }
    }*/
    
    private func subscribeHomeStationPref() {
        cancellable = UserSettings.homeStationPublisher.sink { [weak self] _ in
            if case self?.source = Source.homeStation {
                self?.useCase(.requestStation(date: Date()))
            }
        }
    }
    
    private func getCodeAccordingSource() -> String? {
        switch source {
        case .homeStation:
            UserSettings.homeStation?.code
        case .detailStation(let code):
            code
        }
    }

    private var isHomeStation: Bool {
        guard let stationCode = UserSettings.homeStation?.code else {
            return false
        }
        guard case .detailStation(let code) = source else {
            return false
        }
        return stationCode == code
    }
/*
    @MainActor
    private func insertInfoDay(
        _ dto: [DTO.HomeStation],
        stationCode: String,
        forDate date: Date
    ) {
        let predicateStation = #Predicate<Model.Station> { $0.code == stationCode }
        let stations = try? databaseManager.fetchItems(Model.Station.self, predicate: predicateStation, sortBy: nil)
        guard let station = stations?.first else {
            assertionFailure("should not be nil");
            return
        }
        
        pruneInfoStationsUnlessTheMostRecent(stationCode: stationCode, forDate: date)
        
        let createdAt = date.timeIntervalSince1970
        let info = Model.InfoStationByDate(
            values: dto.map {
                Model.InfoStationByDate.Day(name: $0.name, key: $0.key, value: $0.value, time: $0.time)
            },
            createdAt: createdAt,
            station: station
        )
        do {
            try databaseManager.insert(info)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    @MainActor
    private func pruneInfoStationsUnlessTheMostRecent(stationCode: String, forDate date: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let startOfDayTI = startOfDay.timeIntervalSince1970
        let endOfDayTI = endOfDay.timeIntervalSince1970
//        let threshold = Date().addingTimeInterval(-20).timeIntervalSince1970
        
        // 3. Build the predicate to fetch InfoStationByDate records created today for that station.
        let predicate = #Predicate<Model.InfoStationByDate> { info in
            info.station?.code == stationCode
            && info.createdAt >= startOfDayTI && info.createdAt < endOfDayTI
//            && info.createdAt < threshold
        }
        
        do {
            let results = try databaseManager.fetchItems(Model.InfoStationByDate.self, predicate: predicate, sortBy: nil)
            let sortedResults = results.sorted { $0.createdAt > $1.createdAt }
            
            guard let mostRecent = sortedResults.first else {
                print("avp - No records for today found.")
                return
            }
            let recordsToDelete = sortedResults.filter { $0 !== mostRecent }
            try databaseManager.remove(recordsToDelete)
            print("avp Deleted \(recordsToDelete.count) record(s).")
        } catch {
            print("Error during fetch or delete: \(error)")
            assertionFailure(error.localizedDescription)
        }
    }*/
    
    private enum ItemStatus {
        case upToDate(Model.InfoStationByDate)
        case outdated
        case noData
    }
}

extension HomeStationInteractorImpl {
    
    // MARK: - Init interactor from -
    
    enum Source: Equatable {
        case homeStation, detailStation(code: String)
    }
    
    // MARK: - Action -
    
    enum UseCase {
        case requestStation(date: Date)
        case addToFavs(code: String, isFavorite: Bool)
        case addAsHome(stationName: String?, stationCode: String?)
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

struct StationWorker {

    static func requestInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        date: Date,
        store: Bool
    ) async throws -> [DTO.HomeStation] {
        let dto: [DTO.HomeStation] = try await ServerData.requestStation(code: code, date: date)
        if store {
            await insertInfoDay(database, dto: dto, code: code, forDate: date)
        }
        return dto
    }
    
    @MainActor
    static func fetchInfoStation(
        _ database: DatabaseManagerProtocol,
        code: String,
        date: Date
    ) -> [DTO.HomeStation]? {
        guard let info = fetchInfoDayFromDatabase(database, code: code, date: date) else {
            return nil
        }
        let dto = info.values.map {
            DTO.HomeStation(
                name: $0.name,
                key: $0.key,
                value: $0.value,
                time: $0.time,
                isFavorite: info.station?.isFavorite ?? false
            )
        }
        print("avpv - fetch InfoDay from cache")
        return dto
    }
    
    @MainActor
    private static func fetchInfoDayFromDatabase(
        _ databaseManager: DatabaseManagerProtocol,
        code: String,
        date: Date
    ) -> Model.InfoStationByDate? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let startOfDayTI = startOfDay.timeIntervalSince1970
        let endOfDayTI = endOfDay.timeIntervalSince1970
        let threshold = date.addingTimeInterval(-60*60).timeIntervalSince1970
        
        let pred = #Predicate<Model.InfoStationByDate> { info in
            info.station?.code == code
            && info.createdAt >= startOfDayTI && info.createdAt < endOfDayTI
            && info.createdAt > threshold
        }
        do {
            let infos = try databaseManager.fetchItems(Model.InfoStationByDate.self, predicate: pred, sortBy: nil)
            guard let info = infos.first else {
                print("avp - outdated less than 60 minutes. Should request new one")
                return nil
            }
            return info
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }
    
    @MainActor
    private static func insertInfoDay(
        _ databaseManager: DatabaseManagerProtocol,
        dto: [DTO.HomeStation],
        code: String,
        forDate date: Date
    ) {
        let predicateStation = #Predicate<Model.Station> { $0.code == code }
        let stations = try? databaseManager.fetchItems(Model.Station.self, predicate: predicateStation, sortBy: nil)
        guard let station = stations?.first else {
            assertionFailure("should not be nil");
            return
        }
        
        pruneInfoStationsUnlessTheMostRecent(databaseManager, stationCode: code, forDate: date)
        
        let createdAt = date.timeIntervalSince1970
        let info = Model.InfoStationByDate(
            values: dto.map {
                Model.InfoStationByDate.Day(name: $0.name, key: $0.key, value: $0.value, time: $0.time)
            },
            createdAt: createdAt,
            station: station
        )
        do {
            try databaseManager.insert(info)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    @MainActor
    private static func pruneInfoStationsUnlessTheMostRecent(
        _ databaseManager: DatabaseManagerProtocol,
        stationCode: String,
        forDate date: Date
    ) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let startOfDayTI = startOfDay.timeIntervalSince1970
        let endOfDayTI = endOfDay.timeIntervalSince1970
//        let threshold = Date().addingTimeInterval(-20).timeIntervalSince1970
        
        // 3. Build the predicate to fetch InfoStationByDate records created today for that station.
        let predicate = #Predicate<Model.InfoStationByDate> { info in
            info.station?.code == stationCode
            && info.createdAt >= startOfDayTI && info.createdAt < endOfDayTI
//            && info.createdAt < threshold
        }
        
        do {
            let results = try databaseManager.fetchItems(Model.InfoStationByDate.self, predicate: predicate, sortBy: nil)
            let sortedResults = results.sorted { $0.createdAt > $1.createdAt }
            
            guard let mostRecent = sortedResults.first else {
                print("avp - No records for today found.")
                return
            }
            let recordsToDelete = sortedResults.filter { $0 !== mostRecent }
            try databaseManager.remove(recordsToDelete)
            print("avp Deleted \(recordsToDelete.count) record(s).")
        } catch {
            print("Error during fetch or delete: \(error)")
            assertionFailure(error.localizedDescription)
        }
    }
}
