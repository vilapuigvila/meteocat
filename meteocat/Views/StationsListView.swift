//
//  StationsListView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI

struct StationsListView: View {
    
    @State var viewModel: StationsViewModel = .empty
    
    let columns = [GridItem(.flexible())]
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                Spacer()
//                Text("Items List")
//                    .font(.title2)
//                    .fontWeight(.bold)
//                    .padding(.horizontal)
//                    .padding(.top, 16)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.representable.stations, id: \.self) { item in
                            NavigationLink(destination: buildDetailView(stationCode: item.codi, stationName: item.nom)) {
                                HStack {
                                    Text(item.nom)
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                }
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                                .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Stations")
        }
        .task {
            await requestStations()
        }
    }
    
    private func requestStations() async {
        var stations = await Requester.fetchStations()
        stations = stations.sorted { $0.nom < $1.nom }
        viewModel = StationsViewModel(representable: StationsViewModel.Representable(stations: stations))
    }
    
    private func buildDetailView(stationCode: String, stationName: String) -> some View {
        HomeStationView(code: stationCode, stationName: stationName)
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
    StationsListView()
}
