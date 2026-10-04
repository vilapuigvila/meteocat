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
        @State private var searchText = ""
//        @State private var path: [] = []

// "avp check it out ⚠️ -> .navigationTitle(Estacions) comes from top after pull to refresh"
        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    buildHeader()

                    if viewModel.state == .loading {
                        Text("loading")
                            .opacity(isPullToRefresh ? 1 : 0)
                            .padding(.top, 24)
                        Spacer(minLength: 0)
                    } else {
                        Group {
                            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, filteredStations.isEmpty {
                                ContentUnavailableView.search(text: searchText)
                            } else {
                                ListView(
                                    stations: filteredStations,
                                    nearest: isSearching ? nil : viewModel.nearest,
                                    selectedStation: $selectedStation,
                                    isPresentedDetail: $isPresentedDetail
                                )
                                .refreshable {
                                    viewModel.action(.pullToRefresh)
                                }
                            }
                        }
                    }
                }
                .background(Signal.paper.ignoresSafeArea())
                .navigationTitle("Estacions")
                .toolbar(.hidden, for: .navigationBar)
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
            .refreshable {
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

        private var isSearching: Bool {
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // MARK: Header

        private func buildHeader() -> some View {
            let total = viewModel.state.result.stations.count
            let shown = filteredStations.count
            return SignalHeader {
                SignalKicker(shown == total ? "\(total) stations" : "\(shown) of \(total)")
                    .frame(minHeight: 44, alignment: .leading)
                Text("Estacions")
                    .font(.system(size: 48, weight: .light))
                    .tracking(-1.4)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 4)
                buildSearchField()
                    .padding(.top, 16)
            }
        }

        private func buildSearchField() -> some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Signal.muted)
                TextField("Search stations", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Search stations")
                    .accessibilityIdentifier("stations.search")
                if isSearching {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .foregroundStyle(Signal.ink)
            .padding(.leading, 14)
            .frame(height: 48)
            .background(Signal.paper)
        }

        private var filteredStations: [DTO.Station] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return viewModel.state.result.stations }

            return viewModel.state.result.stations.filter { station in
                station.name.localizedStandardContains(query)
                || station.code.localizedStandardContains(query)
                || station.city.nom.localizedStandardContains(query)
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
        let stations: [DTO.Station]
        /// The operating station closest to the user, when the location is available.
        let nearest: NearestStation.Suggestion?
        
        @Binding var selectedStation: DTO.Station?
        @Binding var isPresentedDetail: Bool
        
        init(
            stations: [DTO.Station],
            nearest: NearestStation.Suggestion? = nil,
            selectedStation: Binding<DTO.Station?>,
            isPresentedDetail: Binding<Bool>
        ) {
            self.stations = stations
            self.nearest = nearest
            _selectedStation = selectedStation
            _isPresentedDetail = isPresentedDetail
        }
        
        var body: some View {
            buildNavigationStackView()
        }
        
        private func buildNavigationStackView() -> some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let nearest, let station = stations.first(where: { $0.code == nearest.code }) {
                        buildNearestCard(nearest, station: station)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                    }
                    ForEach(stations, id: \.code) { item in
                        buildRowView(item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }

        private func open(_ station: DTO.Station) {
            selectedStation = station
            isPresentedDetail = true
        }

        private func buildNearestCard(_ nearest: NearestStation.Suggestion, station: DTO.Station) -> some View {
            let distance = nearest.distanceKm.formatted(.number.precision(.fractionLength(1)))
            return Button {
                open(station)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.viewfinder")
                        .font(.title2)
                        .foregroundStyle(Signal.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nearest to you · \(distance) km")
                            .font(Signal.caption)
                            .textCase(.uppercase)
                            .tracking(1)
                            .foregroundStyle(Color(red: 1, green: 138.0 / 255, blue: 92.0 / 255))
                        Text(nearest.name)
                            .font(.system(.title3).weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 68)
                .background(Signal.onSignal)
                .overlay(Rectangle().stroke(Signal.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("stations.nearest")
        }
        
        private func buildRowView(_ item: DTO.Station) -> some View {
            // stations rebuilt from the database carry no state history: don't call them closed
            let isClosed = !item.states.isEmpty && !NearestStation.isOperating(item)
            return VStack(spacing: 0) {
                Button {
                    open(item)
                } label: {
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(isClosed ? Signal.muted.opacity(0.5) : Signal.orange)
                            .frame(width: 8, height: 8)
                        Text(item.name)
                            .font(.system(.body).weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if isClosed {
                            Text("closed")
                                .font(Signal.caption)
                                .foregroundStyle(Signal.muted)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stations.row.\(item.code)")
                SignalRule()
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
    let mockViewModel: StationsListViewModel = .init(
        interactor: MockStationsListInteractor(behavior: .simulateLoad(initialData: mockStationsPage1)))
    StationsList.MainView(viewModel: mockViewModel)
}
