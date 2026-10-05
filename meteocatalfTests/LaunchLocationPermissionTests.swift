import XCTest
import CoreLocation
@testable import meteocatalf

@MainActor
final class LaunchLocationPermissionTests: XCTestCase {

    private final class RequesterFake: LocationPermissionRequesting {
        var authorizationStatus: CLAuthorizationStatus
        private(set) var requestCount = 0
        init(_ status: CLAuthorizationStatus) { authorizationStatus = status }
        func requestWhenInUseAuthorization() { requestCount += 1 }
    }

    /// Counts the stations calls, no network involved.
    private final class StationsFake {
        private(set) var callCount = 0
        let result: Bool
        init(result: Bool) { self.result = result }
        func ensure() async -> Bool {
            callCount += 1
            return result
        }
    }

    private func makeSUT(
        stations: StationsFake,
        requester: RequesterFake,
        isAppActive: @escaping () -> Bool = { true }
    ) -> LaunchLocationPermission {
        LaunchLocationPermission(
            ensureStations: { await stations.ensure() },
            requester: requester,
            isAppActive: isAppActive
        )
    }

    // the stations call answers `true` both when the list comes from the database and when it is fetched
    // (the database case is covered in StationsListEnsureStationsTests)
    func testStationsAvailableAndNeverAskedAsksForPermission() async {
        let stations = StationsFake(result: true)
        let requester = RequesterFake(.notDetermined)
        await makeSUT(stations: stations, requester: requester).run()

        XCTAssertEqual(stations.callCount, 1)
        XCTAssertEqual(requester.requestCount, 1)
    }

    func testFetchFailsDoesNotAsk() async {
        let stations = StationsFake(result: false)
        let requester = RequesterFake(.notDetermined)
        await makeSUT(stations: stations, requester: requester).run()

        XCTAssertEqual(stations.callCount, 1)
        XCTAssertEqual(requester.requestCount, 0)
    }

    func testAlreadyAnsweredDoesNotAsk() async {
        for status: CLAuthorizationStatus in [.authorizedWhenInUse, .authorizedAlways, .denied, .restricted] {
            let requester = RequesterFake(status)
            await makeSUT(stations: StationsFake(result: true), requester: requester).run()
            XCTAssertEqual(requester.requestCount, 0, "status \(status.rawValue)")
        }
    }

    func testAsksAtMostOncePerLaunchWhenCalledTwice() async {
        let stations = StationsFake(result: true)
        let requester = RequesterFake(.notDetermined)
        let sut = makeSUT(stations: stations, requester: requester)
        await sut.run()
        await sut.run()

        XCTAssertEqual(requester.requestCount, 1)
        XCTAssertEqual(stations.callCount, 1)
    }

    func testConcurrentCallsAskOnce() async {
        let stations = StationsFake(result: true)
        let requester = RequesterFake(.notDetermined)
        let sut = makeSUT(stations: stations, requester: requester)
        async let first: Void = sut.run()
        async let second: Void = sut.run()
        _ = await (first, second)

        XCTAssertEqual(requester.requestCount, 1)
    }

    func testFailedFetchIsNotRetriedInTheSameLaunch() async {
        let stations = StationsFake(result: false)
        let requester = RequesterFake(.notDetermined)
        let sut = makeSUT(stations: stations, requester: requester)
        await sut.run()
        await sut.run()

        XCTAssertEqual(stations.callCount, 1)
        XCTAssertEqual(requester.requestCount, 0)
    }

    func testWaitsForTheAppToBeActiveBeforeAsking() async {
        var isActive = false
        let requester = RequesterFake(.notDetermined)
        let sut = makeSUT(stations: StationsFake(result: true), requester: requester, isAppActive: { isActive })

        await sut.run()
        XCTAssertEqual(requester.requestCount, 0)

        isActive = true
        await sut.run()
        XCTAssertEqual(requester.requestCount, 1)
    }
}
