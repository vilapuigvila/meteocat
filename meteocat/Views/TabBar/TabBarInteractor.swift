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
        }
    }

    private static func prefetchFavoritesMonthToDate() async {
        let databaseManager = await DatabaseManager.shared
        await StationWorker.purgeLegacyCache(databaseManager)
        let favoritesInteractor = FavoritesInteractorImpl(databaseManager: databaseManager)
        await favoritesInteractor.fetchFavoritesMonth()
    }
}
