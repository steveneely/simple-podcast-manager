import Foundation

public protocol AutomaticDownloadStateStore: Sendable {
    func loadState() throws -> AutomaticDownloadState
    func saveState(_ state: AutomaticDownloadState) throws
}
