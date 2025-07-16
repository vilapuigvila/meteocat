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
                                cityCode: selectedStation.city.codi,
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
        
        private func buildDetailView(stationCode: String, cityCode: String, stationName: String) -> some View {
            let viewModel = HomeStationViewModel(
                stationName: stationName,
                interactor: HomeStationInteractorImpl(
                    source: .detailStation(code: stationCode, cityCode: cityCode),
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

// MARK: - Preview -

import Combine

// ——————————————————————————————————————————————————————————————————————
// 1. Mock implementation of StationsListInteractorProtocol
// ——————————————————————————————————————————————————————————————————————

final class MockStationsListInteractor: StationsListInteractorProtocol {
    
    /// Internal subject that drives `publisher` and `domain`.
    private let subject: CurrentValueSubject<StationsListDomain, Never>
    private var cancellables = Set<AnyCancellable>()
    
    /// Expose the current value of the subject.
    var domain: StationsListDomain { subject.value }
    
    /// Conform to protocol by erasing to AnyPublisher.
    var publisher: AnyPublisher<StationsListDomain, Never> {
        subject
            .receive(on: DispatchQueue.main) // match real interactor’s receive(on:)
            .eraseToAnyPublisher()
    }
    
    /// Decide how the mock will respond when `useCase(_:)` is called.
    enum ResponseBehavior {
        /// Do nothing (keep emitting only `initialDomain`).
        case idle
        /// On `.requestStations`, first emit `isLoading = true`, then immediately emit a `.loaded`‐style domain.
        case simulateLoad(initialData: [DTO.Station])
        /// On `.pullToRefresh`, emit a “refreshed” version of the data (for example, with `isLoading = true` → new list).
        case simulateRefresh(oldData: [DTO.Station], newData: [DTO.Station])
        /// On `.requestStations`, emit an error (empty list) after showing loading.
        case simulateEmptyAfterLoad
    }
    
    private let behavior: ResponseBehavior
    
    /// - Parameters:
    ///   - initialDomain:  The domain state that the mock starts with and continuously publishes until a `useCase` is invoked.
    ///   - behavior:       Dictates what happens when `useCase(.requestStations)` or `.pullToRefresh` is called.
    init(
        initialDomain: StationsListDomain = .empty,
        behavior: ResponseBehavior = .idle
    ) {
        self.subject = .init(initialDomain)
        self.behavior = behavior
        
        // Keep `domain` in sync if someone subscribes to `publisher` then reads `domain`.
        subject
            .sink { _ in /* no-op; domain computed from subject.value */ }
            .store(in: &cancellables)
    }
    
    /// Conform to protocol. Depending on `behavior`, we push new values into the subject.
    func useCase(_ useCase: StationsListInteractorImpl.UseCase) {
        switch (useCase, behavior) {
            
        case (.requestStations, .idle):
            // Do nothing—stay at the initial domain
            break
            
        case (.requestStations, .simulateLoad(let initialData)):
            // 1) Emit “loading”
            subject.send(subject.value.copy(isLoading: true))
            // 2) Immediately emit “loaded” with provided data
            subject.send(StationsListDomain(list: initialData, isLoading: false))
            
        case (.requestStations, .simulateEmptyAfterLoad):
            // 1) Emit “loading”
            subject.send(subject.value.copy(isLoading: true))
            // 2) Emit “empty” (error case) after pretend‐loading
            subject.send(.empty)
            
        case (.pullToRefresh, .simulateRefresh(let oldData, let newData)):
            // 1) Emit “loading”
            subject.send(subject.value.copy(isLoading: true))
            // 2) Emit refreshed data
            subject.send(StationsListDomain(list: newData, isLoading: false))
            
        case (.cancelRequestStations, _):
            // Mimic “cancel”: just send whatever empty or previous state you like.
            subject.send(.empty)
            
        default:
            // covers any other combination (e.g. .pullToRefresh with behavior = .idle, etc.)
            break
        }
    }
}

// ——————————————————————————————————————————————————————————————————————
// 2. Example DTO.Station “stubs” and sample usage
// ——————————————————————————————————————————————————————————————————————

// MARK: – Sample “stations” you might pass into the mock

let mockStationsPage1: [DTO.Station] = [
    .init(code: "ST-001", name: "Alpha", type: "", isFavorite: false),
    .init(code: "ST-002", name: "Bravo", type: "", isFavorite: true),
    .init(code: "ST-003", name: "Charlie", type: "", isFavorite: false)
]

let mockStationsPage2: [DTO.Station] = [
    .init(code: "ST-004", name: "Delta", type: "", isFavorite: false),
    .init(code: "ST-005", name: "Echo", type: "", isFavorite: false)
]


// ——————————————————————————————————————————————————————————————————————
// 3. How to inject the mock into your ViewModel or SwiftUI Preview
// ——————————————————————————————————————————————————————————————————————

//
// Example: If your ViewModel looks like:
//   final class StationsListViewModel: ObservableObject {
//       init(interactor: StationsListInteractorProtocol) { … }
//       …
//   }
//
// You can now do:
//
let mockInteractor1 = MockStationsListInteractor(
    initialDomain: .empty,
    behavior: .simulateLoad(initialData: mockStationsPage1)
)

let viewModelUsingMock1 = StationsListViewModel(interactor: mockInteractor1)
// When your view calls viewModel.action(.onAppear), the mock will immediately send:
//   1) StationsListDomain(list: [], isLoading: true)
//   2) StationsListDomain(list: mockStationsPage1, isLoading: false)
//
  
//
// If you want to simulate “pull to refresh” returning new data:
//
let mockInteractor2 = MockStationsListInteractor(
    initialDomain: StationsListDomain(list: mockStationsPage1, isLoading: false),
    behavior: .simulateRefresh(oldData: mockStationsPage1, newData: mockStationsPage2)
)

let viewModelUsingMock2 = StationsListViewModel(interactor: mockInteractor2)
// When your view calls viewModel.action(.pullToRefresh), the mock will send:
//   1) isLoading = true (keeping the old list internally, if you want)
//   2) StationsListDomain(list: mockStationsPage2, isLoading: false)
//

//
// If you want to simulate an “empty list” error after requesting:
//
let mockInteractor3 = MockStationsListInteractor(
    initialDomain: .empty,
    behavior: .simulateEmptyAfterLoad
)

let viewModelUsingMock3 = StationsListViewModel(interactor: mockInteractor3)
// When your view calls viewModel.action(.onAppear), the mock emits:
//   1) isLoading = true
//   2) StationsListDomain(list: [], isLoading: false) → . So the VM’s state will become `.error(.emptyList)`
//   (because your VM maps `domain.list.isEmpty` → `.error(.emptyList)`).
//

#Preview {
    
    let stationsMock: [DTO.Station] = [
        .init(code: "CC", name: "Orís", type: "", isFavorite: false),
        .init(code: "CC", name: "Orís", type: "", isFavorite: false),
        .init(code: "CC", name: "Orís", type: "", isFavorite: false),
        .init(code: "CC", name: "Orís", type: "", isFavorite: false),
        .init(code: "CC", name: "Orís", type: "", isFavorite: false)
    ]
    let mockViewModel: StationsListViewModel = .init(
        interactor: MockStationsListInteractor(behavior: .simulateLoad(initialData: mockStationsPage1)))
    StationsList.ListView(mockViewModel, selectedStation: .constant(nil), isPresentedDetail: .constant(false))
}
