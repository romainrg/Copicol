import CopicolCore
import XCTest

@MainActor
final class SearchTests: XCTestCase {
    private var clock: TestClock!
    private var store: ClipStore!

    override func setUp() async throws {
        clock = TestClock()
        store = try makeStore(clock: clock, testCase: self)
    }

    @discardableResult
    private func ingest(_ content: CapturedContent) async throws -> ClipItem {
        clock.advance(by: 1)
        return try await store.ingest(content).item
    }

    private func search(_ text: String, filter: ClipFilter = .all, scope: ClipScope = .history) -> [String] {
        store.items(matching: ClipQuery(scope: scope, text: text, filter: filter)).map { $0.text ?? $0.filePaths.first ?? "" }
    }

    func testMatchesTextContent() async throws {
        try await ingest(.text("La réunion d'équipe est à 14h"))
        try await ingest(.text("Liste de courses"))

        XCTAssertEqual(search("équipe"), ["La réunion d'équipe est à 14h"])
    }

    func testIsCaseAndDiacriticInsensitive() async throws {
        try await ingest(.text("Été à Évian"))

        XCTAssertEqual(search("ETE"), ["Été à Évian"])
        XCTAssertEqual(search("evian"), ["Été à Évian"])
    }

    func testMatchesLinkTitle() async throws {
        let link = try await ingest(.text("https://www.swift.org"))
        store.updateLinkMetadata(link, title: "Swift Programming Language", favicon: nil)

        XCTAssertEqual(search("programming"), ["https://www.swift.org"])
    }

    func testMatchesFileName() async throws {
        try await ingest(CapturedContent(kind: .file, fileURLs: [URL(fileURLWithPath: "/Users/moi/Documents/Facture-2026.pdf")]))

        XCTAssertEqual(search("facture"), ["/Users/moi/Documents/Facture-2026.pdf"])
        XCTAssertEqual(search("documents"), [], "Seul le nom du fichier est indexé, pas le chemin")
    }

    func testMatchesSourceApplication() async throws {
        try await ingest(.text("depuis Safari", source: safari))
        try await ingest(.text("depuis Notes", source: notes))

        XCTAssertEqual(search("safari"), ["depuis Safari"])
    }

    func testAllWordsMustMatch() async throws {
        try await ingest(.text("clé API production"))
        try await ingest(.text("clé API staging"))
        try await ingest(.text("production database"))

        XCTAssertEqual(search("api production"), ["clé API production"])
    }

    func testEmptyQueryReturnsEverythingMostRecentFirst() async throws {
        try await ingest(.text("premier"))
        try await ingest(.text("deuxième"))
        try await ingest(.text("troisième"))

        XCTAssertEqual(search(""), ["troisième", "deuxième", "premier"])
    }

    func testFilterByKind() async throws {
        try await ingest(.text("texte simple"))
        try await ingest(CapturedContent(kind: .richText, text: "texte riche", rtfData: Data("{\\rtf1 riche}".utf8)))
        try await ingest(.text("https://texte.example.com"))
        try await ingest(.text("#ABCDEF"))
        try await ingest(CapturedContent(kind: .image, imageData: makePNG()))

        XCTAssertEqual(search("", filter: .text), ["texte riche", "texte simple"])
        XCTAssertEqual(search("texte", filter: .link), ["https://texte.example.com"])
        XCTAssertEqual(search("", filter: .color), ["#ABCDEF"])
        XCTAssertEqual(store.items(matching: ClipQuery(filter: .image)).count, 1)
    }

    func testPinboardScope() async throws {
        let work = store.createPinboard(name: "Travail", colorHex: "#0A84FF")
        let perso = store.createPinboard(name: "Perso", colorHex: "#FF375F")
        let pinnedWork = try await ingest(.text("note travail"))
        let pinnedPerso = try await ingest(.text("note perso"))
        try await ingest(.text("note libre"))
        store.pin(pinnedWork, to: work)
        store.pin(pinnedPerso, to: perso)

        XCTAssertEqual(search("note", scope: .pinboard(work.id)), ["note travail"])
        XCTAssertEqual(search("", scope: .pinboard(perso.id)), ["note perso"])
        XCTAssertEqual(search("note").count, 3, "L'historique montre aussi les éléments épinglés")
    }

    func testLimitIsApplied() async throws {
        for index in 0..<10 {
            try await ingest(.text("élément \(index)"))
        }

        XCTAssertEqual(store.items(matching: ClipQuery(limit: 4)).count, 4)
        XCTAssertEqual(store.items(matching: ClipQuery(text: "élément 9", limit: 4)).count, 1)
    }
}
