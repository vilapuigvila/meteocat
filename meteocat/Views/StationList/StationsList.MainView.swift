//
//  StationsListView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI
import SwiftData
import Alfy

struct StationsListView: View {
    @ObservedObject private var viewModel: StationsListViewModel
    
    init(viewModel: StationsListViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        StationsList.MainView(viewModel: viewModel)
    }
}

extension StationsList {
    
    struct MainView: View {
        @StateObject var viewModel: StationsListViewModel
        
        @State private var selectedStation: DTO.Station?
        @State private var isPresentedDetail = false
        @State private var isPullToRefresh = false
//        @State private var path: [] = []

// "avp check it out ⚠️ -> .navigationTitle(Estacions) comes from top after pull to refresh"
        var body: some View {
            NavigationStack {
                if viewModel.state == .loading {
                    Text("loading")
                        .opacity(isPullToRefresh ? 1 : 0)
//                        .animation(.easeInOut(duration: 0.4), value: isPullToRefresh)
                } else {
                    ListView(
                        viewModel,
                        selectedStation: $selectedStation,
                        isPresentedDetail: $isPresentedDetail
                    )
                    .refreshable {
                        viewModel.action(.pullToRefresh)
                    }
                    .navigationTitle("Estacions")
                    .navigationDestination(isPresented: $isPresentedDetail) {
                        if let selectedStation {
                            buildDetailView(
                                stationCode: selectedStation.code,
                                stationName: selectedStation.name
                            )
                        } else {
                            Text("Something went wrong")
                        }
                    }
                }
            }.refreshable {
                viewModel.action(.pullToRefresh)
            }.onAppear {
                viewModel.action(.onAppear)
            }
            .onDisappear {
//                selectedStation = nil
                viewModel.action(.onDisappear)
            }
            .onChange(of: viewModel.state) {
                isPullToRefresh = viewModel.state == .loading
            }
        }
        
        private func buildDetailView(stationCode: String, stationName: String) -> some View {
            let viewModel = HomeStationViewModel(
                stationName: stationName,
                interactor: HomeStationInteractorImpl(
                    source: .detailStation(code: stationCode),
                    databaseManager: DatabaseManager.shared
                )
            )
            return StationDetaiView(/*stationCode: stationCode, */viewModel: viewModel)
        }
    }
    
    fileprivate struct ListView: View {
#warning("avp check it out ⚠️ -> move to representable")
        @State var viewModel: StationsListViewModel
        
        @Binding var selectedStation: DTO.Station?
        @Binding var isPresentedDetail: Bool
        
        private let columns = [GridItem(.flexible())]
        
        init(_ viewModel: StationsListViewModel, selectedStation: Binding<DTO.Station?>, isPresentedDetail: Binding<Bool>) {
            self.viewModel = viewModel
            _selectedStation = selectedStation
            _isPresentedDetail = isPresentedDetail
        }
        
        var body: some View {
            buildNavigationStackView()
        }
        
        private func buildNavigationStackView() -> some View {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.state.result.stations, id: \.self) { item in
                        buildRowView(item)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 24)
        }
        
        private func buildRowView(_ item: DTO.Station) -> some View {
            Button(action: {
                selectedStation = item
                isPresentedDetail = true
            }) {
                HStack {
                    Text(item.name)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .shadow(radius: 2)
            }
        }
        
        /*
        private func requestStations() async {
            var stations = await Requester.fetchStations()
            stations = stations.sorted { $0.name < $1.name }
            viewModel = StationsListViewModel(representable: StationsList.Representable(stations: stations))
        }*/
    }
}

/*
#Preview {
    let stationsMock: [Station] = [
        Station(
            code: "",
            name: "",
            type: "",
            coordinates: Station.Coordinates(latitude: 0, longitude: 0),
            emplacament: "",
            altitude: 0,
            city: Station.City(
                codi: "",
                nom: "",
                slug: "",
                coordenades: nil,
                comarca: nil
            ),
            region: Station.Region(
                codi: 0,
                nom: ""),
            states: []
        )
    ]
    let mockViewModel: StationsListViewModel = .init(representable: .init(stations: stationsMock))
    
    StationsList.ListView(mockViewModel, selectedStation: .constant(nil), isPresentedDetail: .constant(false))
}
*/
