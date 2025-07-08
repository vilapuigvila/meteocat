//
//  TabBarView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI
import Alfy

struct TabBarView: View {
    
    private let databaseManager: DatabaseManagerProtocol = {
        DatabaseManager.makeShared([
            Model.Station.self, Model.InfoStationByDate.self
        ])
    }()
    private let stationsViewModel: StationsListViewModel
    private let forecastViewModel: Forecast.ViewModel<Forecast.InteractorImpl>
    private let homeViewModel: HomeStationViewModel
    private let favsViewModel: FavoritesViewModel
    
    init(homeStation: PREF.HomeStation? = nil) {
        /*
        let _infos = try? databaseManager.fetchItems(Model.InfoStationByDate.self, predicate: nil, sortBy: nil)
        print("avp [DB] 🚀 on App start total infos - \(_infos?.count ?? -99)")*/
        homeViewModel = HomeStationViewModel(
            stationName: nil,
            interactor: HomeStationInteractorImpl(source: .homeStation, databaseManager: DatabaseManager.shared)
        )
        stationsViewModel = StationsListViewModel(
            interactor: StationsListInteractorImpl(databaseManager: DatabaseManager.shared)
        )
        favsViewModel = FavoritesViewModel(interactor: FavoritesInteractorImpl(databaseManager: DatabaseManager.shared))
        
        forecastViewModel = Forecast.ViewModel(
            interactor: Forecast.InteractorImpl(databaseManager: databaseManager)
        )
    }
    
    var body: some View {
        TabView {
            ForecastView(
                viewModel: forecastViewModel
            )
            .tabItem {
                Image(systemName: "cloud.sun.bolt.circle")
                Text("Forecast")
            }
            
            HomeStationView(
                viewModel: homeViewModel
            )
            .tabItem {
                Image(systemName: "thermometer.variable.and.figure.circle.fill")
                Text("My Station")
            }
            
            StationsListView(
                viewModel: stationsViewModel
            )
            .tabItem {
                Image(systemName: "gearshape.fill")
                Text("Stations")
            }
            
            FavoritesView(
                viewModel: favsViewModel
            )
            .tabItem {
                Image(systemName: "heart.fill")
                Text("Favs")
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
