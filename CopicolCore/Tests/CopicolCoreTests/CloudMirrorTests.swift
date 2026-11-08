import CopicolCore
import SwiftData
import XCTest

/// Deux « Mac » partagent le même conteneur Boards en mémoire, qui joue le rôle de CloudKit.
@MainActor
final class CloudMirrorTests: XCTestCase {
    private var clock: TestClock!
    private var macA: ClipStore!
    private var macB: ClipStore!
    private var mirrorA: CloudMirror!
    private var mirrorB: CloudMirror!

    override func setUp() async throws {
        clock = TestClock()
        let sharedBoards = try StorageFactory.makeInMemoryContainers().boards
        macA = try makeDevice(boards: sharedBoards)
        macB = try makeDevice(boards: sharedBoards)
        mirrorA = CloudMirror(store: macA)
        mirrorB = CloudMirror(store: macB)
        macA.syncDelegate = mirrorA
        macB.syncDelegate = mirrorB
    }

    private func makeDevice(boards: ModelContainer) throws -> ClipStore {
        let local = try StorageFactory.makeInMemoryContainers().local
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopicolSyncTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = ClipStore(localContainer: local, boardContainer: boards, files: FileStore(root: root))
        let clock = self.clock!
        store.now = { clock.now }
        return store
    }

    private func texts(_ store: ClipStore) -> Set<String> {
        Set(store.allItems().compactMap(\.text))
    }

    private func remoteClips() throws -> [SyncedClip] {
        try macA.boardContext.fetch(FetchDescriptor<SyncedClip>())
    }

    // MARK: - Export / import

    func testOnlySmallTextItemsAreSynced() async throws {
        try await macA.ingest(.text("bonjour"))
        try await macA.ingest(.text("https://www.swift.org"))
        try await macA.ingest(.text("#FF9500"))
        try await macA.ingest(CapturedContent(kind: .image, imageData: makePNG()))
        try await macA.ingest(CapturedContent(kind: .richText, text: "enrichi", rtfData: Data("{\\rtf1 enrichi}".utf8)))
        try await macA.ingest(.text(String(repeating: "x", count: CloudMirror.maxTextBytes)))

        mirrorB.reconcile()

        XCTAssertEqual(texts(macB), ["bonjour", "https://www.swift.org", "#FF9500"])
        XCTAssertTrue(macB.allItems().allSatisfy(\.isSynced))
        XCTAssertEqual(macB.allItems().first { $0.kind == .link }?.linkURL, "https://www.swift.org")
    }

    func testExistingItemsAreExportedOnFirstReconcile() async throws {
        macA.syncDelegate = nil
        try await macA.ingest(.text("capturé avant l'activation d'iCloud"))
        macA.syncDelegate = mirrorA

        mirrorA.reconcile()
        mirrorB.reconcile()

        XCTAssertEqual(texts(macB), ["capturé avant l'activation d'iCloud"])
    }

    func testDuplicateRemoteCopiesAreCollapsed() async throws {
        let item = try await macA.ingest(.text("doublon")).item
        macA.boardContext.insert(SyncedClip(from: item))
        try macA.saveChanges()

        mirrorA.reconcile()

        XCTAssertEqual(try remoteClips().count, 1)
    }

    // MARK: - Suppressions

    func testExplicitDeletionPropagatesToOtherMac() async throws {
        let item = try await macA.ingest(.text("à supprimer")).item
        mirrorB.reconcile()
        XCTAssertEqual(macB.count(), 1)

        clock.advance(by: 5)
        macA.delete(item)
        mirrorB.reconcile()

        XCTAssertEqual(macB.count(), 0)
        XCTAssertTrue(try remoteClips().isEmpty)
    }

    func testDeletionWhileSyncIsInactiveIsAppliedOnReactivation() async throws {
        let item = try await macA.ingest(.text("supprimé hors ligne")).item
        mirrorB.reconcile()

        macA.syncDelegate = nil
        clock.advance(by: 5)
        macA.delete(item)
        macA.syncDelegate = mirrorA
        mirrorA.reconcile()
        mirrorB.reconcile()

        XCTAssertEqual(macA.count(), 0, "L'élément ne doit pas être réimporté sur le Mac qui l'a supprimé")
        XCTAssertEqual(macB.count(), 0)
    }

