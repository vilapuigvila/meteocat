//
//  Model.Station.swift
//  meteocat
//
//  Created by albert vila on 23/2/25.
//

import Foundation
import SwiftData

extension Model {
    
    @Model
    final class Station {
        var id: String { code }
        
        private(set) var code: String
        private(set) var name: String
        private(set) var type: String
        private(set)var lastUpdated: TimeInterval
        private(set)var isFavorite: Bool = false
        
        init(code: String, name: String, type: String, lastUpdated: TimeInterval) {
            self.code = code
            self.name = name
            self.type = type
            self.lastUpdated = lastUpdated
        }
        
        func movedToFavorite(_ value: Bool) {
            isFavorite = value
        }
    }
}
