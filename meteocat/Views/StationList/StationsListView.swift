//
//  StationsListView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI

struct StationsContentView: View {
    @StateObject private var viewModel: StationsViewModel = .empty
    
    @State private var selectedStation: Station?
    @State private var isPresentedDetail = false
    
    var body: some View {
        NavigationStack {
            StationsListView(
                viewModel,
                selectedStation: $selectedStation,
                isPresentedDetail: $isPresentedDetail
            )
            .navigationDestination(isPresented: $isPresentedDetail) {
                if let selectedStation {
                    buildDetailView(stationCode: selectedStation.code, stationName: selectedStation.name)
                } else {
                    Text("Something went wrong")
                }
            }
        }
    }
    
    private func buildDetailView(stationCode: String, stationName: String) -> some View {
        HomeStationView(
            viewModel: HomeStationViewModel(
                stationName: stationName,
                interactor: HomeStationInteractorImpl(source: .detailStation(code: stationCode))
            )
        )
    }
}

struct StationsListView: View {
    @State var viewModel: StationsViewModel = .empty
    
    @Binding var selectedStation: Station?
    @Binding var isPresentedDetail: Bool
    
    private let columns = [GridItem(.flexible())]
    
    init(_ viewModel: StationsViewModel, selectedStation: Binding<Station?>, isPresentedDetail: Binding<Bool>) {
        self.viewModel = viewModel
        _selectedStation = selectedStation
        _isPresentedDetail = isPresentedDetail
    }
    
    var body: some View {
        buildNavigationStackView()
            .task {
                await requestStations()
            }
    }
        
    private func buildNavigationStackView() -> some View {
//        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.representable.stations, id: \.self) { item in
                        buildRowView(item)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 24)
            .navigationTitle("Estacions")
//            .navigationDestination(isPresented: $isPresentedDetail) {
//                if let selectedStation {
//                    buildDetailView(stationCode: selectedStation.code, stationName: selectedStation.name)
//                } else {
//                    Text("Something went wrong")
//                }
//            }
//        }
    }
    
    private func buildRowView(_ item: Station) -> some View {
        Button(action: {
//            UserSettings.homeStation = Preference.HomeStation(name: item.name, code: item.code)
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

    private func requestStations() async {
        var stations = await Requester.fetchStations()
        stations = stations.sorted { $0.name < $1.name }
        viewModel = StationsViewModel(representable: StationsViewModel.Representable(stations: stations))
    }
    
    private func buildDetailView(stationCode: String, stationName: String) -> some View {
        HomeStationView(
            viewModel: HomeStationViewModel(
                stationName: stationName,
                interactor: HomeStationInteractorImpl(source: .detailStation(code: stationCode))
            )
        )
    }
}

final class StationsViewModel: ObservableObject {
    struct Representable: Hashable {
        let stations: [Station]
        
        static let empty: Representable = .init(stations: [])
    }
    
    @Published private(set) var representable: Representable
    
    static let empty: StationsViewModel = .init(representable: .empty)
    
    init(representable: Representable) {
        self.representable = representable
    }
}

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
    let mockViewModel: StationsViewModel = .init(representable: .init(stations: stationsMock))
    
    StationsListView(mockViewModel, selectedStation: .constant(nil), isPresentedDetail: .constant(false))
}
