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
    final class StationsList {
        
        struct Values: Equatable, Codable {
            let code: String
            let name: String
            let type: String
            init(code: String, name: String, type: String) {
                self.code = code
                self.name = name
                self.type = type
            }
        }

        private(set)var stations: [Values]
        private(set)var lastUpdated: TimeInterval
        
        init (stations: [Values], lastUpdated: TimeInterval) {
            self.stations = stations
            self.lastUpdated = lastUpdated
        }
        
        func asStationsDTO() -> [DTO.Station] {
            stations.map { DTO.Station(code: $0.code, name: $0.name, type: $0.type) }
        }
    }
}
