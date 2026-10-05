import XCTest
import CoreLocation
@testable import meteocatalf

/// Nearest station and the decision to suggest it. No network, no CoreLocation hardware: fakes and fixtures only.
@MainActor
final class NearestStationTests: XCTestCase {

    // MARK: - Fixtures

    /// `open: true` is the station's state today (2 = operating); `open: false` leaves only a closed period.
    private func station(
        _ code: String, _ name: String, lat: Double, lon: Double, operating: Bool = true, city: String = "0001"
    ) throws -> DTO.Station {
        let states = operating
            ? #"[{"codi":2,"dataInici":"2000-01-01T00:00Z","dataFi":null}]"#
            : #"[{"codi":2,"dataInici":"2000-01-01T00:00Z","dataFi":"2020-01-01T00:00Z"},{"codi":3,"dataInici":"2020-01-01T00:00Z","dataFi":null}]"#
        let json = """
        {"codi":"\(code)","nom":"\(name)","tipus":"A","coordenades":{"latitud":\(lat),"longitud":\(lon)},
         "emplacament":"","altitud":1,"municipi":{"codi":"\(city)","nom":"x"},"comarca":{"codi":1,"nom":"x"},"estats":\(states)}
        """
        return try JSONDecoder().decode(DTO.Station.self, from: Data(json.utf8))
    }

    // Orís (CC) and its surroundings, real coordinates
    private let oris = GeoPoint(latitude: 42.07397, longitude: 2.20865)

    private func fixtureList() throws -> [DTO.Station] {
        [
            try station("D5", "Barcelona", lat: 41.3874, lon: 2.1686),
            // closed, and the nearest of all: must be skipped
            try station("XX", "Tancada", lat: 42.0740, lon: 2.2087, operating: false),
            try station("CC", "Orís", lat: 42.07397, lon: 2.20865, city: "081509"),
            try station("VG", "Vic", lat: 41.93, lon: 2.25),
        ]
    }

    // MARK: - Nearest station

    func testPicksTheNearestOperatingStationAndSkipsTheClosedOne() throws {
        let point = GeoPoint(latitude: 42.0741, longitude: 2.2088)
        let result = try XCTUnwrap(NearestStation.find(to: point, in: fixtureList()))

        XCTAssertEqual(result.code, "CC")
        XCTAssertEqual(result.name, "Orís")
        XCTAssertEqual(result.codeCity, "081509")
        XCTAssertLessThan(result.distanceKm, 0.1)
    }

    func testDistanceIsInKilometres() throws {
        // Vic is about 16 km south of Orís
        let result = try XCTUnwrap(NearestStation.find(to: oris, in: [station("VG", "Vic", lat: 41.93, lon: 2.25)]))
        XCTAssertEqual(result.distanceKm, 16.4, accuracy: 0.5)
    }

    func testNoOperatingStationMeansNoResult() throws {
        XCTAssertNil(NearestStation.find(to: oris, in: [try station("XX", "Tancada", lat: 42, lon: 2, operating: false)]))
        XCTAssertNil(NearestStation.find(to: oris, in: []))
    }

    func testStationWithoutHistoryIsNotOperating() {
        XCTAssertFalse(NearestStation.isOperating(DTO.Station(code: "AA", name: "a", type: "A")))
    }

    // MARK: - Decision

    private final class LocationFake: OneShotLocationReading {
        var authorizationStatus: CLAuthorizationStatus
        let point: GeoPoint?
        private(set) var readCount = 0
        init(_ status: CLAuthorizationStatus, point: GeoPoint?) { authorizationStatus = status; self.point = point }
        func readLocation() async -> GeoPoint? { readCount += 1; return point }
    }

    private func makeSuggester(
        location: LocationFake,
        stations: [DTO.Station],
        hasHome: Bool = false
    ) -> NearestStationSuggester {
        NearestStationSuggester(location: location, loadStations: { stations }, hasHomeStation: { hasHome })
    }

    func testSuggestsTheNearestStationWhenEverythingIsAvailable() async throws {
        for status in [CLAuthorizationStatus.authorizedWhenInUse, .authorizedAlways] {
            let suggester = makeSuggester(location: LocationFake(status, point: oris), stations: try fixtureList())
            let result = await suggester.suggestion()
            XCTAssertEqual(result?.code, "CC")
        }
    }

    func testNoSuggestionWithoutPermissionAndTheLocationIsNotRead() async throws {
        for status in [CLAuthorizationStatus.notDetermined, .denied, .restricted] {
            let location = LocationFake(status, point: oris)
            let result = await makeSuggester(location: location, stations: try fixtureList()).suggestion()
            XCTAssertNil(result)
            XCTAssertEqual(location.readCount, 0)
        }
    }

    func testNoSuggestionWhenTheLocationFails() async throws {
        let result = await makeSuggester(
            location: LocationFake(.authorizedWhenInUse, point: nil), stations: try fixtureList()
        ).suggestion()
        XCTAssertNil(result)
    }

    func testNoSuggestionWhenTheListIsEmpty() async {
        let location = LocationFake(.authorizedWhenInUse, point: oris)
        let result = await makeSuggester(location: location, stations: []).suggestion()
        XCTAssertNil(result)
        XCTAssertEqual(location.readCount, 0)
    }

    func testNoSuggestionWhenThereIsAlreadyAHomeStation() async throws {
        let location = LocationFake(.authorizedWhenInUse, point: oris)
        let result = await makeSuggester(location: location, stations: try fixtureList(), hasHome: true).suggestion()
        XCTAssertNil(result)
        XCTAssertEqual(location.readCount, 0)
    }

    func testNoSuggestionWhenTheHomeStationIsChosenWhileTheLocationIsRead() async throws {
        var hasHome = false
        let location = LocationFake(.authorizedWhenInUse, point: oris)
        let list = try fixtureList()
        let suggester = NearestStationSuggester(
            location: location,
            loadStations: { hasHome = true; return list },
            hasHomeStation: { hasHome }
        )
        let result = await suggester.suggestion()
        XCTAssertNil(result)
    }
}
