// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SimplePodcastManager",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SimplePodcastManagerCore",
            targets: ["SimplePodcastManagerCore"]
        ),
        .library(
            name: "SimplePodcastManagerUI",
            targets: ["SimplePodcastManagerUI"]
        ),
        .executable(
            name: "Simple Podcast Manager",
            targets: ["SimplePodcastManagerApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit", from: "10.4.0"),
    ],
    targets: [
        .target(
            name: "SimplePodcastManagerCore",
            dependencies: [
                .product(name: "FeedKit", package: "FeedKit"),
            ],
            path: "Sources/SimplePodcastManagerCore"
        ),
        .target(
            name: "SimplePodcastManagerUI",
            dependencies: ["SimplePodcastManagerCore"],
            path: "Sources/SimplePodcastManagerUI"
        ),
        .executableTarget(
            name: "SimplePodcastManagerApp",
            dependencies: ["SimplePodcastManagerCore", "SimplePodcastManagerUI"],
            path: "Sources/SimplePodcastManagerApp"
        ),
        .testTarget(
            name: "SimplePodcastManagerCoreTests",
            dependencies: ["SimplePodcastManagerCore"],
            path: "Tests/SimplePodcastManagerCoreTests"
        ),
        .testTarget(
            name: "SimplePodcastManagerUITests",
            dependencies: ["SimplePodcastManagerUI", "SimplePodcastManagerCore"],
            path: "Tests/SimplePodcastManagerUITests"
        ),
    ]
)
