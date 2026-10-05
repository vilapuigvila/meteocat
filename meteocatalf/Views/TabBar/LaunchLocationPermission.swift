//
//  LaunchLocationPermission.swift
//  meteocatalf
//

import Foundation
import CoreLocation
import UIKit

/// Asks for "When In Use" location permission. It never reads, stores or publishes the location.
@MainActor
protocol LocationPermissionRequesting {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
}

@MainActor
final class CoreLocationPermissionRequester: LocationPermissionRequesting {
    // kept alive so the system prompt is not dismissed with the manager
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
}

/// At launch: make sure the stations are available, then ask for location permission, only if never asked.
/// Groundwork for finding the stations closest to the user.
@MainActor
final class LaunchLocationPermission {
    private let ensureStations: () async -> Bool
    private let requester: LocationPermissionRequesting
    private let isAppActive: () -> Bool
    private var isRunning = false
    private var isFinished = false

    init(
        ensureStations: @escaping () async -> Bool,
        requester: LocationPermissionRequesting,
        isAppActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
        self.ensureStations = ensureStations
        self.requester = requester
        self.isAppActive = isAppActive
    }

    /// Call it every time the app becomes active. It decides once per launch.
    /// - If the stations cannot be obtained, nothing else happens.
    /// - If the app went to the background while waiting, it waits for the next activation.
    func run() async {
        guard !isRunning, !isFinished else { return }
        isRunning = true
        defer { isRunning = false }

        guard await ensureStations() else {
            isFinished = true
            return
        }
        // the prompt only appears when the app is active
        guard isAppActive() else { return }
        isFinished = true
        guard requester.authorizationStatus == .notDetermined else { return }
        requester.requestWhenInUseAuthorization()
    }
}
