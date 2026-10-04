import XCTest
import Combine
@testable import meteocat

final class HomeStationViewModelTests: XCTestCase {

    private final class InteractorStub: HomeStationInteractorProtocol {
        let subject: CurrentValueSubject<HomeStationStateDomain, Never>
        var domain: HomeStationStateDomain { subject.value }
        var publisher: AnyPublisher<HomeStationStateDomain, Never> { subject.eraseToAnyPublisher() }
        init(_ state: HomeStationStateDomain) { subject = .init(state) }
        func useCase(_ useCase: HomeStationInteractorImpl.UseCase) {}
    }

    func testTilesShowUnitsAndMissingDays() {
        let summary = StationDayInfoSummary(averageTemp: 14.4, accumulatedRain: 45.6, daysWithData: 3, daysExpected: 4)
        let viewModel = HomeStationViewModel(
            stationName: nil,
            interactor: InteractorStub(.loaded(
                dto: [.init(name: "Orís", key: "Temperatura mitjana", value: "17.0 °C", time: nil)],
                stationCode: "CC", cityCode: "1", isHome: true, monthInfo: [], summary: summary
            ))
        )
        // the view model hops to the main queue before publishing
        let loaded = expectation(description: "loaded")
        var representable: HomeStation.Representable?
        let cancellable = viewModel.$stateView.sink {
            guard let value = $0.representable else { return }
            representable = value
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 2)
        cancellable.cancel()

        XCTAssertEqual(representable?.averageTemp, "14.4 °C")
        XCTAssertEqual(representable?.accumulatedRain, "45.6 mm")
        XCTAssertEqual(representable?.missingDays, 1)
    }

    func testNoDataIsItsOwnErrorNotANetworkFailure() {
        XCTAssertEqual(HomeStation.ErrorView(stationInteractorError: .noData), .noData)
        XCTAssertEqual(HomeStation.ErrorView(stationInteractorError: .noInternetConnection), .networkFailure)
    }

    func testNewMonthValuesKeepTheRestOfTheState() {
        let before = HomeStationStateDomain.loaded(
            dto: [.init(name: "Orís", key: "k", value: "v", time: nil, isFavorite: true)],
            stationCode: "CC", cityCode: "1", isHome: true, monthInfo: [], summary: .empty
        )
        let summary = StationDayInfoSummary(averageTemp: 1, accumulatedRain: 2, daysWithData: 1, daysExpected: 1)
        let after = before.withMonth([], summary: summary)

        XCTAssertEqual(after.summuary, summary)
        XCTAssertTrue(after.isFavorite)
        XCTAssertTrue(after.isHome)
        XCTAssertEqual(after.stationCode, "CC")
        XCTAssertEqual(HomeStationStateDomain.loading.withMonth([], summary: summary), .loading)
    }
}
