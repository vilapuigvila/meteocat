//
//  StationDetailView.swift
//  meteocat
//
//  Created by albert vila on 6/2/25.
//

import SwiftUI

struct StationDetaiView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @ObservedObject var viewModel: HomeStationViewModel
    
    let action: () -> Void
    
    var body: some View {
        ZStack {
            HomeStation.MainView(stationName: "unimplemented", state: viewModel.state) {
                viewModel.action($0)
            }
            Button(action: action) {
                Image(systemName: "house.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: 24, height: 24)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: -16)
        }
    }
}

#Preview {
    let vm = HomeStationViewModel(stationName: "Oris", interactor: HomeStationInteractorImpl(source: .detailStation(code: "CC")))
    StationDetaiView(viewModel: vm) {
        
    }
}
