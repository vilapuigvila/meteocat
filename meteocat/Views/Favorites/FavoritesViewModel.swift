//
//  FavoritesViewModel.swift
//  meteocat
//
//  Created by albert vila on 27/2/25.
//

import Foundation
import Combine

/*
enum FavoritesStateDomain: Equatable {
    case idle
    case loading
    case loaded([DTO.HomeStation])
    case error(EquatableError)
    
    var result: [DTO.HomeStation] {
        guard case .loaded(let result) = self else {
            return []
        }
        return result
    }
}*/

final class FavoritesViewModel: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    
    @Published private(set) var stateView: Favorites.ViewState = .idle
    
    let interactor: FavoritesInteractorProtocol
    
    init(interactor: FavoritesInteractorProtocol) {
        self.interactor = interactor
        registerPublisher()
    }
    
    func action(_ action: Favorites.Action) {
        switch action {
        case .onAppear:
            interactor.useCase(.fetchFavorites)
        case .onDisappear:
            break
        }
    }
    #warning("avp check it out ⚠️ -> needs max and min temp")
    private func registerPublisher() {
        interactor
            .publisher
            .receive(on: DispatchQueue.main)
            .map { domain in
                if domain.isLoading {
                    return .loading
                } else {
                    return domain.list.isEmpty ? .error(.empty) :
                        .loaded(domain.list.map {
                            Favorites.Representable(
                                name: $0.name,
                                maxTemp: $0.maxTemp,
                                minTemp: $0.minTemp,
                                stationCode: $0.code,
                                isFAvorite: $0.isFavorite
                            )
                        })
                }
            }
            .weakAssign(to: \.stateView, on: self)
            .store(in: &cancellables)
    }
}
