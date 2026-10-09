//
//  HomeStationWidgetStore.swift
//  meteocatalf
//

import Foundation

/// Reads and writes the home-station snapshot in the App Group the app and the widget share.
struct HomeStationWidgetStore {
    static let key = "homeStationWidgetSnapshot"

    /// nil when the App Group isn't available: nothing is saved and nothing is read.
    let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: WidgetShared.appGroupID)) {
        self.defaults = defaults
    }

    /// nil when nothing is stored or the stored data can't be decoded.
    func load() -> HomeStationWidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(HomeStationWidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: HomeStationWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    func clear() {
        defaults?.removeObject(forKey: Self.key)
    }
}
