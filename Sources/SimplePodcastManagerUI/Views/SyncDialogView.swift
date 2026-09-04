import AppKit
import SwiftUI
import SimplePodcastManagerCore

struct SyncDialogView: View {
    let plan: SyncPlan?
    let progress: SyncExecutionProgress?
    let isSyncing: Bool
    let isPlanning: Bool
    let planningErrorTitle: String?
    let planningErrorMessage: String?
    let incompleteCopyRecoveryTarget: URL?
    let isReplacementPlanReady: Bool
    let lastResult: SyncResult?
    let lastErrorMessage: String?
    let preparedEpisodeCount: Int
    let enabledSubscriptionCount: Int
    let cleanupMaximumEpisodesPerPodcast: Int?
    @Binding var isPresented: Bool
    @Binding var ejectAfterSync: Bool
    @Binding var deleteDownloadsAfterSync: Bool
    let onEjectAfterSyncChange: () -> Void
    let onToggleCleanupDeletion: (URL) -> Void
    let onReplaceIncompleteCopy: (URL) -> Void
    let onSync: () -> Void

    private var hasSuccessfulResult: Bool {
        !isSyncing && lastErrorMessage == nil && lastResult != nil
    }

    private var canSync: Bool {
        guard !isSyncing, !isPlanning, let plan else { return false }
        return plan.actions.contains {
            switch $0 {
            case .copyToDevice, .deleteFromDevice, .ejectDevice:
                return true
            case .skip:
                return false
            }
        }
    }

    private var plannedDeletionTargets: Set<URL> {
        Set((plan?.actions ?? []).compactMap { action in
            guard case .deleteFromDevice(let targetURL, _) = action else { return nil }
            return targetURL.standardizedFileURL
        })
    }

    private var plannedDeletionCount: Int {
        plannedDeletionTargets.count
    }

