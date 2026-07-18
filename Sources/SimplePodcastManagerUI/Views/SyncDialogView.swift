import AppKit
import SwiftUI
import SimplePodcastManagerCore

struct SyncDialogView: View {
    let plan: SyncPlan?
    let actionDescriptions: [String]
    let progress: SyncExecutionProgress?
    let isSyncing: Bool
    let isPlanning: Bool
    let lastResult: SyncResult?
    let lastErrorMessage: String?
    let preparedEpisodeCount: Int
    let enabledSubscriptionCount: Int
    let summaryText: String
    @Binding var isPresented: Bool
    @Binding var ejectAfterSync: Bool
    @Binding var deleteDownloadsAfterSync: Bool
    let onEjectAfterSyncChange: () -> Void
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Close") {
                    isPresented = false
                }

                if !hasSuccessfulResult {
                    Button(isSyncing ? "Working..." : "Start") {
                        onSync()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSync)
                }
            }

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

                if let lastResult {
                    resultCard(lastResult)
                }

                planSummary

                if !actionDescriptions.isEmpty {
                    plannedActions
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
    }

    private var planSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan Summary")
                .font(.headline)

            if let plan {
                let copyCount = plan.actions.count(where: { if case .copyToDevice = $0 { true } else { false } })
                let deleteCount = plan.actions.count(where: { if case .deleteFromDevice = $0 { true } else { false } })
                let skipCount = plan.actions.count(where: { if case .skip = $0 { true } else { false } })

                Text("\(preparedEpisodeCount) episode\(preparedEpisodeCount == 1 ? "" : "s") ready across \(enabledSubscriptionCount) show\(enabledSubscriptionCount == 1 ? "" : "s"), \(copyCount) to copy, \(skipCount) to skip, \(deleteCount) to delete")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(plan.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Choose a compatible device to build the full plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                ForEach(lastResult.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func resultCard(_ result: SyncResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last Run")
                .font(.headline)
            Text(SyncPresentation.resultSummary(result))
                .font(.caption)
                .foregroundStyle(.secondary)
            if result.ejected {
                Text("The device was ejected after the run finished.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(result.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
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
                    ForEach(Array(actionDescriptions.enumerated()), id: \.offset) { _, description in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: SyncPresentation.iconName(for: description))
                                .foregroundStyle(SyncPresentation.iconColor(for: description))
                                .frame(width: 14)
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
    static func resultSummary(_ result: SyncResult) -> String {
        let finishedText = result.finishedAt?.formatted(date: .omitted, time: .shortened) ?? "now"
        return "Last run at \(finishedText): \(result.copiedCount) copied, \(result.deletedCount) deleted, \(result.skippedCount) skipped."
    }

    static func iconName(for description: String) -> String {
        if description.hasPrefix("Copy to device") { return "arrow.down.circle" }
        if description.hasPrefix("Delete old episode") { return "trash" }
        if description.hasPrefix("Skip") { return "arrow.right" }
        if description == "Eject device when finished" { return "eject" }
        return "circle"
    }

    static func iconColor(for description: String) -> Color {
        if description.hasPrefix("Delete old episode") { return .red }
        if description.hasPrefix("Copy to device") { return .accentColor }
        return .secondary
    }
}
