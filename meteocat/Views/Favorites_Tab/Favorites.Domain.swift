//
//  Favorites.Domain.swift
//  meteocat
//
//  Created by albert vila on 18/1/26.
//

import Foundation

struct FavoritesDomain {
    struct FavoriteValue: Identifiable {
        let id = UUID()
        let name: String
        let maxTemp: String
        let minTemp: String
        let rainAcc: String
        let code: String
        let isFavorite: Bool
    }
    static let empty: FavoritesDomain = .init(list: [], isLoading: false, error: nil)
    
    let list: [FavoriteValue]
    let isLoading: Bool
    let error: FavoritesInteractorImpl.ErrorReason?
    
    struct StationValues: Identifiable {
        var id: String { code }
        let code: String
        let name: String
        let days: [FavoriteValue]
    }
}
