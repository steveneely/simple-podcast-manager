// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "PodcastSwift",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "PodcastSwiftCore",
            targets: ["PodcastSwiftCore"]
        ),
        .library(
            name: "PodcastSwiftUI",
            targets: ["PodcastSwiftUI"]
        ),
    ],
    targets: [
        .target(
            name: "PodcastSwiftCore",
            path: "Sources/PodcastSwiftCore"
        ),
        .target(
            name: "PodcastSwiftUI",
            dependencies: ["PodcastSwiftCore"],
            path: "Sources/PodcastSwiftUI"
        ),
        .testTarget(
            name: "PodcastSwiftCoreTests",
            dependencies: ["PodcastSwiftCore"],
            path: "Tests/PodcastSwiftCoreTests"
        ),
        .testTarget(
            name: "PodcastSwiftUITests",
            dependencies: ["PodcastSwiftUI", "PodcastSwiftCore"],
            path: "Tests/PodcastSwiftUITests"
        ),
    ]
)
