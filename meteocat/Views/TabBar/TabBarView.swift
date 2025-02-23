//
//  TabBarView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI

struct TabBarView: View {
    
    private let databaseManager: DatabaseManagerProtocol = {
        DatabaseManager.makeShared([
            Model.StationsList.self
        ])
    }()
    
    init(homeStation: PREF.HomeStation? = nil) {
//        UserSettings.homeStation = nil
    }
    
    var body: some View {
        TabView {
            HomeStationView(
                viewModel: HomeStationViewModel(
                    stationName: nil,
                    interactor: HomeStationInteractorImpl(source: .homeStation)
                )
            )
            .tabItem {
                Image(systemName: "thermometer.variable.and.figure.circle.fill")
                Text("My Station")
            }
            
            StationsListView(
                viewModel: StationsListViewModel(
                    interactor: StationsListInteractorImpl(databaseManager: .shared)
                )
            )
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
