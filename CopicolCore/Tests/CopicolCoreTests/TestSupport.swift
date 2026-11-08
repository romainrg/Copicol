import AppKit
import CopicolCore
import UniformTypeIdentifiers
import XCTest

/// Horloge contrôlée par les tests.
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Store en mémoire + dossier de fichiers temporaire, nettoyé à la fin du test.
@MainActor
func makeStore(clock: TestClock, testCase: XCTestCase) throws -> ClipStore {
    let containers = try StorageFactory.makeInMemoryContainers()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CopicolTests-\(UUID().uuidString)")
    testCase.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    let store = ClipStore(localContainer: containers.local, boardContainer: containers.boards, files: FileStore(root: root))
    store.now = { clock.now }
    return store
}

/// Presse-papiers privé : n'interfère jamais avec le presse-papiers général de la session.
func makePasteboard(testCase: XCTestCase) -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("CopicolTests-\(UUID().uuidString)"))
    pasteboard.clearContents()
    testCase.addTeardownBlock { pasteboard.releaseGlobally() }
    return pasteboard
}

func makePNG(width: Int = 8, height: Int = 8, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
let notes = SourceApp(bundleID: "com.apple.Notes", name: "Notes")
