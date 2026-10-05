//
//  NearestStation.swift
//  meteocatalf
//

import Foundation
import CoreLocation

struct GeoPoint: Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// Finds the operating station closest to a point. Pure: no location services, no network.
enum NearestStation {

    struct Suggestion: Equatable, Hashable, Sendable {
        let code: String
        let name: String
        let codeCity: String
        let distanceKm: Double
    }

    /// meteo.cat marks each station's history with state codes (2 = operating, 1 and 3 = stopped periods).
    /// A station is operating when the state that is still open (no end date) is 2.
    /// Checked against the live list: every station has one open state, always 2; the others only appear in the past.
    static let operatingStateCode = 2

    static func isOperating(_ station: DTO.Station) -> Bool {
        station.states.first(where: { $0.dataFi == nil })?.codi == operatingStateCode
    }

    /// The closest operating station, or `nil` when there is none.
    static func find(to point: GeoPoint, in stations: [DTO.Station]) -> Suggestion? {
        let origin = CLLocation(latitude: point.latitude, longitude: point.longitude)
        return stations
            .filter(isOperating)
            // the placeholder coordinates of stations rebuilt from the database
            .filter { !($0.coordinates.latitude == 0 && $0.coordinates.longitude == 0) }
            .map { station -> (DTO.Station, CLLocationDistance) in
                let location = CLLocation(latitude: station.coordinates.latitude, longitude: station.coordinates.longitude)
                return (station, origin.distance(from: location))
            }
            .min { $0.1 < $1.1 }
            .map { Suggestion(code: $0.0.code, name: $0.0.name, codeCity: $0.0.city.codi, distanceKm: $0.1 / 1000) }
    }
}

// MARK: - Location, one shot

/// Reads the current location once. It never asks for permission: the launch flow does that.
@MainActor
protocol OneShotLocationReading {
    var authorizationStatus: CLAuthorizationStatus { get }
    /// `nil` when the location can't be read.
    func readLocation() async -> GeoPoint?
}

@MainActor
final class CoreLocationOneShotReader: NSObject, OneShotLocationReading, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<GeoPoint?, Never>] = []

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
        // a station is kilometres away: no need for the GPS
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func readLocation() async -> GeoPoint? {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            // callers that arrive meanwhile share the answer
            if waiting.count == 1 { manager.requestLocation() }
        }
    }

    private func finish(_ point: GeoPoint?) {
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume(returning: point) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let point = locations.last.map { GeoPoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        Task { @MainActor in self.finish(point) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

// MARK: - Decision

@MainActor
protocol NearestStationSuggesting {
    func suggestion() async -> NearestStation.Suggestion?
}

/// Decides whether the empty My Station tab can suggest a station. Any failure means "no suggestion".
/// It never stores, logs or sends the location.
@MainActor
final class NearestStationSuggester: NearestStationSuggesting {
    private let location: OneShotLocationReading
    private let loadStations: () async -> [DTO.Station]
    private let hasHomeStation: () -> Bool

    /// - loadStations: the station list with coordinates; empty when it can't be obtained.
    init(
        location: OneShotLocationReading,
        loadStations: @escaping () async -> [DTO.Station],
        hasHomeStation: @escaping () -> Bool = { UserSettings.homeStation != nil }
    ) {
        self.location = location
        self.loadStations = loadStations
        self.hasHomeStation = hasHomeStation
    }

    func suggestion() async -> NearestStation.Suggestion? {
        guard !hasHomeStation() else { return nil }
        // the location is only read when the user already allowed it
        guard Self.isGranted(location.authorizationStatus) else { return nil }
        let stations = await loadStations()
        guard !stations.isEmpty else { return nil }
        guard let point = await location.readLocation() else { return nil }
        // the user may have chosen a station while we were waiting
        guard !hasHomeStation() else { return nil }
        return NearestStation.find(to: point, in: stations)
    }

    private static func isGranted(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }
}
