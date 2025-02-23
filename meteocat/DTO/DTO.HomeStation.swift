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
        let date: String?
    }
}
