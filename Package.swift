// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Crew",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Crew",
            targets: ["Crew"]
        ),
    ],
    targets: [
        .target(
            name: "Crew",
            path: "Sources/Crew"
        ),
    ]
)
