import AppKit
import CopicolCore
import XCTest

/// Détection de type : classification des textes et lecture d'un vrai NSPasteboard (privé).
@MainActor
final class ContentClassifierTests: XCTestCase {
    // MARK: - Texte seul

    func testHexColorsAreDetectedAndNormalized() {
        XCTAssertEqual(ContentClassifier.classify("#ff8800"), .color("#FF8800"))
        XCTAssertEqual(ContentClassifier.classify("  #FFF \n"), .color("#FFFFFF"))
        XCTAssertEqual(ContentClassifier.classify("#0f08"), .color("#00FF0088"))
        XCTAssertEqual(ContentClassifier.classify("#12345678"), .color("#12345678"))
    }

    func testInvalidHexColorsAreText() {
        for candidate in ["#ggg", "#12345", "ff8800", "#ff8800 rouge", "#"] {
            XCTAssertEqual(ContentClassifier.classify(candidate), .plain, candidate)
        }
    }

    func testWebLinksAreDetected() {
        XCTAssertEqual(ContentClassifier.classify("https://www.apple.com/fr/"), .link(URL(string: "https://www.apple.com/fr/")!))
        XCTAssertEqual(ContentClassifier.classify("http://localhost:8080/api"), .link(URL(string: "http://localhost:8080/api")!))
        XCTAssertEqual(ContentClassifier.classify("www.example.org"), .link(URL(string: "https://www.example.org")!))
    }

    func testNonLinksAreText() {
        for candidate in ["voir https://apple.com", "mailto:a@b.fr", "ftp://files.example.org", "https://", "apple", "https://intranet"] {
            XCTAssertEqual(ContentClassifier.classify(candidate), .plain, candidate)
        }
    }

