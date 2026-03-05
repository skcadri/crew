// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Crew",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Crew", targets: ["Crew"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Crew",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            path: "Sources/Crew"
        ),
        .testTarget(
            name: "CrewTests",
            dependencies: ["Crew"],
            path: "Tests/CrewTests"
        )
    ]
)
