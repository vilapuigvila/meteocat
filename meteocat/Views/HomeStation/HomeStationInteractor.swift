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

    var publisher: AnyPublisher<HomeStationStateDomain, Never> {
        subject.eraseToAnyPublisher()
    }
    var domain: HomeStationStateDomain { subject.value }
    
    let source: Source
    
    init(source: Source) {
        self.source = source
    }
    
    func useCase(_ useCase: UseCase) {
        switch useCase {
        case .requestStation(let date):
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
                guard let code = self.getCodeAccordingSource() else {
                    self.subject.send(.error(.missingCode))
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(0))
                    let result = try await Requester.requestStation(code: code, date: date)
                    self.subject.send(.loaded(result))
                } catch {
                    self.subject.send(.error(.unknown(error.localizedDescription)))
                }
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
    
    enum Source {
        case homeStation, detailStation(code: String)
    }
    
    // MARK: - Action -
    
    enum UseCase {
        case requestStation(date: Date)
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
