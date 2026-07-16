import Foundation

public enum EpisodeSelector {
    public static func isHigherPriority(_ lhs: Episode, than rhs: Episode) -> Bool {
        switch (lhs.publicationDate, rhs.publicationDate) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
