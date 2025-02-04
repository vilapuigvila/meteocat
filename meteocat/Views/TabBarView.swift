//
//  TabBarView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI

struct TabBarView: View {
    var body: some View {
        TabView {
            HomeStationView(code: "CC", stationName: "Orís")
                .tabItem {
                    Image(systemName: "thermometer.variable.and.figure.circle.fill")
                    Text("My Station")
                }
            
            StationsListView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Stations")
                }
        }
    }
}

#Preview {
    TabBarView()
}
