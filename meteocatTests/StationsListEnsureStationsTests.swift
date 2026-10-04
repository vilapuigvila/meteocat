import XCTest
import SwiftData
import Combine
import Alfy
@testable import meteocat

/// A throwaway in-memory database with the app's schema.
@MainActor
private final class InMemoryDatabase: DatabaseManagerProtocol {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: Schema([Model.Station.self, Model.InfoStationByDate.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    func insert<T: PersistentModel>(_ item: T) throws -> T {
        context.insert(item)
        try context.save()
        return item
    }
    func insert<T: PersistentModel>(_ sequenceOf: [T]) throws {
        sequenceOf.forEach { context.insert($0) }
        try context.save()
    }
    func fetchItems<T: PersistentModel>(_ item: T.Type, predicate: Predicate<T>?, sortBy: [SortDescriptor<T>]?) throws -> [T] {
        try context.fetch(FetchDescriptor<T>(predicate: predicate, sortBy: sortBy ?? []))
    }
    func removeItem<T: PersistentModel>(_ item: T) throws {
        context.delete(item)
        try context.save()
    }
    func remove<T: PersistentModel>(_ items: [T]) throws {
        items.forEach { context.delete($0) }
        try context.save()
    }
    func deleteAll<T: PersistentModel>(_ item: T.Type) throws {
        try context.fetch(FetchDescriptor<T>()).forEach { context.delete($0) }
        try context.save()
    }
    func save() throws { try context.save() }
}

@MainActor
final class StationsListEnsureStationsTests: XCTestCase {

    /// Fresh stations in the database: the call answers without a request, and the tab gets the same list.
    func testFreshStationsInDatabaseAreAvailableWithoutNetwork() async throws {
        let database = try InMemoryDatabase()
        try database.insert([
            Model.Station(code: "CC", codeCity: "1", name: "Orís", type: "A", lastUpdated: Date().timeIntervalSince1970)
        ])
        let interactor = StationsListInteractorImpl(databaseManager: database)

        let available = await interactor.ensureStationsAvailable()

        XCTAssertTrue(available)
        XCTAssertEqual(interactor.domain.list.map(\.code), ["CC"])
        XCTAssertFalse(interactor.domain.isLoading)
    }
}
