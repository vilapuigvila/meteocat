//
//  Item.swift
//  meteocat
//
//  Created by albert vila on 31/10/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
