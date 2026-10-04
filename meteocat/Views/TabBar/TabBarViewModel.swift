//
//  TabBarViewModel.swift
//  meteocat
//
//  Created by albert vila on 18/1/26.
//

import Foundation
import Combine
import UIKit
import Alfy

@MainActor
final class TabBarViewModel: ObservableObject {
    private let databaseManager: DatabaseManagerProtocol
    private let interactor: TabBarInteractorProtocol
    private var cancellables: Set<AnyCancellable> = []

    let stationsViewModel: StationsListViewModel
    let homeViewModel: HomeStationViewModel
    let favsViewModel: FavoritesViewModel
    let weatherMapViewModel = WeatherMapViewModel()

    init(homeStation: PREF.HomeStation? = nil) {
        databaseManager = DatabaseManager.makeShared([
            Model.Station.self, Model.InfoStationByDate.self
        ])

        // one interactor, shared by the Stations tab and the launch call, so the list is requested once
        let stationsInteractor = StationsListInteractorImpl(databaseManager: DatabaseManager.shared)

        // The app host of the unit tests launches the real app: it must not show a permission prompt there,
        // nor read the location.
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        let loadStations: () async -> [DTO.Station] = {
            // joins the launch request in flight; the coordinates come from the cached list (15 days)
            guard await stationsInteractor.ensureStationsAvailable() else { return [] }
            return (try? await ServerData.request(.stations(forceRefresh: false))) ?? []
        }

        // The Stations tab offers the closest station even when the user already has a home station.
        stationsViewModel = StationsListViewModel(
            interactor: stationsInteractor,
            nearestStationSuggester: isRunningUnitTests ? nil : NearestStationSuggester(
                location: CoreLocationOneShotReader(),
                loadStations: loadStations,
                hasHomeStation: { false }
            )
        )

        homeViewModel = HomeStationViewModel(
            stationName: nil,
            interactor: HomeStationInteractorImpl(
                source: .homeStation,
                databaseManager: DatabaseManager.shared,
                nearestStationSuggester: isRunningUnitTests ? nil : NearestStationSuggester(
                    location: CoreLocationOneShotReader(),
                    loadStations: loadStations
                )
            )
        )
        favsViewModel = FavoritesViewModel(
            interactor: FavoritesInteractorImpl(databaseManager: DatabaseManager.shared)
        )

        interactor = TabBarInteractorImpl(
            launchLocationPermission: isRunningUnitTests ? nil : LaunchLocationPermission(
                ensureStations: { await stationsInteractor.ensureStationsAvailable() },
                requester: CoreLocationPermissionRequester()
            )
        )

        interactor.useCase(.appDidStart)
        observeAppActivation()
    }

    /// The location prompt only appears while the app is active, so it is asked on activation, not from `init`.
    private func observeAppActivation() {
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.interactor.useCase(.appDidBecomeActive) }
            .store(in: &cancellables)
        if UIApplication.shared.applicationState == .active {
            interactor.useCase(.appDidBecomeActive)
        }
    }
}
