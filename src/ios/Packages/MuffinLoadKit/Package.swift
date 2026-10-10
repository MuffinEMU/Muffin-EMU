// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MuffinLoadKit",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "LoadKit", targets: ["LoadKit"]),
    ],
    targets: [
        .target(name: "LoadKit"),
        .executableTarget(name: "loadkit-check", dependencies: ["LoadKit"]),
    ]
)
