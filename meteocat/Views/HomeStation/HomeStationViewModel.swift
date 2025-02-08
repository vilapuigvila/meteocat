//
//  HomeStationViewModel.swift
//  meteocat
//
//  Created by albert vila on 5/2/25.
//

import Foundation
import Combine

/*
enum StateDomain<T: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded([T])
    case error(String)
}
*/

enum HomeStationStateDomain: Equatable, Sendable {
    case idle
    case loading
    case loaded([StationModel])
    case error(HomeStationInteractorImpl.ErrorReason)
}

final class HomeStationViewModel: ObservableObject {
    @Published private(set) var state: HomeStation.ViewState = .idle {
        didSet {
            print("\(state)")
        }
    }
    
    let stationName: String?
    let interactor: HomeStationInteractorProtocol
    
    init(stationName: String?, interactor: HomeStationInteractorProtocol) {
        self.stationName = stationName
        self.interactor = interactor
        registerPublisher()
    }
    
    func action(_ action: HomeStation.Action) {
        switch action {
        case .viewAppeared: break
        case .request(let date):
            interactor.useCase(.requestStation(date: date))
        }
    }
    private var cancellables: Set<AnyCancellable> = []

    private func registerPublisher() {
        interactor
            .publisher
            .receive(on: DispatchQueue.main)
            .map(mapToHomeStationState)
            .weakAssign(to: \.state, on: self)
            .store(in: &cancellables)
    }
    
    private func mapToHomeStationState(_ value: HomeStationStateDomain) -> HomeStation.ViewState {
        switch value {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .loaded(let representable):
            return .loaded(
                representable.map {
                    HomeStation.Representable(name: $0.name, key: $0.key, value: $0.value, date: $0.date)
                }
            )
        case .error(let error):
            return .error(error.asHomeStationErrorView())
        }
    }
}
