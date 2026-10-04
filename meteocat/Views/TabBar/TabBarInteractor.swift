//
//  TabBarInteractor.swift
//  meteocat
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

    /// `launchLocationPermission` is nil when the app must not ask (unit tests).
    init(launchLocationPermission: LaunchLocationPermission? = nil) {
        self.launchLocationPermission = launchLocationPermission
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
