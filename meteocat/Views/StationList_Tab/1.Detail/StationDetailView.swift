//
//  StationDetailView.swift
//  meteocat
//
//  Created by albert vila on 6/2/25.
//

import SwiftUI
import SwiftData

fileprivate final class FavoriteState: ObservableObject {
    @Published var isFavorite: Bool
    
    init(isFavorite: Bool = false) {
        self.isFavorite = isFavorite
    }
}

struct StationDetaiView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFavoriteState: Bool = false
    
    @StateObject var viewModel: HomeStationViewModel
    
    init(viewModel: HomeStationViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        HomeStation.MainView(source: .detail, state: viewModel.stateView) {
            viewModel.action($0)
        }
    }
    var isFavorite: Bool {
        viewModel.stateView.representable?.isFavorite ?? false
    }
}

#if DEBUG
import Combine

private extension HomeStationStateDomain {
    static var empty: Self {
        .idle
    }
}
private struct InteractorMock: HomeStationInteractorProtocol {
    var domain: HomeStationStateDomain {
        subject.value
    }
    let subject = CurrentValueSubject<HomeStationStateDomain, Never>(.empty)
    var publisher: AnyPublisher<HomeStationStateDomain, Never> {
        subject.eraseToAnyPublisher()
    }
    
    func useCase(_ useCase: HomeStationInteractorImpl.UseCase) {
        switch useCase {
        case .requestStation:
            subject.send(
                .loaded(
                    dto: [DTO.HomeStation(name: "Vic", key: "Temp Max", value: "10 C", time: nil, isFavorite: true),
                         DTO.HomeStation(name: "Vic", key: "Temp Min", value: "2 C", time: nil, isFavorite: true),
                         DTO.HomeStation(name: "Vic", key: "Temp Mitjana", value: "10.2 C", time: nil, isFavorite: true),
                         DTO.HomeStation(name: "Vic", key: "Pluja", value: "0.0 mm", time: nil, isFavorite: true)],
                    stationCode: "",
                    cityCode: "",
                    isHome: false,
                    monthInfo: [],
                    summary: .init(averageTemp: 12.3, accumulatedRain: 34, firstDate: 0, lastDate: 0)
                )
            )
//            subject.send(.loading)
        case .addToFavs:
            break
        case .addAsHome:
            break
        case .cancelRequestStation:
            break
        }
    }
}

#Preview {
    let vm = HomeStationViewModel(
        stationName: "CC",
        interactor: InteractorMock()
    )
    StationDetaiView(/*stationCode: "",*/ viewModel: vm)
}
#endif
