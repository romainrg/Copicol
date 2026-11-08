import CopicolCore
import XCTest

@MainActor
final class RetentionTests: XCTestCase {
    private var clock: TestClock!
    private var store: ClipStore!

    override func setUp() async throws {
        clock = TestClock()
        store = try makeStore(clock: clock, testCase: self)
    }

    @discardableResult
    private func ingest(_ text: String, ageInDays days: Double) async throws -> ClipItem {
        let item = try await store.ingest(.text(text)).item
        item.lastUsedAt = clock.now.addingTimeInterval(-days * 86_400)
        try store.saveChanges()
        return item
    }

    func testCutoffDates() {
        let now = clock.now
        XCTAssertEqual(RetentionPolicy.day.cutoff(from: now), now.addingTimeInterval(-86_400))
        XCTAssertEqual(RetentionPolicy.week.cutoff(from: now), now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(RetentionPolicy.month.cutoff(from: now), now.addingTimeInterval(-30 * 86_400))
        XCTAssertNil(RetentionPolicy.unlimited.cutoff(from: now))
    }

    func testPurgeRemovesOnlyExpiredUnpinnedItems() async throws {
        try await ingest("récent", ageInDays: 0.5)
        try await ingest("vieux", ageInDays: 3)
        let pinnedOld = try await ingest("épinglé", ageInDays: 400)
        store.pin(pinnedOld, to: store.createPinboard(name: "Archives", colorHex: "#FF9F0A"))

        let removed = store.purge(retention: .day)

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(Set(store.allItems().compactMap(\.text)), ["récent", "épinglé"])
    }

    func testEachPolicyBoundary() async throws {
        try await ingest("2 jours", ageInDays: 2)
        try await ingest("10 jours", ageInDays: 10)
        try await ingest("45 jours", ageInDays: 45)

        XCTAssertEqual(store.purge(retention: .unlimited), 0)
        XCTAssertEqual(store.purge(retention: .month), 1)
        XCTAssertEqual(store.purge(retention: .week), 1)
        XCTAssertEqual(store.purge(retention: .day), 1)
        XCTAssertEqual(store.count(), 0)
    }

    func testRecentUseProtectsAnOldItem() async throws {
        let item = try await ingest("réutilisé", ageInDays: 20)
        store.touch(item)

        XCTAssertEqual(store.purge(retention: .week), 0)
    }

    func testPurgeDeletesFilesOfExpiredItems() async throws {
        let image = try await store.ingest(CapturedContent(kind: .image, imageData: makePNG())).item
        image.lastUsedAt = clock.now.addingTimeInterval(-10 * 86_400)
        try store.saveChanges()
        let directory = store.files.directory(for: image.id)

        store.purge(retention: .week)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testClearHistoryKeepsPinnedItems() async throws {
        try await ingest("a", ageInDays: 0)
        try await ingest("b", ageInDays: 0)
        let pinned = try await ingest("c", ageInDays: 0)
        store.pin(pinned, to: store.createPinboard(name: "Favoris", colorHex: "#30D158"))

        XCTAssertEqual(store.clearHistory(), 2)
        XCTAssertEqual(store.allItems().map(\.id), [pinned.id])
    }

    func testDeletingPinboardReturnsItemsToHistory() async throws {
        let board = store.createPinboard(name: "Projet", colorHex: "#BF5AF2")
        let item = try await ingest("snippet", ageInDays: 100)
        store.pin(item, to: board)

        store.delete(board)

        XCTAssertNil(item.pinboardID)
        XCTAssertTrue(store.pinboards().isEmpty)
        XCTAssertEqual(store.purge(retention: .month), 1, "De retour dans l'historique, l'élément suit la rétention")
    }

    func testOrphanFilesAreRemoved() async throws {
        let kept = try await store.ingest(CapturedContent(kind: .image, imageData: makePNG())).item
        try store.files.write([.thumbnail: Data([1])], for: UUID())

        XCTAssertEqual(store.removeOrphanFiles(), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.files.directory(for: kept.id).path))
    }
}
