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
    case loaded(dto: [DTO.HomeStation], stationCode: String, cityCode: String, isHome: Bool)
    case error(HomeStationInteractorImpl.ErrorReason)
    
    var result: [DTO.HomeStation] {
        guard case .loaded(let dto, _, _, _) = self else {
            return []
        }
        return dto
    }
    var stationCode: String {
        if case .loaded(_, let code, _, _) = self {
            return code
        } else {
            assertionFailure()
            return ""
        }
    }
    var cityCode: String {
        if case .loaded(_, _, let cityCode, _) = self {
            return cityCode
        } else {
            assertionFailure()
            return ""
        }
    }
    var isHome: Bool {
        if case .loaded(_, _, _, let isHome) = self {
            return isHome
        } else {
            assertionFailure()
            return false
        }
    }
    var isFavorite: Bool {
        if case .loaded(let dto, _, _, _) = self {
            return dto.first?.isFavorite ?? false
        } else {
            assertionFailure()
            return false
        }
    }
    func copy(isHome: Bool? = nil, isFavorite: Bool? = nil) -> Self {
        .loaded(
            dto: result.map {
                DTO.HomeStation(
                    name: $0.name,
                    key: $0.key,
                    value: $0.value, time: $0.time, isFavorite: isFavorite ?? self.isFavorite)
            },
            stationCode: stationCode,
            cityCode: cityCode,
            isHome: isHome ?? self.isHome
        )
    }
}

final class HomeStationViewModel: ObservableObject {
    @Published private(set) var stateView: HomeStation.ViewState = .idle
    
    var stationName: String?
    let interactor: HomeStationInteractorProtocol
    
    init(stationName: String?, interactor: HomeStationInteractorProtocol) {
        self.stationName = stationName
        self.interactor = interactor
        registerPublisher()
    }
    
    func action(_ action: HomeStation.Action) {
        switch action {
        case .onAppear:
            interactor.useCase(.requestStation(date: Date()))
        case .onDisappear:
            interactor.useCase(.cancelRequestStation)
        case .request(let date):
            interactor.useCase(.requestStation(date: date))
        case .addToFavs(let stationCode, let isFav):
            interactor.useCase(.addToFavs(code: stationCode, isFavorite: isFav))
        case .addAsHome(let stationName, let code, let codeCity):
            interactor.useCase(.addAsHome(stationName: stationName, stationCode: code, codeCity: codeCity))
        case .presentCurrentWeather(let stationCode):
            break
        }
    }
    private var cancellables: Set<AnyCancellable> = []

    private func registerPublisher() {
        interactor
            .publisher
            .receive(on: DispatchQueue.main)
            .map(mapToHomeStationState)
            .weakAssign(to: \.stateView, on: self)
            .store(in: &cancellables)
    }
    
    private func mapToHomeStationState(_ value: HomeStationStateDomain) -> HomeStation.ViewState {
        switch value {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .loaded(let representable, let stationCode, let cityCode, let isHome):
            print("avvp [HOME STATION VM] - \(dump(representable))")
            let values = representable.map {
                HomeStation.Representable.Values(key: $0.key, value: $0.value, time: $0.time)
            }
            return .loaded(
                HomeStation.Representable(
                    values: values,
                    name: representable.first?.name ?? "",
                    code: stationCode,
                    cityCode: cityCode,
                    isFavorite: representable.first?.isFavorite ?? false,
                    isHome: isHome
                )
            )
        case .error(let error):
            return .error(error.asHomeStationErrorView())
        }
    }
}
