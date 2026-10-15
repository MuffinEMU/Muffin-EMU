// swift-tools-version: 5.9
// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

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
