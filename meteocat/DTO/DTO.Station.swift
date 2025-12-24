//
//  Station.swift
//  meteocat
//
//  Created by albert vila on 23/2/25.
//

import Foundation

typealias Stations = [String: DTO.Station]

extension DTO {
    
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
        let isFavorite: Bool
        
        init(
            code: String,
            name: String,
            type: String,
            isFavorite: Bool = false
        ) {
            self.code = code
            self.name = name
            self.type = type
            self.coordinates = .init(latitude: 0, longitude: 0)
            self.emplacament = ""
            self.altitude = 0
            self.city = City(codi: "", nom: "", slug: "", coordenades: Coordinates(latitude: 0, longitude: 0), comarca: "")
            self.region = Region(codi: 0, nom: "")
            self.states = []
            self.isFavorite = isFavorite
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.code = try container.decode(String.self, forKey: .code)
            self.name = try container.decode(String.self, forKey: .name).firstLetterUppercased
            self.type = try container.decode(String.self, forKey: .type)
            self.coordinates = try container.decode(Station.Coordinates.self, forKey: .coordinates)
            self.emplacament = try container.decode(String.self, forKey: .emplacament)
            self.altitude = try container.decode(Double.self, forKey: .altitude)
            self.city = try container.decode(Station.City.self, forKey: .city)
            self.region = try container.decode(Station.Region.self, forKey: .region)
            self.states = try container.decode([Station.State].self, forKey: .states)
            self.isFavorite = false
        }
        
        func copy(isFavorite: Bool) -> Self {
            Station(code: code, name: name, type: type, isFavorite: isFavorite)
        }
        
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
        
        struct Coordinates: Decodable, Hashable {
            let latitude: Double
            let longitude: Double
            
            enum CodingKeys: String, CodingKey {
                case latitude = "latitud"
                case longitude = "longitud"
            }
        }
        
        struct City: Decodable, Hashable {
            let codi: String
            let nom: String
            let slug: String?
            let coordenades: Coordinates?
            let comarca: String?
        }
        
        struct Region: Decodable, Hashable {
            let codi: Int
            let nom: String
        }
        
        struct State: Decodable, Hashable {
            let codi: Int
            let dataInici: String
            let dataFi: String?
        }
    }
}
