import Foundation

public struct PreparationProgress: Equatable, Sendable {
    public var totalCount: Int
    public var completedCount: Int
    public var currentEpisodeID: String?
    public var currentEpisodeTitle: String?
    public var activeEpisodeIDs: [String]
    public var activeEpisodeTitles: [String]

    public init(
        totalCount: Int,
        completedCount: Int,
        currentEpisodeID: String? = nil,
        currentEpisodeTitle: String? = nil,
        activeEpisodeIDs: [String] = [],
        activeEpisodeTitles: [String] = []
    ) {
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.currentEpisodeID = currentEpisodeID
        self.currentEpisodeTitle = currentEpisodeTitle
        self.activeEpisodeIDs = activeEpisodeIDs
        self.activeEpisodeTitles = activeEpisodeTitles
    }

    public var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}
