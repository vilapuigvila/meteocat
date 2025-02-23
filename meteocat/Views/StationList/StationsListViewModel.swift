//
//  StationsViewModel.swift
//  meteocat
//
//  Created by albert vila on 10/2/25.
//

import Foundation
import Combine

final class StationsListViewModel: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    
    @Published
    private(set) var state: StationsList.ViewState = .idle
    private let interactor: StationsListInteractorProtocol
    
    init(interactor: StationsListInteractorProtocol) {
        self.interactor = interactor
        registerPublisher()
    }
    
    func action(_ action: StationsList.Action) {
        switch action {
        case .onAppear:
            interactor.useCase(.requestStations)
        case .onDisappear:
            interactor.useCase(.cancelRequestStations)
        case .pullToRefresh:
            interactor.useCase(.pullToRefresh)
        }
    }
    
    private func registerPublisher() {
        interactor
            .publisher
            .receive(on: DispatchQueue.main)
            .map { domain in
                if domain.isLoading {
                    return .loading
                } else {
                    return domain.list.isEmpty ? .error(.emptyList) : .loaded(domain.list)
                }
            }
            .weakAssign(to: \.state, on: self)
            .store(in: &cancellables)
    }
}
