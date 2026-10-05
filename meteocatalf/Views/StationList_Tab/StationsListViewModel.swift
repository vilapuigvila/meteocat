//
//  StationsViewModel.swift
//  meteocatalf
//
//  Created by albert vila on 10/2/25.
//

import Foundation
import Combine

final class StationsListViewModel: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    
    @Published
    private(set) var state: StationsList.ViewState = .idle
    /// The operating station closest to the user. `nil` until known, and when the location isn't allowed.
    @Published
    private(set) var nearest: NearestStation.Suggestion?
    private let interactor: StationsListInteractorProtocol
    private let nearestStationSuggester: NearestStationSuggesting?
    
    init(interactor: StationsListInteractorProtocol, nearestStationSuggester: NearestStationSuggesting? = nil) {
        self.interactor = interactor
        self.nearestStationSuggester = nearestStationSuggester
        registerPublisher()
    }
    
    func action(_ action: StationsList.Action) {
        switch action {
        case .onAppear:
            interactor.useCase(.requestStations)
            refreshNearest()
        case .onDisappear:
            interactor.useCase(.cancelRequestStations)
        case .pullToRefresh:
            interactor.useCase(.pullToRefresh)
        }
    }
    
    private func refreshNearest() {
        guard let nearestStationSuggester else { return }
        Task { @MainActor [weak self] in
            let suggestion = await nearestStationSuggester.suggestion()
            self?.nearest = suggestion
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
