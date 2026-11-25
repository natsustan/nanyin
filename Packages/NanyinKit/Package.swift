// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NanyinKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NanyinKit", targets: ["NanyinKit"]),
    ],
    targets: [
        .target(name: "NanyinKit"),
        .testTarget(name: "NanyinKitTests", dependencies: ["NanyinKit"]),
    ]
)
