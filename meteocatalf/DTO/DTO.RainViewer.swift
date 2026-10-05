//
//  DTO.RainViewer.swift
//  meteocatalf
//

import Foundation

extension DTO {
    /// `https://api.rainviewer.com/public/weather-maps.json`: where the radar tiles are and which images exist.
    struct RainViewerMaps: Decodable, Hashable {
        struct Radar: Decodable, Hashable {
            let past: [Frame]
        }
        /// One radar image: when it was taken (Unix time) and the path of its tiles under `host`.
        struct Frame: Decodable, Hashable {
            let time: TimeInterval
            let path: String
        }
        let host: String
        let radar: Radar
    }
}
