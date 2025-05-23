//
//  FavoriteDetailView.swift
//  meteocat
//
//  Created by albert vila on 27/2/25.
//

import Foundation
import SwiftUI

struct FavoriteDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var viewModel: HomeStationViewModel
    
    var body: some View {
        ZStack {
            HomeStation.MainView(source: .modal, state: viewModel.stateView) {
                viewModel.action($0)
            }
        }
    }
}
