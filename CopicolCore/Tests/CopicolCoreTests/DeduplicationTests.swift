import CopicolCore
import XCTest

@MainActor
final class DeduplicationTests: XCTestCase {
    private var clock: TestClock!
    private var store: ClipStore!

    override func setUp() async throws {
        clock = TestClock()
        store = try makeStore(clock: clock, testCase: self)
    }

    func testIdenticalTextMovesToTopInsteadOfDuplicating() async throws {
        try await store.ingest(.text("bonjour", source: safari))
        clock.advance(by: 60)
        try await store.ingest(.text("au revoir", source: safari))
        clock.advance(by: 60)

        let result = try await store.ingest(.text("bonjour", source: notes))

        guard case .bumped(let item) = result else { return XCTFail("Une copie identique doit remonter l'existant") }
        XCTAssertEqual(store.count(), 2)
        XCTAssertEqual(store.allItems().first?.id, item.id)
        XCTAssertEqual(item.copyCount, 2)
        XCTAssertEqual(item.lastUsedAt, clock.now)
        XCTAssertEqual(item.sourceAppName, "Notes", "La source est celle de la dernière copie")
    }

    func testCopyingTheLatestItemAgainDoesNotCreateADuplicate() async throws {
        try await store.ingest(.text("même contenu"))
        try await store.ingest(.text("même contenu"))
        try await store.ingest(.text("même contenu"))

        XCTAssertEqual(store.count(), 1)
        XCTAssertEqual(store.allItems().first?.copyCount, 3)
    }

    func testSameTextWithDifferentKindsIsNotMerged() async throws {
        try await store.ingest(.text("Titre"))
        try await store.ingest(CapturedContent(kind: .richText, text: "Titre", rtfData: Data("{\\rtf1 Titre}".utf8)))

        XCTAssertEqual(store.count(), 2)
    }

    func testDifferentTextsAreKeptSeparately() async throws {
        try await store.ingest(.text("un"))
        try await store.ingest(.text("Un"))

        XCTAssertEqual(store.count(), 2, "La déduplication est sensible à la casse : contenus différents")
    }

    func testIdenticalImageIsDeduplicatedAndFilesAreStoredOnce() async throws {
        let png = makePNG()
        let first = try await store.ingest(CapturedContent(kind: .image, imageData: png))
        let second = try await store.ingest(CapturedContent(kind: .image, imageData: png))

        XCTAssertEqual(store.count(), 1)
        XCTAssertEqual(first.item.id, second.item.id)
        let item = first.item
        XCTAssertTrue(item.has(.image))
        XCTAssertTrue(item.has(.thumbnail))
        XCTAssertEqual(item.imageWidth, 8)
        XCTAssertEqual(store.files.read(.image, for: item.id), png)
        let directories = try FileManager.default.contentsOfDirectory(atPath: store.files.itemsDirectory.path)
        XCTAssertEqual(directories, [item.id.uuidString])
    }

    func testTIFFImageIsConvertedToPNG() async throws {
        let tiff = try XCTUnwrap(NSImage(data: makePNG())?.tiffRepresentation)
        let item = try await store.ingest(CapturedContent(kind: .image, imageData: tiff, imageIsPNG: false)).item

        let stored = try XCTUnwrap(store.files.read(.image, for: item.id))
        XCTAssertEqual(stored.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]), "Signature PNG attendue")
    }

    func testUnreadableImageIsRejected() async throws {
        do {
            try await store.ingest(CapturedContent(kind: .image, imageData: Data("pas une image".utf8)))
            XCTFail("Une image illisible doit être rejetée")
        } catch ClipStore.IngestError.unreadableImage {
            XCTAssertEqual(store.count(), 0)
        }
    }

    func testDeletingAnItemRemovesItsFiles() async throws {
        let item = try await store.ingest(CapturedContent(kind: .image, imageData: makePNG())).item
        let directory = store.files.directory(for: item.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))

        store.delete(item)

        XCTAssertEqual(store.count(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testTouchMovesPastedItemToTop() async throws {
        let older = try await store.ingest(.text("ancien")).item
        clock.advance(by: 10)
        try await store.ingest(.text("récent"))
        clock.advance(by: 10)

        store.touch(older)

        XCTAssertEqual(store.allItems().first?.id, older.id)
        XCTAssertEqual(older.copyCount, 1, "Coller n'est pas une nouvelle copie")
    }
}
