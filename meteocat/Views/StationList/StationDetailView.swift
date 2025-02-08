//
//  StationDetailView.swift
//  meteocat
//
//  Created by albert vila on 6/2/25.
//

import SwiftUI

struct StationDetaiView: View {
    @ObservedObject var viewModel: HomeStationViewModel
    
    let code: String
    
    var body: some View {
        HomeStation.MainView(stationName: "unimplemented", state: viewModel.state) {
            viewModel.action($0)
        }
    }
}
