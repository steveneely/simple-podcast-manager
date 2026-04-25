import Foundation

public struct GitHubUpdateChecker: UpdateChecking {
    private let releasesURL: URL
    private let session: URLSession

    public init(
        releasesURL: URL = URL(string: "https://api.github.com/repos/steveneely/simple-podcast-manager/releases?per_page=20")!,
        session: URLSession = CachedHTTPSession.shared
    ) {
        self.releasesURL = releasesURL
        self.session = session
    }

    public func checkForUpdates(currentReleaseTag: String?) async throws -> UpdateCheckResult {
        var request = URLRequest(url: releasesURL)
        request.setValue("SimplePodcastManager", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.requestFailed
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        guard let latestRelease = releases.first(where: { !$0.draft })?.appRelease else {
            throw UpdateCheckError.noReleasesFound
        }

        return UpdateCheckResult(
            latestRelease: latestRelease,
            isUpdateAvailable: Self.isUpdateAvailable(currentReleaseTag: currentReleaseTag, latestReleaseTag: latestRelease.tagName),
            currentReleaseTag: currentReleaseTag
        )
    }

    public static func isUpdateAvailable(currentReleaseTag: String?, latestReleaseTag: String) -> Bool {
        guard let currentReleaseTag, currentReleaseTag != latestReleaseTag else {
            return false
        }

        guard
            let currentVersion = ReleaseVersion(tag: currentReleaseTag),
            let latestVersion = ReleaseVersion(tag: latestReleaseTag)
        else {
            return currentReleaseTag != latestReleaseTag
        }

        return currentVersion < latestVersion
    }
}

public enum UpdateCheckError: LocalizedError, Equatable, Sendable {
    case requestFailed
    case noReleasesFound

    public var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Could not check GitHub releases."
        case .noReleasesFound:
            return "No app releases were found."
        }
    }
}

private struct GitHubRelease: Decodable {
    var name: String?
    var tagName: String
    var htmlURL: URL
    var draft: Bool
    var prerelease: Bool

    var appRelease: AppRelease {
        AppRelease(
            name: name ?? tagName,
            tagName: tagName,
            htmlURL: htmlURL,
            isPrerelease: prerelease
        )
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

private struct ReleaseVersion: Comparable {
    var major: Int
    var minor: Int
    var patch: Int
    var prereleaseName: String?
    var prereleaseNumber: Int?

    init?(tag: String) {
        let trimmedTag = tag.trimmingPrefix("v")
        let parts = trimmedTag.split(separator: "-", maxSplits: 1).map(String.init)
        let versionParts = parts[0].split(separator: ".").compactMap { Int($0) }
        guard versionParts.count == 3 else { return nil }

        self.major = versionParts[0]
        self.minor = versionParts[1]
        self.patch = versionParts[2]

        if parts.count > 1 {
            let prereleaseParts = parts[1].split(separator: ".", maxSplits: 1).map(String.init)
            self.prereleaseName = prereleaseParts.first
            if prereleaseParts.count > 1 {
                self.prereleaseNumber = Int(prereleaseParts[1])
            }
        }
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prereleaseName, rhs.prereleaseName) {
        case (.none, .some):
            return false
        case (.some, .none):
            return true
        case (.none, .none):
            return false
        case (.some(let lhsName), .some(let rhsName)):
            if lhsName != rhsName { return lhsName < rhsName }
            return (lhs.prereleaseNumber ?? 0) < (rhs.prereleaseNumber ?? 0)
        }
    }
}
