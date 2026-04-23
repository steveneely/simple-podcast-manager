import Foundation
import Observation
import SpodcastManaagerCore

@MainActor
@Observable
public final class SyncPlanViewModel {
    public private(set) var plan: SyncPlan?
    public private(set) var isPlanning: Bool
    public private(set) var lastErrorMessage: String?

    private let planner: SyncPlanner

    public init(planner: SyncPlanner = SyncPlanner()) {
        self.planner = planner
        self.plan = nil
        self.isPlanning = false
        self.lastErrorMessage = nil
    }

    public var actionDescriptions: [String] {
        guard let plan else { return [] }
        return plan.actions.map(Self.describe(action:))
    }

    public func buildPlan(
        device: DeviceInfo?,
        preparedEpisodes: [PreparedEpisode],
        subscriptions: [FeedSubscription],
        ejectAfterSync: Bool,
        isDryRun: Bool
    ) {
        guard let device else {
            plan = nil
            lastErrorMessage = "Select a compatible device before building a sync plan."
            return
        }

        isPlanning = true
        defer { isPlanning = false }

        do {
            plan = try planner.makePlan(
                device: device,
                preparedEpisodes: preparedEpisodes,
                subscriptions: subscriptions,
                ejectAfterSync: ejectAfterSync,
                isDryRun: isDryRun
            )
            lastErrorMessage = nil
        } catch {
            plan = nil
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func clearPlan() {
        plan = nil
        lastErrorMessage = nil
    }

    private static func describe(action: SyncAction) -> String {
        switch action {
        case .copyToDevice(_, let destinationURL):
            return "Copy to device: \(destinationURL.lastPathComponent)"
        case .deleteFromDevice(let targetURL):
            return "Delete old episode: \(targetURL.lastPathComponent)"
        case .clearDeviceTrash:
            return "Clear device trash"
        case .ejectDevice:
            return "Eject device after sync"
        case .skip(let reason):
            return "Skip: \(reason)"
        }
    }
}
