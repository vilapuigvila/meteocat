//
//  TabBarView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI

struct TabBarView: View {
    @UserDefault(UserPreferencesKey.homeStation.rawValue, defaultValue: nil)
    var homeStation: Preference.HomeStation?
    
    var body: some View {
        TabView {
            HomeStationView(
                viewModel: HomeStationViewModel(stationName: homeStation?.name, interactor: HomeStationInteractorImpl(source: .homeStation))
            )
            .tabItem {
                Image(systemName: "thermometer.variable.and.figure.circle.fill")
                Text("My Station")
            }
            StationsContentView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Stations")
                }
        }
        .onAppear {
            print(#function)
        }
    }
}
/*
#Preview {
    TabBarView()
}*/
