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
<<<<<<< HEAD
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.1"),
=======
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.0"),
>>>>>>> worker-2
    ],
    targets: [
        .executableTarget(
            name: "Crew",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
<<<<<<< HEAD
            path: "Sources/Crew",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
=======
            path: "Sources/Crew"
>>>>>>> worker-2
        ),
        .testTarget(
            name: "CrewTests",
            dependencies: ["Crew"],
            path: "Tests/CrewTests"
        )
    ]
)