    func testRetentionPurgeIsNotPropagated() async throws {
        try await macA.ingest(.text("ancien"))
        mirrorB.reconcile()
        clock.advance(by: 3 * 86_400)
        mirrorA.importCutoff = { [clock] in RetentionPolicy.day.cutoff(from: clock!.now) }

        XCTAssertEqual(macA.purge(retention: .day), 1)
        mirrorA.reconcile()
        mirrorB.reconcile()

        XCTAssertEqual(macA.count(), 0, "Trop ancien pour la rétention de A : pas de réimport")
        XCTAssertEqual(texts(macB), ["ancien"], "B conserve l'élément selon sa propre rétention")
    }

    func testEmptiedRemoteStoreNeverWipesLocalHistory() async throws {
        try await macA.ingest(.text("un"))
        try await macA.ingest(.text("deux"))
        mirrorB.reconcile()

        // Base iCloud réinitialisée (compte changé, synchronisation remise à zéro).
        try remoteClips().forEach { macA.boardContext.delete($0) }
        try macA.saveChanges()
        mirrorB.reconcile()

        XCTAssertEqual(texts(macB), ["un", "deux"])
        XCTAssertEqual(try remoteClips().count, 2, "Les éléments locaux sont réexportés")
    }

    func testRecopyAfterRemoteDeletionKeepsItem() async throws {
        let onA = try await macA.ingest(.text("toujours utile")).item
        mirrorB.reconcile()
        clock.advance(by: 5)
        macA.delete(onA)

        clock.advance(by: 5)
        try await macB.ingest(.text("toujours utile"))
        mirrorB.reconcile()
        mirrorA.reconcile()

        XCTAssertEqual(texts(macB), ["toujours utile"])
        XCTAssertEqual(texts(macA), ["toujours utile"], "Une nouvelle copie après la suppression l'emporte")
    }

    func testOldTombstonesArePruned() async throws {
        let item = try await macA.ingest(.text("éphémère")).item
        macA.delete(item)
        clock.advance(by: CloudMirror.tombstoneLifetime + 1)

        mirrorA.reconcile()

        XCTAssertTrue(try macA.boardContext.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    // MARK: - Épinglage et usage

    func testPinningOnOneMacIsMergedOnTheOther() async throws {
        let item = try await macA.ingest(.text("note partagée")).item
        mirrorB.reconcile()
        clock.advance(by: 10)

        // Les pinboards vivent dans le conteneur synchronisé : visibles des deux côtés.
        let board = macA.createPinboard(name: "Projet", colorHex: "#30D158")
        macA.pin(item, to: board)
        mirrorB.reconcile()

        XCTAssertEqual(macB.pinboards().map(\.name), ["Projet"])
        XCTAssertEqual(macB.allItems().first?.pinboardID, board.id)
    }

    func testMostRecentPinWins() async throws {
        let onA = try await macA.ingest(.text("conflit")).item
        mirrorB.reconcile()
        let first = macA.createPinboard(name: "A", colorHex: "#0A84FF")
        let second = macA.createPinboard(name: "B", colorHex: "#FF453A")

        clock.advance(by: 5)
        macA.pin(onA, to: first)
        clock.advance(by: 5)
        macB.pin(try XCTUnwrap(macB.allItems().first), to: second)
        mirrorA.reconcile()

        XCTAssertEqual(onA.pinboardID, second.id)
    }

    func testUsageOnAnotherMacDoesNotUndoPin() async throws {
        let onA = try await macA.ingest(.text("épinglé ici")).item
        mirrorB.reconcile()
        clock.advance(by: 5)
        let board = macA.createPinboard(name: "Gardés", colorHex: "#30D158")
        macA.pin(onA, to: board)

        // B recolle l'élément sans avoir encore reçu l'épinglage.
        clock.advance(by: 5)
        macB.touch(try XCTUnwrap(macB.allItems().first))
        mirrorA.reconcile()
        mirrorB.reconcile()

        XCTAssertEqual(onA.pinboardID, board.id)
        XCTAssertEqual(onA.lastUsedAt, clock.now, "La date d'usage la plus récente est conservée")
        XCTAssertEqual(macB.allItems().first?.pinboardID, board.id)
    }

    func testAvailabilityWithoutEntitlement() {
        XCTAssertNil(CloudSyncAvailability.containerIdentifier, "Le processus de test n'a pas d'entitlement iCloud")
    }
}
