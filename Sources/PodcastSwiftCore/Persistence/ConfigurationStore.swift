import Foundation

public protocol ConfigurationStore {
    func loadConfiguration() throws -> AppConfiguration
    func saveConfiguration(_ configuration: AppConfiguration) throws
}
