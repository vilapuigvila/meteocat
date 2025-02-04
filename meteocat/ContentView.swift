//
//  ContentView.swift
//  meteocat
//
//  Created by albert vila on 31/10/24.
//

import SwiftUI
import SwiftData
/*
struct ContentView: View {
//    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var viewModel: ViewModel = .init(reprsentable: [])
    @State private var selectedDate = Date()
    @State private var isDatePickerVisible = true
    
    var body: some View {
//        NavigationSplitView {
            List {
                Section(
                    header: VStack {
                        Text(selectedDate.formatted(date: .abbreviated, time: .complete))
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.bottom, 20)
//                        if isDatePickerVisible {
                            DatePicker(
                                "Select Date",
                                selection: $selectedDate, in: ...Date(),
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(CompactDatePickerStyle()) // Or you can use WheelDatePickerStyle()
                            .padding(.bottom, 20)
                            .id(selectedDate.timeIntervalSince1970)
//                        }
                    }
                ) {
                    ForEach(viewModel.reprsentable, id: \.self) { item in
                        HStack {
                            Text("\(item.key)")
                            Spacer()
                            Text("\(item.value)")
                            Spacer()
                            /*
                            if let date = item.date {
                                Text(date)
                            }*/
                        }
                        /*
                         NavigationLink {
                         Text("Item at \(item.key)")
                         //                        Text("Item at \(item.key, format: Date.FormatStyle(date: .numeric, time: .standard))")
                         } label: {
                         Text(item.value)
                         }*/
                    }
                }
            }
            .task {
                let stations = await Requester.fetchStations()
                do {
                    let model = try await Requester.requestOris()
                    viewModel = ViewModel(reprsentable: model, stations: )
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
        selectedDate = date
        Task {
            do {
                let model = try await Requester.requestOris(date: date)
                withAnimation {
                    viewModel = ViewModel(reprsentable: model, stations: viewModel.stations)
//                    isDatePickerVisible = true
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    /*
    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }*/
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
*/
