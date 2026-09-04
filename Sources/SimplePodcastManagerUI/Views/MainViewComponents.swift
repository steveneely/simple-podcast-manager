import AppKit
import SwiftUI
import SimplePodcastManagerCore

enum FeedSelectionPolicy {
    static let initialSelection: FeedSubscription.ID? = nil

    static func selectionAfterRemovingFeeds(
        currentSelection: FeedSubscription.ID?,
        remainingSubscriptions: [FeedSubscription]
    ) -> FeedSubscription.ID? {
        guard let currentSelection else { return nil }
        return remainingSubscriptions.contains(where: { $0.id == currentSelection })
            ? currentSelection
            : nil
    }
}

enum FeedSidebarActivityStatus: Equatable {
    case newEpisodes(Int)
    case inactive
}

enum DownloadStatusPresentation {
    static func text(count: Int, isAutomatic: Bool) -> String {
        if isAutomatic {
            return "\(count) automatic download\(count == 1 ? "" : "s")"
        }
        return "\(count) downloading"
    }
}

struct DeviceSectionView<SyncControls: View, OtherAudio: View>: View {
    @Bindable var viewModel: DeviceViewModel
    @Binding var isShowingDetails: Bool
    let libraryErrorMessage: String?
    let downloadStatusText: String?
    let deviceSelection: Binding<String>
    let onDisconnect: () -> Void
    let onRefresh: () -> Void
    @ViewBuilder let syncControls: SyncControls
    @ViewBuilder let otherAudio: OtherAudio

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device")
                        .font(.headline)
                    if let selectedDevice = viewModel.selectedDevice {
                        Button(viewModel.statusMessage) {
                            isShowingDetails.toggle()
                        }
                        .buttonStyle(.link)
                        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(selectedDevice.name)
                                    .font(.headline)
                                Text("Mounted at: \(selectedDevice.rootURL.path)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Podcast folder: \(selectedDevice.podcastDirectoryURL.path)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(minWidth: 320, alignment: .leading)
                        }
                    } else {
                        Text(viewModel.statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let downloadStatusText {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(downloadStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if viewModel.selectedDevice != nil {
                    HoverIconButton(
                        systemName: "eject",
                        helpText: viewModel.isDisconnecting ? "Disconnecting device" : "Disconnect device",
                        isDisabled: viewModel.isDisconnecting,
                        action: onDisconnect
                    )
                }

                HoverIconButton(
                    systemName: "arrow.clockwise",
                    helpText: "Refresh devices",
                    action: onRefresh
                )
            }

            if viewModel.hasMultipleDevices {
                Picker("Target device", selection: deviceSelection) {
                    Text("Choose a device")
                        .tag("")
                    ForEach(viewModel.devices) { device in
                        Text(device.name)
                            .tag(device.id)
                    }
                }
                .pickerStyle(.menu)
            }

            syncControls
            otherAudio

            if let errorMessage = viewModel.lastErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let libraryErrorMessage {
                Text(libraryErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

enum FeedRefreshDisplayScope: Equatable {
    case allShows
    case show(String)

    var progressText: String {
        switch self {
        case .allShows:
            "Checking shows…"
        case let .show(title):
            "Checking \(title)…"
        }
    }
}

struct FeedRefreshSummary: Equatable {
    var scope: FeedRefreshDisplayScope
    var discoveredEpisodeCount: Int?
    var downloadedEpisodes: [FeedRefreshDownloadedEpisode]
    var failedSubscriptionCount: Int

    var downloadedEpisodeCount: Int { downloadedEpisodes.count }

    var text: String {
        var parts: [String] = []
        if let discoveredEpisodeCount {
            parts.append(episodeText(discoveredEpisodeCount))
        }
        if discoveredEpisodeCount.map({ $0 > 0 }) == true || downloadedEpisodeCount > 0 {
            parts.append("\(downloadedEpisodeCount) downloaded")
        }
        if failedSubscriptionCount > 0 {
            let showLabel = failedSubscriptionCount == 1 ? "show" : "shows"
            parts.append("\(failedSubscriptionCount) \(showLabel) failed")
        }

        let result = parts.joined(separator: " · ")
        switch scope {
        case .allShows:
            return result
        case let .show(title):
            return "\(title): \(result)"
        }
    }

    private func episodeText(_ discoveredEpisodeCount: Int) -> String {
        guard discoveredEpisodeCount > 0 else { return "No new episodes" }
        let episodeLabel = discoveredEpisodeCount == 1 ? "episode" : "episodes"
        return "\(discoveredEpisodeCount) new \(episodeLabel)"
    }
}

struct FeedRefreshDownloadedEpisode: Equatable, Identifiable {
    let id: String
    let episodeTitle: String
    let podcastTitle: String

    init(_ episode: Episode) {
        let sourceID = episode.subscriptionID?.uuidString ?? episode.sourceFeedURL.absoluteString
        self.id = "\(sourceID)|\(episode.id)"
        self.episodeTitle = episode.title
        self.podcastTitle = episode.podcastTitle
    }

    static func merging(
        _ existingEpisodes: [FeedRefreshDownloadedEpisode],
        with newEpisodes: [FeedRefreshDownloadedEpisode]
    ) -> [FeedRefreshDownloadedEpisode] {
        var episodeIDs = Set(existingEpisodes.map(\.id))
        return existingEpisodes + newEpisodes.filter { episodeIDs.insert($0.id).inserted }
    }
}

enum FeedRefreshStatus: Equatable {
    case refreshing(FeedRefreshDisplayScope)
    case completed(FeedRefreshSummary)

    var isRefreshing: Bool {
        if case .refreshing = self { return true }
        return false
    }
}

struct FeedSidebarView: View {
    @State private var isShowingDownloadedEpisodes = false

    let subscriptions: [FeedSubscription]
    @Binding var selectedFeedID: FeedSubscription.ID?
    let isRefreshing: Bool
    let refreshStatus: FeedRefreshStatus?
    let episodeCount: (FeedSubscription) -> Int
    let newEpisodeCount: (FeedSubscription) -> Int
    let isInactive: (FeedSubscription) -> Bool
    let newestPublicationDate: (FeedSubscription) -> Date?
    let hasFeedIssue: (FeedSubscription) -> Bool
    let artworkURL: (FeedSubscription) -> URL?
    let allowsInsecureArtwork: (FeedSubscription) -> Bool
    let onAdd: () -> Void
    let onRefresh: () -> Void
    let onRefreshSubscription: (FeedSubscription) -> Void
    let onEdit: (FeedSubscription) -> Void
    let onDelete: (FeedSubscription) -> Void
    let onDeleteOffsets: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shows")
                    .font(.headline)
                Spacer()

                HoverIconButton(systemName: "plus", helpText: "Add show", action: onAdd)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                        .help("Loading feeds")
                } else {
                    HoverIconButton(
                        systemName: "arrow.clockwise",
                        helpText: "Refresh shows",
                        action: onRefresh
                    )
                }
            }

            List {
                ForEach(subscriptions) { subscription in
                    let count = episodeCount(subscription)
                    let isSelected = selectedFeedID == subscription.id
                    let hasIssue = hasFeedIssue(subscription)
                    let activityStatus = Self.activityStatus(
                        newEpisodeCount: newEpisodeCount(subscription),
                        isInactive: isInactive(subscription),
                        hasFeedIssue: hasIssue,
                        isEnabled: subscription.isEnabled
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            selectedFeedID = Self.selection(
                                afterClicking: subscription.id,
                                currentSelection: selectedFeedID
                            )
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                PodcastArtworkView(
                                    artworkURL: artworkURL(subscription),
                                    allowsInsecureHTTP: allowsInsecureArtwork(subscription),
                                    size: 42,
                                    cornerRadius: 9
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(subscription.title)
                                            .font(.headline)
                                        if !subscription.isEnabled {
                                            Text("Disabled")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if isRefreshing && count == 0 {
                                        Text("Loading episodes…")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        HStack(spacing: 4) {
                                            Text("\(count) episode\(count == 1 ? "" : "s")")

                                            switch activityStatus {
                                            case let .newEpisodes(newCount):
                                                Text("·")
                                                Text(Self.newEpisodeLabel(for: newCount))
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(Color.accentColor)
                                                    .help("\(newCount) new episode\(newCount == 1 ? "" : "s")")
                                            case .inactive:
                                                Text("·")
                                                Text("Inactive")
                                                    .foregroundStyle(Color.orange)
                                                    .help(inactiveHelpText(for: subscription))
                                            case nil:
                                                EmptyView()
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if subscription.isEnabled && hasIssue {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .help("This feed had a refresh problem")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isSelected {
                            HStack(spacing: 4) {
                                if isRefreshing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 28, height: 28)
                                        .help("Refreshing")
                                } else {
                                    HoverIconButton(
                                        systemName: "arrow.clockwise",
                                        helpText: "Refresh"
                                    ) {
                                        onRefreshSubscription(subscription)
                                    }
                                }
                                HoverIconButton(systemName: "pencil", helpText: "Edit") {
                                    onEdit(subscription)
                                }
                                HoverIconButton(
                                    systemName: "trash",
                                    helpText: "Remove",
                                    isDestructive: true
                                ) {
                                    onDelete(subscription)
                                }
                            }
                            .padding(.leading, 52)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(
                        isSelected ? Color.accentColor.opacity(0.12) : Color.clear
                    )
                }
                .onDelete(perform: onDeleteOffsets)
            }

            refreshStatusFooter
        }
        .padding(14)
    }

    @ViewBuilder
    private var refreshStatusFooter: some View {
        Group {
            switch refreshStatus {
            case let .refreshing(scope):
                VStack(alignment: .leading, spacing: 4) {
                    Text(scope.progressText)
                        .lineLimit(1)
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            case let .completed(summary):
                if summary.downloadedEpisodes.isEmpty {
                    Text(summary.text)
                        .lineLimit(1)
                        .help(summary.text)
                } else {
                    Button {
                        isShowingDownloadedEpisodes.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(summary.text)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Show downloaded episodes")
                    .popover(isPresented: $isShowingDownloadedEpisodes, arrowEdge: .bottom) {
                        downloadedEpisodesPopover(summary.downloadedEpisodes)
                    }
                }
            case nil:
                Color.clear
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func downloadedEpisodesPopover(
        _ downloadedEpisodes: [FeedRefreshDownloadedEpisode]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloaded Episodes")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(downloadedEpisodes) { episode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.episodeTitle)
                                .fontWeight(.medium)
                            Text(episode.podcastTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    static func selection(
        afterClicking subscriptionID: FeedSubscription.ID,
        currentSelection: FeedSubscription.ID?
    ) -> FeedSubscription.ID? {
        currentSelection == subscriptionID ? nil : subscriptionID
    }

    static func activityStatus(
        newEpisodeCount: Int,
        isInactive: Bool,
        hasFeedIssue: Bool,
        isEnabled: Bool
    ) -> FeedSidebarActivityStatus? {
        guard isEnabled, !hasFeedIssue else { return nil }
        if newEpisodeCount > 0 {
            return .newEpisodes(newEpisodeCount)
        }
        return isInactive ? .inactive : nil
    }

    static func newEpisodeLabel(for count: Int) -> String {
        count > 99 ? "99+ new" : "\(count) new"
    }

    private func inactiveHelpText(for subscription: FeedSubscription) -> String {
        guard let date = newestPublicationDate(subscription) else { return "No recent episodes" }
        return "Latest episode published \(date.formatted(date: .long, time: .omitted))"
    }
}

struct OtherAudioReviewView: View {
    let deviceName: String
    let podcastDirectoryPath: String
    let files: [URL]
    let selectedFiles: Set<URL>
    let isReviewing: Bool
    let inspectedFileCount: Int
    let reviewMessage: String?
    let errorMessage: String?
    let relativePath: (URL) -> String
    let onToggleSelection: (URL) -> Void
    let onReview: () -> Void
    let onCancelReview: () -> Void
    let onDeleteSelected: () -> Void
    let onClose: () -> Void

    private var selectionDescription: String {
        let count = selectedFiles.count
        return "\(count) file\(count == 1 ? "" : "s") selected"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if isReviewing {
                    reviewingContent
                } else if !files.isEmpty {
                    resultsContent
                } else if let errorMessage {
                    errorContent(errorMessage)
                } else {
                    emptyContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Review Device Audio")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("\(deviceName)  ·  \(podcastDirectoryPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HoverIconButton(systemName: "xmark", helpText: "Close review", action: onClose)
        }
        .padding(20)
    }

    private var reviewingContent: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Checking the podcast folder…")
                .font(.headline)
            Text("\(inspectedFileCount.formatted()) files checked")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Large libraries may take a moment. You can cancel without changing anything on the device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(32)
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(files.count.formatted()) other audio file\(files.count == 1 ? "" : "s") found")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("These files are not associated with a podcast in Simple Podcast Manager. Sync always leaves them untouched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(files, id: \.path) { fileURL in
                        fileRow(fileURL)
                        if fileURL != files.last {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .padding(20)
    }

    private func fileRow(_ fileURL: URL) -> some View {
        let standardizedURL = fileURL.standardizedFileURL
        let isSelected = selectedFiles.contains(standardizedURL)

        return Button {
            onToggleSelection(fileURL)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.red : Color.secondary)
                Text(relativePath(fileURL))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isSelected ? Color.red.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(relativePath(fileURL))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var emptyContent: some View {
        ContentUnavailableView(
            "No Other Audio Found",
            systemImage: "checkmark.circle",
            description: Text(reviewMessage ?? "The podcast folder contains only audio managed by Simple Podcast Manager.")
        )
    }

    private func errorContent(_ message: String) -> some View {
        ContentUnavailableView(
            "Couldn’t Review Device Audio",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if !files.isEmpty {
                Text(selectionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isReviewing {
                Button("Cancel", action: onCancelReview)
            } else {
                Button("Check Again", systemImage: "arrow.clockwise", action: onReview)
                    .disabled(!files.isEmpty && !selectedFiles.isEmpty)

                Button("Close", action: onClose)

                if !files.isEmpty {
                    Button("Delete Selected…", role: .destructive, action: onDeleteSelected)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(selectedFiles.isEmpty)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct EpisodeDetailsView: View {
    let episode: Episode
    let durationLabel: String?
    let downloadLabel: String?
    let downloadWarnings: [String]
    let removedLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let description = episode.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty
            {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 5) {
                detailRow(label: "Podcast", value: episode.podcastTitle)
                if let publicationDate = episode.publicationDate {
                    detailRow(
                        label: "Published",
                        value: publicationDate.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if let durationLabel {
                    detailRow(label: "Length", value: durationLabel)
                }
                if let downloadLabel {
                    detailRow(label: "Download", value: downloadLabel)
                }
                ForEach(downloadWarnings, id: \.self) { warning in
                    detailRow(label: "Warning", value: warning)
                }
                if let removedLabel {
                    detailRow(label: "Device", value: removedLabel)
                }
                urlRow(label: "Media URL", url: episode.enclosureURL)
                urlRow(label: "Feed URL", url: episode.sourceFeedURL)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            detailLabel(label)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func urlRow(label: String, url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            detailLabel(label)
            Link(url.absoluteString, destination: url)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailLabel(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
    }
}
