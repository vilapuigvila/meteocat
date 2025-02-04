//
//  HomeStationView.swift
//  meteocat
//
//  Created by albert vila on 4/2/25.
//

import SwiftUI

struct HomeStationView: View {
    
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var viewModel: HomeViewModel = .init(reprsentable: [], stationName: "...")
    @State private var selectedDate = Date()
    @State private var isDatePickerVisible = true
    @State private var isLoading = true
    
    let code: String
    let stationName: String
    
    var body: some View {
//        NavigationSplitView {
            List {
                Section(header: buildHeaderView()) {
                    ForEach(viewModel.reprsentable, id: \.self) { item in
                        HStack {
                            Text("\(item.key)")
                            Spacer()
                            Text("\(item.value)")
//                            Spacer()
                            
                            /*
                            if let date = item.date {
                                Text(date)
                            }*/
                        }
                    }
                    if isLoading {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .task {
                do {
                    let model = try await Requester.requestOris(code: code)
                    withAnimation {
                        isLoading = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation {
                            viewModel = HomeViewModel(reprsentable: model, stationName: stationName)
                        }
                    }
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
            .onChange(of: selectedDate) { oldValue, newValue in
                request(date: newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                request(date: Date())
            }
    }

    private func request(date: Date) {
        isLoading = true
        selectedDate = date
        Task {
            do {
                withAnimation {
                    isLoading = false
                }
                let model = try await Requester.requestOris(code: code, date: date)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation {
                        viewModel = HomeViewModel(reprsentable: model, stationName: stationName)
                    }
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    private func buildHeaderView() -> some View {
        VStack {
            VStack(alignment: .center) {
                Text(stationName)
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
        }
    }
}

#Preview {
    HomeStationView(code: "CC", stationName: "Orís")
}
