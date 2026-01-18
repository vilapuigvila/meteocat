//
//  TabBarViewModel.swift
//  meteocat
//
//  Created by albert vila on 18/1/26.
//

import Foundation
import Combine
import Alfy

@MainActor
final class TabBarViewModel: ObservableObject {
    private let databaseManager: DatabaseManagerProtocol
    private let interactor: TabBarInteractorProtocol

    let stationsViewModel: StationsListViewModel
    let homeViewModel: HomeStationViewModel
    let favsViewModel: FavoritesViewModel

    init(homeStation: PREF.HomeStation? = nil) {
        databaseManager = DatabaseManager.makeShared([
            Model.Station.self, Model.InfoStationByDate.self
        ])

        interactor = TabBarInteractorImpl()

        homeViewModel = HomeStationViewModel(
            stationName: nil,
            interactor: HomeStationInteractorImpl(source: .homeStation, databaseManager: DatabaseManager.shared)
        )
        stationsViewModel = StationsListViewModel(
            interactor: StationsListInteractorImpl(databaseManager: DatabaseManager.shared)
        )
        favsViewModel = FavoritesViewModel(
            interactor: FavoritesInteractorImpl(databaseManager: DatabaseManager.shared)
        )

        interactor.useCase(.appDidStart)
    }
}
