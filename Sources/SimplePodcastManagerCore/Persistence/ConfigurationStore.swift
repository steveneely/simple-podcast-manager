import Foundation

public protocol ConfigurationStore: Sendable {
    func loadConfiguration() throws -> AppConfiguration
    func saveConfiguration(_ configuration: AppConfiguration) throws
}
