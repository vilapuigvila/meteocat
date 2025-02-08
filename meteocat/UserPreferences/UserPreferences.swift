//
//  UserPreferences.swift
//  meteocat
//
//  Created by albert vila on 6/2/25.
//

import Foundation
import Combine

enum UserPreferencesKey: String {
    case lastUpdateDate
    case homeStation
}

@propertyWrapper
struct UserDefault<T: Codable> {
    let key: String
    let defaultValue: T?

    
    init(_ key: String, defaultValue: T?) {
        self.key = key
        self.defaultValue = defaultValue
        
    }

    var wrappedValue: T? {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let decodedValue = try? JSONDecoder().decode(T.self, from: data) {
                return decodedValue
            }
            return defaultValue
        }
        set {
            if let encodedValue = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encodedValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            NotificationCenter.default.post(name: .userDefaultsChanged, object: key)
        }
    }
}

enum Preference {
    struct HomeStation: Codable, Equatable {
        let name: String
        let code: String
    }
}

struct UserSettings {
#warning("avp check it out ⚠️ -> default value to nil")
    @UserDefault(UserPreferencesKey.homeStation.rawValue, defaultValue: Preference.HomeStation(name: "Orís", code: "CC"))
    static var homeStation: Preference.HomeStation?
}

extension Notification.Name {
    static let userDefaultsChanged = Notification.Name("userDefaultsChanged")
}

extension UserDefaults {
    func publisher<T: Codable>(for key: String, defaultValue: T) -> AnyPublisher<T, Never> {
        NotificationCenter.default.publisher(for: .userDefaultsChanged)
            .compactMap { notification -> T? in
                guard let changedKey = notification.object as? String, changedKey == key else { return nil }
                return UserDefaults.standard.decode(T.self, forKey: key) ?? defaultValue
            }
            .eraseToAnyPublisher()
    }
    
    func decode<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
