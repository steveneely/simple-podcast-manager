import Foundation

public protocol MediaWorkspaceProviding: Sendable {
    func makeWorkspace() throws -> URL
}
