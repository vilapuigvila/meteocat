//
//  Favorites.MainView.swift
//  meteocat
//
//  Created by albert vila on 27/2/25.
//

import Foundation
import SwiftUI
import Alfy

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
            ZStack {
                if case .idle = state {
                    EmptyView()
                      .transition(.opacity)
                }
                if case .error(let error) = state {
                    switch error {
                    case .networkFailure:
                        NetworkFailureErrorView()
                            .transition(.opacity)
                    case .empty:
                        MissingStationErrorView()
                            .transition(.opacity)
                    }
                }
                if case .loading = state {
                    WeatherLoader()
                }
                if case .loaded(let representable) = state {
                    NavigationStack {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(representable) { item in
                                    buildCardView(item)
                                        .transition( .opacity)
                                        .animation(.easeOut(duration: 0.5), value: state.result)
                                        .onTapGesture {
                                            selectedItem = item
                                        }
                                }
                            }
                            .padding()
                        }
                        .navigationTitle("Favorites")
                        .onChange(of: selectedItem) { _, newValue in
                            guard newValue != nil else {
                                return
                            }
                            isPresentedSheet = true
                        }
                        .sheet(isPresented: $isPresentedSheet, onDismiss: {
                            selectedItem = nil
                            action(.onAppear)
                        }) {
                            if let selectedItem {
                                let viewModel = HomeStationViewModel(
                                    stationName: selectedItem.name,
                                    interactor: HomeStationInteractorImpl(
                                        source: .detailStation(code: selectedItem.stationCode, cityCode: ""),
                                        databaseManager: DatabaseManager.shared
                                    )
                                )
                                FavoriteDetailView(viewModel: viewModel)
 //                            .presentationDetents([.medium, .fraction(0.8), .height(200)], selection: $currentDetent)
                                    .presentationDetents([.medium, .large])
                                    .interactiveDismissDisabled(false)
                            }
                        }
                    }
                    
                }
            }
            .animation(.easeInOut(duration: 0.5), value: state)
            .background(Color.black)
            .onAppear {
                action(.onAppear)
            }
        }
        
        private func buildCardView(_ item: Favorites.Representable) -> some View {
            Favorites.CardView(item: item)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.blue.opacity(0.3))
                .cornerRadius(8)
        }
    }
}

#Preview {
     var mockviewModel: Favorites.ViewState {
        .loaded([
            Favorites.Representable(name: "Castellar de N'Hug", maxTemp: "19.1 C", minTemp: "10.12121321 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "St. Llorenç de Morunys", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Vallter 2000", maxTemp: "23.1324353453435454 C", minTemp: "21.1123454545 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Vic", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Barcelona", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Banyoles", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Cadaqués", maxTemp: "19.1 C", minTemp: "10.1 C", rainAcc: "12 mm", stationCode: "", isFAvorite: false),
            Favorites.Representable(name: "Olot", maxTemp: "19.145644564446 C", minTemp: "10.1 C", rainAcc: "--", stationCode: "", isFAvorite: false),
        ])
    }
    return Favorites.MainView(state: mockviewModel) { _ in
        
    }
}

extension Favorites {
    
    struct CardView: View {
        let item: Favorites.Representable
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.name)
                    .font(.custom("Poppins-Bold", size: 19))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.925))
                    .bold()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cloud.rain")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.blue)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Group {
                                    if item.rainAcc == "--" {
                                        GeometryReader { geo in
                                            Path { path in
                                                path.move(to: CGPoint(x: 0, y: geo.size.height))
                                                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                                            }
                                            .stroke(Color.red.opacity(0.8), lineWidth: 1.5)
                                        }
                                    }
                                }
                            )
                        Text(item.rainAcc)
                            .lineLimit(1)
                            .font(.custom("Poppins-Bold", size: 12))
                            .foregroundStyle(
                                item.rainAcc == "--"
                                  ? Color.red.opacity(0.8)
                                  : Color.teal.opacity(0.9)
                            )
                    }
                    
                    HStack {
                        Text(item.maxTemp)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .font(.custom("Poppins-Bold", size: 12))
                            .foregroundStyle(.red)
                        
                        Spacer()
                        
                        Text(item.minTemp)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .font(.custom("Poppins-Bold", size: 12))
                            .foregroundStyle(.mint.opacity(0.9))
                    }
                }
            }
        }
    }
}

