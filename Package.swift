// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipMaster",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClipMaster",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "HotKey",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "ClipMaster",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "ClipMasterTests",
            dependencies: ["ClipMaster"],
            path: "Tests/ClipMasterTests"
        ),
    ]
)
