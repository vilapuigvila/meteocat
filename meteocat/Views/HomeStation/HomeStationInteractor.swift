//
//  HomeStationInteractor.swift
//  meteocat
//
//  Created by albert vila on 6/2/25.
//

import Foundation
import Combine

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
    init(source: Source) {
        self.source = source
        subscribeHomeStationPref()
    }
    
    func useCase(_ useCase: UseCase) {
        switch useCase {
        case .cancelRequestStation:
            taskRequestStation?.cancel()
            taskRequestStation = nil
        case .requestStation(let date):
            guard let code = self.getCodeAccordingSource() else {
                subject.send(.error(.missingCode))
                return
            }
            guard taskRequestStation == nil && isRequestAllowed(forCode: code) else {
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
                    try await Task.sleep(for: .seconds(0))
                    let result = try await Requester.requestStation(code: code, date: date)
                    self.setNewDateRequest(code: code)
                    self.subject.send(.loaded(result))
                } catch {
                    self.subject.send(.error(.unknown(error.localizedDescription)))
                }
            }
        }
    }
    
    private func setNewDateRequest(code: String) {
        let lastHomeStation: PREF.LastRequests = {
            guard let pref = UserSettings.lastHomeStationRequest else {
                return PREF.LastRequests(requests: [])
            }
            return pref
        }()
        UserSettings.lastHomeStationRequest = lastHomeStation.append(PREF.LastRequests.Request(timeInterval: Date().timeIntervalSince1970, code: code))
    }
    
    private func isRequestAllowed(forCode code: String) -> Bool {
        let isRequestOutDate: Bool = {
            guard let request = UserSettings.lastHomeStationRequest?.requests.first(where: { $0.code == code }) else {
                return true
            }
            let isOutdated = Date(timeIntervalSince1970: request.timeInterval).differenceInSecondsFromNow > 60*5 ? true : false
            return isOutdated
        }()
        guard !domain.result.isEmpty else {
            return true
        }
        return isRequestOutDate
    }
    
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
}

extension HomeStationInteractorImpl {
    
    // MARK: - Init interactor from -
    
    enum Source: Equatable {
        case homeStation, detailStation(code: String)
    }
    
    // MARK: - Action -
    
    enum UseCase {
        case requestStation(date: Date)
        case cancelRequestStation
    }
    
    // MARK: - Error -
    
    enum ErrorReason: Error, Equatable {
        case noData
        case decodingFailed
        case missingCode
        case unknown(String)
        
        func asHomeStationErrorView() -> HomeStation.ErrorView {
            HomeStation.ErrorView(stationInteractorError: self)
        }
    }
}
