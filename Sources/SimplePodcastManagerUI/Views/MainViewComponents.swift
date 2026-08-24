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

struct DeviceSectionView<SyncControls: View, OtherAudio: View>: View {
    @Bindable var viewModel: DeviceViewModel
    @Binding var isShowingDetails: Bool
    let libraryErrorMessage: String?
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

struct FeedSidebarView: View {
    let subscriptions: [FeedSubscription]
    @Binding var selectedFeedID: FeedSubscription.ID?
    let isRefreshing: Bool
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
        }
        .padding(14)
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

struct OtherAudioSectionView: View {
    let files: [URL]
    let selectedFiles: Set<URL>
    let relativePath: (URL) -> String
    let onToggleSelection: (URL) -> Void
    let onDeleteSelected: () -> Void

    private var fileListHeight: CGFloat {
        let rowHeight: CGFloat = 22
        let maximumListHeight: CGFloat = 96
        return min(CGFloat(files.count) * rowHeight, maximumListHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Other Audio on Device")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Delete Selected", action: onDeleteSelected)
                    .disabled(selectedFiles.isEmpty)
            }

            Text("These files are under the device podcast folder but are not associated with a podcast subscription. They are never deleted by Sync.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(files, id: \.path) { fileURL in
                        let standardizedURL = fileURL.standardizedFileURL
                        Button {
                            onToggleSelection(fileURL)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedFiles.contains(standardizedURL) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedFiles.contains(standardizedURL) ? Color.red : Color.secondary)
                                Text(relativePath(fileURL))
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: fileListHeight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
