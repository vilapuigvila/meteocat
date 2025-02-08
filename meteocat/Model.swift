//
//  Model.swift
//  meteocat
//
//  Created by albert vila on 5/2/25.
//

import Foundation
import SwiftData

typealias Stations = [String: Station]

//@Model
struct Station: Decodable, Hashable {
    let code: String
    let name: String
    let type: String
    let coordinates: Coordinates
    let emplacament: String
    let altitude: Double
    let city: City
    let region: Region
    let states: [State]
    
    enum CodingKeys: String, CodingKey {
        case code = "codi"
        case name = "nom"
        case type = "tipus"
        case coordinates = "coordenades"
        case emplacament = "emplacament"
        case altitude = "altitud"
        case city = "municipi"
        case region = "comarca"
        case states = "estats"
    }
    
//    @Model
    struct Coordinates: Decodable, Hashable {
        let latitude: Double
        let longitude: Double
        
        enum CodingKeys: String, CodingKey {
            case latitude = "latitud"
            case longitude = "longitud"
        }
    }
    
//    @Model
    struct City: Decodable, Hashable {
        let codi: String
        let nom: String
        let slug: String?
        let coordenades: Coordinates?
        let comarca: String?
    }
    
//    @Model
    struct Region: Decodable, Hashable {
        let codi: Int
        let nom: String
    }
    
//    @Model
    struct State: Decodable, Hashable {
        let codi: Int
        let dataInici: String
        let dataFi: String?
    }
}
