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
        /// When the values were downloaded. Decides if a day can still change (see `DayKey.needsRefresh`).
        private(set)var createdAt: TimeInterval
        private(set) var station: Station?
        /// The day these values belong to, as `DayKey.value` (yyyymmdd). One row per station and day.
        /// `0` marks rows stored before this field existed; they are purged at launch because
        /// their `createdAt` was the requested day, not the download time.
        private(set) var dayKey: Int = 0

        init(values: [Day], createdAt: TimeInterval, dayKey: Int, station: Station) {
            self.values = values
            self.createdAt = createdAt
            self.dayKey = dayKey
            self.station = station
        }
    }
}
