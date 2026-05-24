// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "Gokan",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GokanCore", targets: ["GokanCore"]),
        .library(name: "GokanEngine", targets: ["GokanEngine"]),
        .library(name: "GokanModels", targets: ["GokanModels"]),
        .library(name: "GokanUI", targets: ["GokanUI"]),
        .executable(name: "GokanMacApp", targets: ["GokanMacApp"]),
    ],
    targets: [
        .target(name: "GokanCore"),
        .target(
            name: "GokanEngine",
            dependencies: ["GokanCore"]
        ),
        .target(name: "GokanModels"),
        .target(
            name: "GokanUI",
            dependencies: ["GokanCore", "GokanEngine", "GokanModels"]
        ),
        .executableTarget(
            name: "GokanMacApp",
            dependencies: ["GokanUI"]
        ),
        .testTarget(
            name: "GokanCoreTests",
            dependencies: ["GokanCore"]
        ),
        .testTarget(
            name: "GokanEngineTests",
            dependencies: ["GokanEngine"]
        ),
        .testTarget(
            name: "GokanModelsTests",
            dependencies: ["GokanModels"]
        ),
        .testTarget(
            name: "GokanUITests",
            dependencies: ["GokanUI", "GokanCore", "GokanEngine"]
        ),
    ]
)
