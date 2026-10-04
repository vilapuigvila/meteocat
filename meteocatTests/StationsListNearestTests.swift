import XCTest
@testable import meteocat

/// The Stations tab offers the closest station when the suggester finds one. No location, no network: fakes only.
@MainActor
final class StationsListNearestTests: XCTestCase {

    private struct FakeSuggester: NearestStationSuggesting {
        let result: NearestStation.Suggestion?
        func suggestion() async -> NearestStation.Suggestion? { result }
    }

    private let oris = NearestStation.Suggestion(code: "CC", name: "Orís", codeCity: "081509", distanceKm: 1.2)

    private func makeViewModel(_ suggester: NearestStationSuggesting?) -> StationsListViewModel {
        StationsListViewModel(interactor: MockStationsListInteractor(), nearestStationSuggester: suggester)
    }

    func testNearestIsPublishedOnAppear() async throws {
        let viewModel = makeViewModel(FakeSuggester(result: oris))
        XCTAssertNil(viewModel.nearest)

        viewModel.action(.onAppear)
        try await waitUntil { viewModel.nearest != nil }

        XCTAssertEqual(viewModel.nearest, oris)
    }

    func testNoSuggestionLeavesNearestEmpty() async throws {
        let viewModel = makeViewModel(FakeSuggester(result: nil))

        viewModel.action(.onAppear)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(viewModel.nearest)
    }

    func testWithoutSuggesterThereIsNoNearest() async throws {
        let viewModel = makeViewModel(nil)

        viewModel.action(.onAppear)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(viewModel.nearest)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met in \(timeout)s") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
