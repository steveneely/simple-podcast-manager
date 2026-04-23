// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SpodcastManaager",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SpodcastManaagerCore",
            targets: ["SpodcastManaagerCore"]
        ),
        .library(
            name: "SpodcastManaagerUI",
            targets: ["SpodcastManaagerUI"]
        ),
        .executable(
            name: "Spodcast Manaager",
            targets: ["SpodcastManaagerApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit", from: "10.4.0"),
    ],
    targets: [
        .target(
            name: "SpodcastManaagerCore",
            dependencies: [
                .product(name: "FeedKit", package: "FeedKit"),
            ],
            path: "Sources/SpodcastManaagerCore"
        ),
        .target(
            name: "SpodcastManaagerUI",
            dependencies: ["SpodcastManaagerCore"],
            path: "Sources/SpodcastManaagerUI"
        ),
        .executableTarget(
            name: "SpodcastManaagerApp",
            dependencies: ["SpodcastManaagerCore", "SpodcastManaagerUI"],
            path: "Sources/SpodcastManaagerApp"
        ),
        .testTarget(
            name: "SpodcastManaagerCoreTests",
            dependencies: ["SpodcastManaagerCore"],
            path: "Tests/SpodcastManaagerCoreTests"
        ),
        .testTarget(
            name: "SpodcastManaagerUITests",
            dependencies: ["SpodcastManaagerUI", "SpodcastManaagerCore"],
            path: "Tests/SpodcastManaagerUITests"
        ),
    ]
)
