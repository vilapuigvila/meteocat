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
    final class HomeStation {
        /*
         struct HomeStation: Decodable, Hashable {
             let name: String
             let key: String
             let value: String
             let date: String?
         }
         */
        
        struct Values: Equatable, Codable {
            let name: String
            let key: String
            let value: String
            let date: String?
            
            init(name: String, key: String, value: String, date: String?) {
                self.name = name
                self.key = key
                self.value = value
                self.date = date
            }
        }

        private(set)var values: [Values]
        private(set)var lastUpdated: TimeInterval
        
        init (values: [Values], lastUpdated: TimeInterval) {
            self.values = values
            self.lastUpdated = lastUpdated
        }
        
//        func asStationsDTO() -> [DTO.Station] {
//            values.map { DTO.Station(code: $0.code, name: $0.name, type: $0.type) }
//        }
    }
}
