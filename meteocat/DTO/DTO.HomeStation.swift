//
//  DTO.HomeStation.swift
//  meteocat
//
//  Created by albert vila on 23/2/25.
//

import Foundation

extension DTO {
    struct HomeStation: Decodable, Hashable {
        let name: String
        let key: String
        let value: String
        let time: String?
        private(set) var isFavorite: Bool = false
        
        func copyWithIsFavorite(_ isFavorite: Bool) -> Self {
            var copy = self
            copy.isFavorite = isFavorite
            return copy
        }
    }
}
