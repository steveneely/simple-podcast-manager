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
        .executable(
            name: "Podcast Swift",
            targets: ["PodcastSwiftApp"]
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
        .executableTarget(
            name: "PodcastSwiftApp",
            dependencies: ["PodcastSwiftCore", "PodcastSwiftUI"],
            path: "Sources/PodcastSwiftApp"
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
