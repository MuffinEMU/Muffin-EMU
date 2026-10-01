// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MuffinTouchLab",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TouchLabCore", targets: ["TouchLabCore"]),
        .library(name: "TouchLabUI", targets: ["TouchLabUI"]),
    ],
    targets: [
        // Platform-free: touch model, schemes, mixer. Builds and is checked on macOS.
        .target(name: "TouchLabCore"),
        // UIKit view + SwiftUI wrapper. iOS only; compiles to nothing elsewhere.
        .target(name: "TouchLabUI", dependencies: ["TouchLabCore"]),
        // `swift run touchlab-check` - behaviour and layout checks. An executable rather
        // than a test target so it runs with Command Line Tools alone (no XCTest there).
        .executableTarget(name: "touchlab-check", dependencies: ["TouchLabCore"]),
        // `swift run touchlab-render <dir>` - SVG previews of every scheme on every
        // target device.
        .executableTarget(name: "touchlab-render", dependencies: ["TouchLabCore"]),
    ]
)
