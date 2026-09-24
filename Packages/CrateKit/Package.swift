// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CrateKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CrateKit", targets: ["CrateKit"]),
    ],
    targets: [
        .target(name: "CrateKit"),
        .testTarget(name: "CrateKitTests", dependencies: ["CrateKit"]),
    ]
)
