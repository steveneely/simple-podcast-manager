// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SPodcastManager",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SPodcastManagerCore",
            targets: ["SPodcastManagerCore"]
        ),
        .library(
            name: "SPodcastManagerUI",
            targets: ["SPodcastManagerUI"]
        ),
        .executable(
            name: "S Podcast Manager",
            targets: ["SPodcastManagerApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit", from: "10.4.0"),
    ],
    targets: [
        .target(
            name: "SPodcastManagerCore",
            dependencies: [
                .product(name: "FeedKit", package: "FeedKit"),
            ],
            path: "Sources/SPodcastManagerCore"
        ),
        .target(
            name: "SPodcastManagerUI",
            dependencies: ["SPodcastManagerCore"],
            path: "Sources/SPodcastManagerUI"
        ),
        .executableTarget(
            name: "SPodcastManagerApp",
            dependencies: ["SPodcastManagerCore", "SPodcastManagerUI"],
            path: "Sources/SPodcastManagerApp"
        ),
        .testTarget(
            name: "SPodcastManagerCoreTests",
            dependencies: ["SPodcastManagerCore"],
            path: "Tests/SPodcastManagerCoreTests"
        ),
        .testTarget(
            name: "SPodcastManagerUITests",
            dependencies: ["SPodcastManagerUI", "SPodcastManagerCore"],
            path: "Tests/SPodcastManagerUITests"
        ),
    ]
)
