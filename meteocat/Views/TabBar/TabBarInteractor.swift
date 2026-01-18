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

            Task(priority: .background) {
                await Self.prefetchFavoritesMonthToDate()
            }
        }
    }

    private static func prefetchFavoritesMonthToDate(referenceDate: Date = Date()) async {
        let databaseManager = await DatabaseManager.shared
        let favoritesInteractor = FavoritesInteractorImpl(databaseManager: databaseManager)
        _ = try? await favoritesInteractor.fetchFavoritesMonthToDate(referenceDate: referenceDate)
    }
}
