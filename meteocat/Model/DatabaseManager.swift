//
//  DatabaseManager.swift
//  meteocat
//
//  Created by albert vila on 22/2/25.
//
/*
import Foundation
import SwiftData

//typealias PersistentModel = PersistentModel

protocol DatabaseManagerProtocol {
    @MainActor @discardableResult
    func insert<T: PersistentModel>(_ item: T) throws -> T
    
    @MainActor
    func insert<T: PersistentModel>(_ sequenceOf: [T]) throws
    
    @MainActor
    func fetchItems<T: PersistentModel>(_ item: T.Type, predicate: Predicate<T>?, sortBy: [SortDescriptor<T>]?) throws -> [T]
    
    @MainActor
    func removeItem<T: PersistentModel>(_ item: T) throws
    
    @MainActor
    func remove<T: PersistentModel>(_ items: [T]) throws
    
    @MainActor
    func deleteAll<T: PersistentModel>(_ item: T.Type) throws
    
    @MainActor
    func save() throws
    
//    @MainActor
//    func transaction<T>(_ block: () throws -> T) rethrows
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
//        sharedModelContainer.mainContext.container.deleteAllData()
        
        self.modelContainer = sharedModelContainer
        self.modelContext = modelContainer.mainContext
    }
    
    // MARK: - Protocol funcs -
    
    func save() throws {
        try modelContext.save()
    }
    
    @MainActor
    func insert<T: PersistentModel>(_ item: T) throws -> T  {
        assert(Thread.isMainThread)
        modelContext.insert(item)
        try modelContext.save()
        return item
    }
    
    @MainActor
    func insert<T: PersistentModel>(_ sequenceOf: [T]) throws {
        assert(Thread.isMainThread)
        do {
            try modelContext.transaction {
                for item in sequenceOf {
//                    guard fetchExistingItem(by: item.id, type: T.self) == nil else {
//                        continue
//                    }
                    modelContext.insert(item)
                }
            }
            try modelContext.save()
        } catch {
            print("❌ Error storing stations: \(error)")
        }
    }
    
    @MainActor
    func fetchItems<T: PersistentModel>(_ item: T.Type, predicate: Predicate<T>?, sortBy: [SortDescriptor<T>]?) throws -> [T] {
        assert(Thread.isMainThread)
        return try modelContext.fetch(
            FetchDescriptor<T>(predicate: predicate, sortBy: sortBy ?? [])
        )
    }
    
    @MainActor
    func removeItem<T: PersistentModel>(_ item: T) throws {
        assert(Thread.isMainThread)
        modelContext.delete(item)
        try modelContext.save()
    }
    
    @MainActor
    func remove<T: PersistentModel>(_ items: [T]) throws {
        assert(Thread.isMainThread)
        guard !items.isEmpty else { return }
        items.forEach { modelContext.delete($0) }
        try modelContext.save()
    }
    
    @MainActor
    func deleteAll<T: PersistentModel>(_ item: T.Type) throws {
        assert(Thread.isMainThread)
        try modelContext.fetch(FetchDescriptor<T>()).forEach { modelContext.delete($0) }
        try modelContext.save()
    }

    /*
//    @MainActor
    private func fetchExistingItem<T: PersistentModel>(by id: T.ID, type: T.Type) -> T? where T.ID: Comparable & Codable {
        let fetchDescriptor = FetchDescriptor<T>(
            predicate: #Predicate<T> { item in
                item.id == id
            }
        )
        return try? modelContext.fetch(fetchDescriptor).first
    }
     */
}
*/
