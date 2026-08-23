import Foundation
import OSLog

@MainActor
final class StartupPerformanceTracker {
    private let logger = Logger(
        subsystem: "com.steveneely.simple-podcast-manager",
        category: "StartupPerformance"
    )
    private let startTime = ContinuousClock.now

    func mark(_ milestone: String) {
        let elapsed = startTime.duration(to: .now)
        let milliseconds = elapsed.components.seconds * 1_000
            + Int64(elapsed.components.attoseconds / 1_000_000_000_000_000)
        logger.notice("Startup milestone: \(milestone, privacy: .public) at \(milliseconds) ms")
    }
}
