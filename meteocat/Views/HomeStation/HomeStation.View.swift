//
//  HomeStationView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI
import Combine

struct HomeStationView: View {
    
    @ObservedObject var viewModel: HomeStationViewModel
    
    var body: some View {
        HomeStation.MainView(stationName: viewModel.stationName, state: viewModel.state) {
            viewModel.action($0)
        }
    }
}

extension HomeStation {
    
    struct MainView: View /*, DecoupledView*/ {
        
        @Environment(\.scenePhase) private var scenePhase
        
        @State private var selectedDate = Date()
        @State private var isDatePickerVisible = true
        @State private var isLoading = false
        
        let stationName: String?
        let state: HomeStation.ViewState
        let action: (HomeStation.Action) -> Void
        
        var body: some View {
            Group {
                if case .error(let errorView) = state {
                    switch errorView {
                    case .missingStationCode:
                        Text("Please select a station from the list.")
                    case .networkFailure:
                        Text("Network Error")
                    }
                } else {
                    VStack {
                        List {
                            Section(header: buildHeaderView()) {
                                ForEach(state.result, id: \.self) { item in
                                    VStack(spacing: 8) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text("\(item.key)")
                                            Spacer()
                                            Text("\(item.value)")
                                        }
                                        if let date = item.date {
                                            HStack {
                                                Spacer()
                                                Text(date)
                                                    .font(.custom("Poppins-Bold", size: 12))
                                                    .foregroundStyle(.gray)
                                            }
                                        }
                                    }
                                    .padding([.top, .bottom], 12)
                                }
                            }
                        }
                        .listRowSeparator(.visible)
                    }
                }
            }
            .onAppear {
                action(.onAppear)
            }
            .onDisappear {
                action(.onDisappear)
            }
            .onChange(of: selectedDate) { oldValue, newValue in
                guard oldValue != newValue else { return assertionFailure() }
                action(.request(date: newValue))
            }
            .onChange(of: state) { _, newValue in
                withAnimation { isLoading = newValue == .loading }
            }
            .onReceive(
                Publishers.Merge(
                    NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification),
                    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            )) { notification in
                switch notification.name {
                case UIApplication.didEnterBackgroundNotification:
                    action(.onDisappear)
                case UIApplication.willEnterForegroundNotification:
                    selectedDate = Date()
                    action(.request(date: selectedDate))
                default:
                    assertionFailure("not implemented")
                    break
                }
            }
        }
        
        @State private var scale: CGFloat = 1.0
        private func buildHeaderView() -> some View {
            VStack {
                VStack(alignment: .center) {
                    Text(state.result.first?.name ?? "--")
                        .font(.custom("san francisco display", size: 28))
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    Text(selectedDate.formatted(date: .abbreviated, time: .standard))
                        .font(.custom("Poppins-Bold", size: 14))
                }
                .padding(.bottom, 16)

                DatePicker(
                    "Select Date",
                    selection: $selectedDate, in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(CompactDatePickerStyle())
                .padding(.bottom, 20)
                .id(selectedDate.timeIntervalSince1970)
                
                SafariProgressBar(isLoading: $isLoading)
                    .frame(height: 4)
            }
        }
    }
}


//#Preview {
//    HomeStation.MainView(code: "CC", stationName: "Orís") { _ in  }
//}
