import Testing
import Foundation
@testable import SimplePodcastManagerCore

struct AppIdentityTests {
    @Test
    func packagedDevelopmentAppUsesItsOwnCheckoutData() throws {
        let root = try makeCheckout()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "dist/dev/Simple Podcast Manager Dev.app")

        let support = AppIdentity.applicationSupportDirectory(bundleURL: app, isMarkedDevelopment: true)

        #expect(support == developmentData(in: root))
        #expect(AppIdentity.isDevelopmentBuild(bundleURL: app, isMarkedDevelopment: true))
    }

    @Test
    func releaseBundleInsideCheckoutCannotUseInstalledDataOrUpdates() throws {
        let root = try makeCheckout()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "dist/build/Simple Podcast Manager.app")

        #expect(AppIdentity.applicationSupportDirectory(
            bundleURL: app, isDistributionBuild: true
        ) == developmentData(in: root))
        #expect(AppIdentity.isDevelopmentBuild(bundleURL: app, isDistributionBuild: true))
    }

    @Test
    func sourceRunUsesCheckoutDataEvenWithDistributionMetadata() throws {
        let root = try makeCheckout()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: ".build/debug/Simple Podcast Manager")

        #expect(AppIdentity.applicationSupportDirectory(
            bundleURL: executable, isDistributionBuild: true
        ) == developmentData(in: root))
        #expect(AppIdentity.isDevelopmentBuild(bundleURL: executable, isDistributionBuild: true))
    }

    @Test
    func separateWorktreesNeverShareTheirDataDirectory() throws {
        let first = try makeCheckout()
        let second = try makeCheckout()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let firstSupport = AppIdentity.applicationSupportDirectory(
            bundleURL: first.appending(path: "dist/dev/Simple Podcast Manager Dev.app")
        )
        let secondSupport = AppIdentity.applicationSupportDirectory(
            bundleURL: second.appending(path: "dist/dev/Simple Podcast Manager Dev.app")
        )

        #expect(firstSupport == developmentData(in: first))
        #expect(secondSupport == developmentData(in: second))
        #expect(firstSupport != secondSupport)
    }

    @Test
    func developmentMarkerWinsOutsideCheckoutEvenWithDistributionMarker() {
        let bundleURL = URL(fileURLWithPath: "/Applications/Development Copy.app")
        let support = AppIdentity.applicationSupportDirectory(
            bundleURL: bundleURL, isDistributionBuild: true, isMarkedDevelopment: true
        )
        #expect(support.path.contains("/.dev-data/"))
        #expect(AppIdentity.isDevelopmentBuild(
            bundleURL: bundleURL, isDistributionBuild: true, isMarkedDevelopment: true
        ))
    }

    @Test
    func unmarkedBundleDefaultsToDevelopmentInsteadOfInstalledData() {
        let bundleURL = URL(fileURLWithPath: "/Applications/Unmarked Test.app")
        #expect(AppIdentity.applicationSupportDirectory(bundleURL: bundleURL).path.contains("/.dev-data/"))
        #expect(AppIdentity.isDevelopmentBuild(bundleURL: bundleURL))
    }

    @Test
    func explicitlyDistributedAppKeepsExistingProductionStorageLocation() {
        // Resolve a path only; never open or read the installed database.
        let bundleURL = URL(fileURLWithPath: "/Applications/Simple Podcast Manager.app")
        let support = AppIdentity.applicationSupportDirectory(bundleURL: bundleURL, isDistributionBuild: true)
        #expect(support == FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SimplePodcastManager", directoryHint: .isDirectory))
        #expect(!AppIdentity.isDevelopmentBuild(bundleURL: bundleURL, isDistributionBuild: true))
    }

    @Test
    func symlinkToCheckoutCannotBypassDevelopmentIsolation() throws {
        let root = try makeCheckout()
        let alias = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let bundleURL = alias.appending(path: "Simple Podcast Manager.app")
        #expect(AppIdentity.applicationSupportDirectory(
            bundleURL: bundleURL, isDistributionBuild: true
        ) == developmentData(in: root))
    }

    private func makeCheckout() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "Package.swift"))
        return root
    }

    private func developmentData(in root: URL) -> URL {
        root.appending(path: ".dev-data/SimplePodcastManager", directoryHint: .isDirectory)
    }
}
