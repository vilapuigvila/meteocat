//
//  Model.HomeStation.swift
//  meteocat
//
//  Created by albert vila on 23/2/25.
//

import Foundation
import SwiftData

extension Model {
    
    @Model
    final class InfoStationByDate {
        struct Day: Equatable, Codable {
            let name: String
            let key: String
            let value: String
            let time: String?
            
            init(name: String, key: String, value: String, time: String?) {
                self.name = name
                self.key = key
                self.value = value
                self.time = time
            }
        }
        
        private(set)var values: [Day]
        private(set)var createdAt: TimeInterval
        private(set) var station: Station?
        
        init(values: [Day], createdAt: TimeInterval, station: Station) {
            self.values = values
            self.createdAt = createdAt
            self.station = station
        }
    }
}
