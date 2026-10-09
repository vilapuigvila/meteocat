//
//  TabBarInteractor.swift
//  meteocatalf
//
//  Created by albert vila on 18/1/26.
//

import Foundation
import Alfy

protocol TabBarInteractorProtocol {
    func useCase(_ useCase: TabBarInteractorImpl.UseCase)
}

final class TabBarInteractorImpl: TabBarInteractorProtocol {
    enum UseCase {
        case appDidStart
        case appDidBecomeActive
    }

    private let launchLocationPermission: LaunchLocationPermission?
    private let widgetRefresher: HomeStationWidgetRefreshing?

    /// `launchLocationPermission` is nil when the app must not ask (unit tests); so is `widgetRefresher`.
    init(
        launchLocationPermission: LaunchLocationPermission? = nil,
        widgetRefresher: HomeStationWidgetRefreshing? = nil
    ) {
        self.launchLocationPermission = launchLocationPermission
        self.widgetRefresher = widgetRefresher
    }

    private static var didPrefetchFavoritesMonthToDate = false

    func useCase(_ useCase: UseCase) {
        switch useCase {
        case .appDidStart:
            guard !Self.didPrefetchFavoritesMonthToDate else { return }
            Self.didPrefetchFavoritesMonthToDate = true
            
            Task.detached(priority: .background) {
                let startTime = CFAbsoluteTimeGetCurrent()
                await Self.prefetchFavoritesMonthToDate()
                let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
                print("avpv - Prefetch completed in \(timeElapsed) seconds")
            }
        case .appDidBecomeActive:
            // Before the permission guard: the widget is fed whether or not the app asks for location.
            if let widgetRefresher {
                Task { @MainActor in
                    await widgetRefresher.refresh()
                }
            }
            guard let launchLocationPermission else { return }
            Task { @MainActor in
                await launchLocationPermission.run()
            }
        }
    }

    private static func prefetchFavoritesMonthToDate() async {
        let databaseManager = await DatabaseManager.shared
        await StationWorker.purgeLegacyCache(databaseManager)
        let favoritesInteractor = FavoritesInteractorImpl(databaseManager: databaseManager)
        await favoritesInteractor.fetchFavoritesMonth()
    }
}
