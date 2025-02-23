//
//  DatabaseManager.swift
//  meteocat
//
//  Created by albert vila on 22/2/25.
//

import Foundation
import SwiftData

protocol DatabaseManagerProtocol {
    @MainActor @discardableResult
    func appendItem<T: PersistentModel>(item: T) throws -> T
    
    @MainActor
    func fetchItems<T: PersistentModel>(_ item: T.Type) throws -> [T]
    
    @MainActor
    func removeItem<T: PersistentModel>(_ item: T) throws
    
    @MainActor
    func deleteAll<T: PersistentModel>(_ item: T.Type) throws
}

extension DatabaseManagerProtocol where Self == DatabaseManager {
    @MainActor
    static var shared: Self {
        DatabaseManager.shared
    }
}

final class DatabaseManager : DatabaseManagerProtocol {
    enum ErrorReason: Error {
        case itemNotFound
    }
    @MainActor
    static func makeShared(_ types: [any PersistentModel.Type]) -> DatabaseManager {
        assert(_shared == nil, "call only once")
        if _shared == nil {
            _shared = DatabaseManager(types)
        }
        return _shared
    }
    @MainActor
    private static var _shared: DatabaseManager!
    
    @MainActor
    static var shared: DatabaseManager {
        assert(_shared != nil, "please call makeShared first")
        return _shared!
    }
    
    // MARK: - Properties -
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    @MainActor
    private init(_ types: [any PersistentModel.Type]) {
         let sharedModelContainer: ModelContainer? = {
             let schema = Schema(types)
             let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
             do {
                 return try ModelContainer(for: schema, configurations: [modelConfiguration])
             } catch {
                 return nil
             }
         }()
        guard let sharedModelContainer else {
            fatalError()
        }
        self.modelContainer = sharedModelContainer
        self.modelContext = modelContainer.mainContext
    }
    
//    @MainActor
    func appendItem<T: PersistentModel>(item: T) throws -> T  {
        modelContext.insert(item)
        try modelContext.save()
        return item
    }
    
//    @MainActor
    func fetchItems<T: PersistentModel>(_ item: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }
    
//    @MainActor
    func removeItem<T: PersistentModel>(_ item: T) throws {
        let fetchDescriptor = FetchDescriptor<T>()
        let results = try modelContext.fetch(fetchDescriptor)
        guard let entityToDelete = results.first else {
            assertionFailure()
            throw ErrorReason.itemNotFound
        }
        modelContext.delete(entityToDelete)
        try modelContext.save()
    }
    
//    @MainActor
    func deleteAll<T: PersistentModel>(_ item: T.Type) throws {
        try modelContext.fetch(FetchDescriptor<T>()).forEach { modelContext.delete($0) }
        try modelContext.save()
    }
}
