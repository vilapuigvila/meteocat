//
//  meteocatApp.swift
//  meteocat
//
//  Created by albert vila on 31/10/24.
//

import SwiftUI
import Alfy
import SDWebImage
import SDWebImageSVGCoder

@main
struct meteocatApp: App {
    /*var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Model.Station.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()*/
    
    init() {
        let svgCoder = SDImageSVGCoder.shared
        SDImageCodersManager.shared.addCoder(svgCoder)
    }
    
    var body: some Scene {
        WindowGroup {
            TabBarView()
        }
//        .modelContainer(sharedModelContainer)
    }
}
