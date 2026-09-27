// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrateStore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "CrateStore", targets: ["CrateStore"]),
        .library(name: "CrateStoreTestSupport", targets: ["CrateStoreTestSupport"]),
    ],
    dependencies: [
        .package(path: "../CrateKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "CrateStore", dependencies: ["CrateKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "CrateStoreTestSupport", dependencies: ["CrateStore", "CrateKit"]),
        .testTarget(name: "CrateStoreTests", dependencies: ["CrateStore", "CrateStoreTestSupport", "CrateKit", .product(name: "GRDB", package: "GRDB.swift")], resources: [.copy("Fixtures/v1.sqlite")]),
    ]
)