    private var selectedCleanupDeletionCount: Int {
        guard let plan else { return 0 }
        return plan.cleanupCandidates.count {
            plannedDeletionTargets.contains($0.targetURL.standardizedFileURL)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync Podcasts")
                .font(.title2)
                .fontWeight(.semibold)

            if hasSuccessfulResult {
                successConfirmation
            } else {
                Toggle("Eject when finished", isOn: $ejectAfterSync)
                    .toggleStyle(.checkbox)
                    .onChange(of: ejectAfterSync) {
                        onEjectAfterSyncChange()
                    }

                Toggle("Delete downloaded episodes when finished", isOn: $deleteDownloadsAfterSync)
                    .toggleStyle(.checkbox)

                if let progress, isSyncing {
                    SyncProgressView(progress: progress)
                }

                if let planningErrorMessage {
                    planningErrorCard(
                        title: planningErrorTitle ?? "Cannot Start Sync",
                        message: planningErrorMessage
                    )
                }

                if isReplacementPlanReady {
                    replacementPlanReadyCard
                }

                if plannedDeletionCount > 0 {
                    deletionNotice
                }

                planSummary

                if plan?.cleanupCandidates.isEmpty == false {
                    cleanupReview
                }

                if plan?.actions.isEmpty == false {
                    plannedActions
                }
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()

                Button("Close") {
                    isPresented = false
                }

                if !hasSuccessfulResult, planningErrorMessage == nil {
                    Button(isSyncing ? "Working..." : isPlanning ? "Checking..." : "Sync") {
                        onSync()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSync)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
    }

    private var deletionNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                SyncPresentation.deletionNoticeTitle(
                    selectedCleanupDeletionCount: selectedCleanupDeletionCount
                ),
                systemImage: selectedCleanupDeletionCount > 0 ? "list.number" : "trash"
            )
                .font(.headline)
            Text(
                SyncPresentation.deletionNotice(
                    deletionCount: plannedDeletionCount,
                    selectedCleanupDeletionCount: selectedCleanupDeletionCount,
                    cleanupMaximumEpisodesPerPodcast: cleanupMaximumEpisodesPerPodcast
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cleanupReview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Episodes Suggested for Cleanup")
                .font(.headline)
            Text("Uncheck any episode you want to keep on the MP3 player.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plan?.cleanupCandidates ?? []) { candidate in
                        Toggle(
                            isOn: Binding(
                                get: { plannedDeletionTargets.contains(candidate.targetURL.standardizedFileURL) },
                                set: { _ in onToggleCleanupDeletion(candidate.targetURL) }
                            )
                        ) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.episodeTitle)
                                        .lineLimit(1)
                                    Text("\(candidate.podcastTitle) · \(candidate.publicationDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(SyncPresentation.formattedFileSize(candidate.fileSizeBytes))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }

    private var planSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan Summary")
                .font(.headline)

            if let plan {
                let copyCount = plan.actions.count(where: { if case .copyToDevice = $0 { true } else { false } })
                let deleteCount = plan.actions.count(where: { if case .deleteFromDevice = $0 { true } else { false } })
                let skipCount = plan.actions.count(where: { if case .skip = $0 { true } else { false } })

                Text("\(preparedEpisodeCount) episode\(preparedEpisodeCount == 1 ? "" : "s") ready across \(enabledSubscriptionCount) podcast\(enabledSubscriptionCount == 1 ? "" : "s"), \(copyCount) to copy, \(skipCount) to skip, \(deleteCount) to delete")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } else if isPlanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking actions and available device space...")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if planningErrorMessage == nil {
                Text("Choose a compatible device to build the full plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func planningErrorCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let incompleteCopyRecoveryTarget {
                Button("Replace Incomplete Copy", systemImage: "arrow.triangle.2.circlepath") {
                    onReplaceIncompleteCopy(incompleteCopyRecoveryTarget)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Prepare a sync plan that replaces the incomplete device copy")

                Text("SPM will remove the device copy and copy the prepared episode back in the same sync. Review both actions before starting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var replacementPlanReadyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Replacement Plan Ready", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("SPM is ready to remove the incomplete device copy and copy the complete episode back. Review the actions below, then click Sync.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var successConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Complete")
                .font(.headline)
            Text("Finished. You can close this window.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastResult {
                Text(SyncPresentation.resultSummary(lastResult))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if lastResult.ejected {
                    Text("The device was ejected after the run finished.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var plannedActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planned Actions")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((plan?.actions ?? []).enumerated()), id: \.offset) { _, action in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: SyncPresentation.iconName(for: action))
                                .foregroundStyle(SyncPresentation.iconColor(for: action))
                                .frame(width: 14)
                            Text(action.summaryDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let fileSizeBytes = action.fileSizeBytes {
                                Text(SyncPresentation.formattedFileSize(fileSizeBytes))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: 180)
        }
    }

}

struct SyncProgressView: View {
    let progress: SyncExecutionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
            Text(progress.currentActionDescription ?? "Finishing")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("\(progress.completedCount) of \(progress.totalCount) actions complete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum SyncPresentation {
    static func deletionNoticeTitle(selectedCleanupDeletionCount: Int) -> String {
        selectedCleanupDeletionCount > 0
            ? "Episodes Selected for Cleanup"
            : "Episodes Selected for Removal"
    }

    static func deletionNotice(
        deletionCount: Int,
        selectedCleanupDeletionCount: Int,
        cleanupMaximumEpisodesPerPodcast: Int?
    ) -> String {
        if selectedCleanupDeletionCount > 0, let cleanupMaximumEpisodesPerPodcast {
            let cleanupEpisodeText = "Device Cleanup is set to keep the latest \(cleanupMaximumEpisodesPerPodcast) episodes per podcast. \(selectedCleanupDeletionCount) older episode\(selectedCleanupDeletionCount == 1 ? "" : "s")"
            let otherRemovalCount = deletionCount - selectedCleanupDeletionCount
            let otherRemovalText = otherRemovalCount > 0
                ? " Another \(otherRemovalCount) episode\(otherRemovalCount == 1 ? " is" : "s are") selected for removal."
                : ""
            return "\(cleanupEpisodeText) \(selectedCleanupDeletionCount == 1 ? "is" : "are") selected for cleanup during this sync.\(otherRemovalText) Review the selections below before syncing."
        }

        return "\(deletionCount) episode\(deletionCount == 1 ? " is" : "s are") selected for removal during this sync. Review the planned actions before syncing."
    }

    static func resultSummary(_ result: SyncResult) -> String {
        let finishedText = result.finishedAt?.formatted(date: .omitted, time: .shortened) ?? "now"
        return "Last run at \(finishedText): \(result.copiedCount) copied (\(formattedFileSize(result.copiedBytes))), \(result.deletedCount) deleted (\(formattedFileSize(result.deletedBytes))), \(result.skippedCount) skipped."
    }

    static func formattedFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func iconName(for action: SyncAction) -> String {
        switch action {
        case .copyToDevice: "arrow.down.circle"
        case .deleteFromDevice: "trash"
        case .skip: "arrow.right"
        case .ejectDevice: "eject"
        }
    }

    static func iconColor(for action: SyncAction) -> Color {
        switch action {
        case .deleteFromDevice: .red
        case .copyToDevice: .accentColor
        case .skip, .ejectDevice: .secondary
        }
    }
}
