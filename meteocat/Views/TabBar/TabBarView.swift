//
//  TabBarView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI
import Alfy

struct TabBarView: View {
    @StateObject private var viewModel: TabBarViewModel
    
    init(homeStation: PREF.HomeStation? = nil) {
        _viewModel = StateObject(wrappedValue: TabBarViewModel(homeStation: homeStation))
    }
    
    var body: some View {
        TabView {
            /*
            ForecastView(
                viewModel: forecastViewModel
            )
            .tabItem {
                Image(systemName: "cloud.sun.bolt.circle")
                Text("Forecast")
            }*/
            
            HomeStationView(
                viewModel: viewModel.homeViewModel
            )
            .tabItem {
                Image(systemName: "thermometer.variable.and.figure.circle.fill")
                Text("My Station")
            }
            
            StationsListView(
                viewModel: viewModel.stationsViewModel
            )
            .tabItem {
                Image(systemName: "gearshape.fill")
                Text("Stations")
            }
            
            FavoritesView(
                viewModel: viewModel.favsViewModel
            )
            .tabItem {
                Image(systemName: "heart.fill")
                Text("Favs")
            }
        }
    }
}
/*
#Preview {
    TabBarView()
}*/
