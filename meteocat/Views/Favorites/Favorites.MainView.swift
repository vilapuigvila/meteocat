//
//  Favorites.MainView.swift
//  meteocat
//
//  Created by albert vila on 27/2/25.
//

import Foundation
import SwiftUI

struct FavoritesView: View {
    
    @ObservedObject var viewModel: FavoritesViewModel
    
    var body: some View {
        Favorites.MainView(state: viewModel.stateView) {
            viewModel.action($0)
        }
    }
}

extension Favorites {
    
    struct MainView: View {
        
        let state: Favorites.ViewState
        let action: (Favorites.Action) -> Void
        
        @State private var selectedItem: Favorites.Representable?
        @State private var isPresentedSheet = false
        @State private var currentDetent = PresentationDetent.large
        
        private let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible())
        ]
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(state.result) { item in
                            buildCardView(item)
                                .onTapGesture {
                                    selectedItem = item
                                }
                        }
                    }
                    .padding()
                }
                .navigationTitle("Favorites")
                .onAppear {
                    action(.onAppear)
                }
                .onChange(of: selectedItem) { _, newValue in
                    guard newValue != nil else {
                        return
                    }
                    isPresentedSheet = true
                }
                .sheet(isPresented: $isPresentedSheet, onDismiss: {
                    selectedItem = nil
                }) {
                    if let selectedItem {
                        let viewModel = HomeStationViewModel(
                            stationName: selectedItem.name,
                            interactor: HomeStationInteractorImpl(
                                source: .detailStation(code: selectedItem.stationCode),
                                databaseManager: .shared
                            )
                        )
                        FavoriteDetailView(viewModel: viewModel)
//                            .presentationDetents([.medium, .fraction(0.8), .height(200)], selection: $currentDetent)
                            .presentationDetents([.medium, .large])
                            .interactiveDismissDisabled(false)
                    }
                }
                .background(Color.black)
            }
        }
        
        private func buildCardView(_ item: Favorites.Representable) -> some View {
            VStack( alignment: .leading, spacing: 12) {
                Text(item.name)
                    .font(.custom("Poppins-Bold", size: 19))
                    .foregroundStyle(.white.opacity(0.925))
                    .bold()
                    .lineLimit(1)
                
                HStack {
                    Text("Max: " + item.maxTemp)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .font(.custom("Poppins-Bold", size: 12))
                        .foregroundStyle(.red)
                    Spacer()
                    Text("Min: " + item.minTemp)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .font(.custom("Poppins-Bold", size: 12))
                        .foregroundStyle(.mint.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .padding(.horizontal, 12)
            .background(Color.blue.opacity(0.3))
            .cornerRadius(8)
        }
    }
}

#Preview {
     var mockviewModel: Favorites.ViewState {
        .loaded([
            Favorites.Representable(name: "Castellar de N'Hug", maxTemp: "19.1 C", minTemp: "10.12121321 C", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "St. Llorenç de Morunys", maxTemp: "19.1 C", minTemp: "10.1 C", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Vallter 2000", maxTemp: "23.1324353453435454 C", minTemp: "21.1123454545 C",stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Vic", maxTemp: "19.1 C", minTemp: "10.1 C", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Barcelona", maxTemp: "19.1 C", minTemp: "10.1 C", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Banyoles", maxTemp: "19.1 C", minTemp: "10.1 C", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Cadaqués", maxTemp: "19.1 C", minTemp: "10.1 C", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Olot", maxTemp: "19.145644564446 C", minTemp: "10.1 C", stationCode: "", isFAvorite: false),
        ])
    }
    return Favorites.MainView(state: mockviewModel) { _ in
        
    }
}