    func testHexColorComponentsRoundTrip() throws {
        let components = try XCTUnwrap(HexColor.components("#FF800080"))
        XCTAssertEqual(components.red, 1, accuracy: 0.001)
        XCTAssertEqual(components.green, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(components.alpha, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(HexColor.hex(components), "#FF800080")
    }

    // MARK: - Lecture du presse-papiers

    private func read(_ pasteboard: NSPasteboard, excluded: Set<String> = [], frontmost: SourceApp? = safari) -> PasteboardReader.Outcome {
        PasteboardReader.read(pasteboard, frontmostApp: frontmost, excludedBundleIDs: excluded, ownBundleID: "io.github.romainrg.Copicol")
    }

    private func captured(_ outcome: PasteboardReader.Outcome, file: StaticString = #filePath, line: UInt = #line) throws -> CapturedContent {
        guard case .captured(let content) = outcome else {
            XCTFail("Contenu attendu, obtenu \(outcome)", file: file, line: line)
            throw XCTSkip()
        }
        return content
    }

    func testPlainString() throws {
        let pasteboard = makePasteboard(testCase: self)
        pasteboard.setString("Bonjour le monde", forType: .string)

        let content = try captured(read(pasteboard))
        XCTAssertEqual(content.kind, .text)
        XCTAssertEqual(content.text, "Bonjour le monde")
        XCTAssertEqual(content.source, safari)
    }

    func testRichTextKeepsRTFAndHTML() throws {
        let pasteboard = makePasteboard(testCase: self)
        let attributed = NSAttributedString(string: "Gras", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        let item = NSPasteboardItem()
        item.setString("Gras", forType: .string)
        item.setData(rtf, forType: .rtf)
        item.setData(Data("<b>Gras</b>".utf8), forType: .html)
        pasteboard.writeObjects([item])

        let content = try captured(read(pasteboard))
        XCTAssertEqual(content.kind, .richText)
        XCTAssertEqual(content.rtfData, rtf)
        XCTAssertNotNil(content.htmlData)
    }

    func testPNGImage() throws {
        let pasteboard = makePasteboard(testCase: self)
        let png = makePNG()
        pasteboard.setData(png, forType: .png)

        let content = try captured(read(pasteboard))
        XCTAssertEqual(content.kind, .image)
        XCTAssertEqual(content.imageData, png)
        XCTAssertTrue(content.imageIsPNG)
    }

    func testTIFFImage() throws {
        let pasteboard = makePasteboard(testCase: self)
        let tiff = try XCTUnwrap(NSImage(data: makePNG())?.tiffRepresentation)
        pasteboard.setData(tiff, forType: .tiff)

        let content = try captured(read(pasteboard))
        XCTAssertEqual(content.kind, .image)
        XCTAssertFalse(content.imageIsPNG)
    }

    func testImageWithRealTextIsTreatedAsText() throws {
        let pasteboard = makePasteboard(testCase: self)
        let item = NSPasteboardItem()
        item.setString("A1\tB1", forType: .string)
        item.setData(makePNG(), forType: .png)
        pasteboard.writeObjects([item])

        XCTAssertEqual(try captured(read(pasteboard)).kind, .text)
    }

    func testFileURLs() throws {
        let pasteboard = makePasteboard(testCase: self)
        let urls = [URL(fileURLWithPath: "/tmp/rapport.pdf"), URL(fileURLWithPath: "/tmp/photo.jpg")]
        pasteboard.writeObjects(urls as [NSURL])

        let content = try captured(read(pasteboard))
        XCTAssertEqual(content.kind, .file)
        XCTAssertEqual(content.fileURLs.map(\.path), ["/tmp/rapport.pdf", "/tmp/photo.jpg"])
    }

    func testLinkString() throws {
        let pasteboard = makePasteboard(testCase: self)
        pasteboard.setString("https://developer.apple.com/documentation", forType: .string)

        let content = try captured(read(pasteboard))
        XCTAssertEqual(content.kind, .link)
        XCTAssertEqual(content.linkURL?.host(), "developer.apple.com")
    }

    func testHexColorString() throws {
        let pasteboard = makePasteboard(testCase: self)
        pasteboard.setString("#1e90ff", forType: .string)

        let content = try captured(read(pasteboard))
        XCTAssertEqual(content.kind, .color)
        XCTAssertEqual(content.colorHex, "#1E90FF")
    }

    func testNSColor() throws {
        let pasteboard = makePasteboard(testCase: self)
        pasteboard.writeObjects([NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)])

        let content = try captured(read(pasteboard))
        XCTAssertEqual(content.kind, .color)
        XCTAssertEqual(content.colorHex, "#FF0000")
    }

    func testConcealedContentIsIgnored() {
        let pasteboard = makePasteboard(testCase: self)
        let item = NSPasteboardItem()
        item.setString("mot-de-passe", forType: .string)
        item.setData(Data(), forType: PasteboardReader.concealedType)
        pasteboard.writeObjects([item])

        XCTAssertEqual(read(pasteboard), .ignored(.concealed))
    }

    func testTransientContentIsIgnored() {
        let pasteboard = makePasteboard(testCase: self)
        let item = NSPasteboardItem()
        item.setString("éphémère", forType: .string)
        item.setData(Data(), forType: PasteboardReader.transientType)
        pasteboard.writeObjects([item])

        XCTAssertEqual(read(pasteboard), .ignored(.transient))
    }

    func testExcludedFrontmostAppIsIgnored() {
        let pasteboard = makePasteboard(testCase: self)
        pasteboard.setString("secret", forType: .string)
        let onePassword = SourceApp(bundleID: "com.1password.1password", name: "1Password")

        XCTAssertEqual(read(pasteboard, excluded: ["com.1password.1password"], frontmost: onePassword), .ignored(.excludedApp("com.1password.1password")))
    }

    func testDeclaredSourceWinsOverFrontmostApp() {
        let pasteboard = makePasteboard(testCase: self)
        let item = NSPasteboardItem()
        item.setString("copié en arrière-plan", forType: .string)
        item.setString("com.bitwarden.desktop", forType: PasteboardReader.sourceType)
        pasteboard.writeObjects([item])

        XCTAssertEqual(read(pasteboard, excluded: ["com.bitwarden.desktop"]), .ignored(.excludedApp("com.bitwarden.desktop")))
    }

    func testOwnWritesAreIgnored() {
        let pasteboard = makePasteboard(testCase: self)
        let item = NSPasteboardItem()
        item.setString("recollé par Copicol", forType: .string)
        item.setString("io.github.romainrg.Copicol", forType: PasteboardReader.sourceType)
        pasteboard.writeObjects([item])

        XCTAssertEqual(read(pasteboard), .ignored(.ownWrite))
    }

    func testEmptyPasteboardIsIgnored() {
        XCTAssertEqual(read(makePasteboard(testCase: self)), .ignored(.empty))
    }

    // MARK: - Aller-retour écriture / lecture

    func testWriterRoundTripPreservesKinds() async throws {
        let store = try makeStore(clock: TestClock(), testCase: self)
        let samples: [CapturedContent] = [
            .text("texte simple"),
            .text("https://www.swift.org"),
            .text("#336699"),
            CapturedContent(kind: .image, imageData: makePNG()),
            CapturedContent(kind: .file, fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")])
        ]
        for sample in samples {
            let item = try await store.ingest(sample).item
            let pasteboard = makePasteboard(testCase: self)
            XCTAssertTrue(PasteboardWriter.write(item, files: store.files, to: pasteboard, plainText: false, sourceBundleID: nil))

            let content = try captured(read(pasteboard))
            XCTAssertEqual(content.kind, sample.kind)
            XCTAssertEqual(ContentHasher.hash(content), item.contentHash, "\(sample.kind)")
        }
    }

    func testPlainTextWriteDropsFormatting() async throws {
        let store = try makeStore(clock: TestClock(), testCase: self)
        let item = try await store.ingest(CapturedContent(kind: .richText, text: "Gras", rtfData: Data("{\\rtf1 Gras}".utf8))).item
        let pasteboard = makePasteboard(testCase: self)

        PasteboardWriter.write(item, files: store.files, to: pasteboard, plainText: true, sourceBundleID: "io.github.romainrg.Copicol")

        XCTAssertEqual(pasteboard.string(forType: .string), "Gras")
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertEqual(pasteboard.string(forType: PasteboardReader.sourceType), "io.github.romainrg.Copicol")
    }
}
