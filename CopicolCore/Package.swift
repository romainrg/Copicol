// swift-tools-version: 5.10
import PackageDescription

// Cœur métier de Copicol : modèles SwiftData, capture/écriture du presse-papiers,
// stockage disque, déduplication, rétention, recherche et miroir iCloud.
// Bibliothèque statique : aucun framework dynamique à embarquer ni à signer.
let package = Package(
    name: "CopicolCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CopicolCore", targets: ["CopicolCore"])
    ],
    targets: [
        .target(name: "CopicolCore"),
        .testTarget(name: "CopicolCoreTests", dependencies: ["CopicolCore"])
    ]
)
