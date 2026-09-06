import AppKit
import SwiftUI
import SimplePodcastManagerCore

enum PodcastSelectionPolicy {
    static let initialSelection: PodcastSubscription.ID? = nil

    static func selectionAfterRemovingPodcasts(
        currentSelection: PodcastSubscription.ID?,
        remainingSubscriptions: [PodcastSubscription]
    ) -> PodcastSubscription.ID? {
        guard let currentSelection else { return nil }
        return remainingSubscriptions.contains(where: { $0.id == currentSelection })
            ? currentSelection
            : nil
    }
}

enum PodcastSidebarActivityStatus: Equatable {
    case newEpisodes(Int)
    case inactive
}

enum PodcastSidebarSortCriterion: Hashable {
    case name
    case recentlyUpdated
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
                        Button {
                            isShowingDetails.toggle()
                        } label: {
                            Label(viewModel.statusMessage, systemImage: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Show device details")
                        .accessibilityLabel("Show device details for \(selectedDevice.name)")
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

enum PodcastRefreshDisplayScope: Equatable {
    case allPodcasts
    case podcast(String)

    func progressText(_ progress: PodcastRefreshProgress?) -> String {
        switch self {
        case .allPodcasts:
            if let progress, progress.totalCount > 0 {
                "Checking podcasts… \(progress.completedCount) of \(progress.totalCount)"
            } else {
                "Checking podcasts…"
            }
        case let .podcast(title):
            "Checking \(title)…"
        }
    }

    func compactProgressText(_ progress: PodcastRefreshProgress?) -> String {
        switch self {
        case .allPodcasts:
            if let progress, progress.totalCount > 0 {
                return "Checking \(progress.completedCount) / \(progress.totalCount)"
            }
            return "Checking podcasts…"
        case .podcast:
            return "Checking podcast…"
        }
    }
}

struct PodcastRefreshProgress: Equatable {
    var completedCount: Int
    var totalCount: Int
}

struct PodcastRefreshSummary: Equatable {
    var scope: PodcastRefreshDisplayScope
    var checkedPodcastCount: Int?
    var discoveredEpisodeCount: Int?
    var downloadedEpisodes: [PodcastRefreshEpisodeDetail]
    var remainingNewEpisodes: [PodcastRefreshEpisodeDetail]
    var issues: [PodcastRefreshIssue]

    var downloadedEpisodeCount: Int { downloadedEpisodes.count }

    mutating func recordDownloadedEpisodes(_ episodes: [PodcastRefreshEpisodeDetail]) {
        downloadedEpisodes = PodcastRefreshEpisodeDetail.merging(downloadedEpisodes, with: episodes)
        let downloadedEpisodeIDs = Set(episodes.map(\.id))
        remainingNewEpisodes.removeAll { downloadedEpisodeIDs.contains($0.id) }
    }

    var hasDetails: Bool {
        !downloadedEpisodes.isEmpty || !remainingNewEpisodes.isEmpty || !issues.isEmpty
    }

    var counters: [PodcastRefreshSummaryCounter] {
        var counters: [PodcastRefreshSummaryCounter] = []
        if !remainingNewEpisodes.isEmpty {
            counters.append(PodcastRefreshSummaryCounter(
                count: remainingNewEpisodes.count,
                label: "new",
                systemImage: "circle.fill",
                tone: .newEpisodes,
                accessibilityText: "\(remainingNewEpisodes.count) still new"
            ))
        }
        if downloadedEpisodeCount > 0 {
            counters.append(PodcastRefreshSummaryCounter(
                count: downloadedEpisodeCount,
                label: "downloaded",
                systemImage: "arrow.down.circle.fill",
                tone: .downloaded,
                accessibilityText: "\(downloadedEpisodeCount) downloaded"
            ))
        }
        if !issues.isEmpty {
            counters.append(PodcastRefreshSummaryCounter(
                count: issues.count,
                label: issues.count == 1 ? "issue" : "issues",
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                accessibilityText: issues.count == 1
                    ? "1 needs attention"
                    : "\(issues.count) need attention"
            ))
        }
        return counters
    }

    var collapsedText: String {
        guard !counters.isEmpty else { return "Up to date" }
        return counters.map { "\($0.count) \($0.label)" }.joined(separator: " · ")
    }

    var parts: [PodcastRefreshSummaryPart] {
        var parts: [PodcastRefreshSummaryPart] = []
        if case let .podcast(title) = scope {
            parts.append(PodcastRefreshSummaryPart(text: title, tone: .neutral))
        }
        if case .allPodcasts = scope, let checkedPodcastCount {
            parts.append(PodcastRefreshSummaryPart(text: "\(checkedPodcastCount) checked", tone: .neutral))
        }
        if let discoveredEpisodeCount {
            parts.append(PodcastRefreshSummaryPart(
                text: episodeText(discoveredEpisodeCount),
                tone: .discovery
            ))
        }
        if !remainingNewEpisodes.isEmpty {
            parts.append(PodcastRefreshSummaryPart(
                text: "\(remainingNewEpisodes.count) still new",
                tone: .newEpisodes
            ))
        }
        if downloadedEpisodeCount > 0 {
            parts.append(PodcastRefreshSummaryPart(
                text: "\(downloadedEpisodeCount) downloaded",
                tone: .downloaded
            ))
        }
        if !issues.isEmpty {
            parts.append(PodcastRefreshSummaryPart(
                text: issues.count == 1 ? "1 needs attention" : "\(issues.count) need attention",
                tone: .warning
            ))
        }
        return parts
    }

    var text: String {
        parts.map(\.text).joined(separator: " · ")
    }

    private func episodeText(_ discoveredEpisodeCount: Int) -> String {
        guard discoveredEpisodeCount > 0 else { return "No episodes found" }
        let episodeLabel = discoveredEpisodeCount == 1 ? "episode" : "episodes"
        return "\(discoveredEpisodeCount) \(episodeLabel) found"
    }
}

struct PodcastRefreshSummaryCounter: Equatable, Identifiable {
    var id: PodcastRefreshSummaryPart.Tone { tone }
    let count: Int
    let label: String
    let systemImage: String
    let tone: PodcastRefreshSummaryPart.Tone
    let accessibilityText: String
}

struct PodcastRefreshSummaryPart: Equatable {
    enum Tone: Hashable {
        case neutral
        case discovery
        case newEpisodes
        case downloaded
        case warning
    }

    let text: String
    let tone: Tone
}

struct PodcastRefreshEpisodeDetail: Equatable, Identifiable {
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
        _ existingEpisodes: [PodcastRefreshEpisodeDetail],
        with newEpisodes: [PodcastRefreshEpisodeDetail]
    ) -> [PodcastRefreshEpisodeDetail] {
        var episodeIDs = Set(existingEpisodes.map(\.id))
        return existingEpisodes + newEpisodes.filter { episodeIDs.insert($0.id).inserted }
    }
}

struct PodcastRefreshIssue: Equatable, Identifiable {
    let id: String
    let title: String
    let podcastTitle: String
    let message: String
}

enum PodcastRefreshStatus: Equatable {
    case refreshing(PodcastRefreshDisplayScope)
    case checked(PodcastRefreshDisplayScope, checkedPodcastCount: Int, discoveredEpisodeCount: Int)
    case completed(PodcastRefreshSummary)

    var isActive: Bool {
        switch self {
        case .refreshing, .checked:
            true
        case .completed:
            false
        }
    }
}

struct PodcastSidebarView: View {
    @State private var isShowingDownloadedEpisodes = false

    let subscriptions: [PodcastSubscription]
    @Binding var selectedPodcastID: PodcastSubscription.ID?
    @Binding var sortOrder: PodcastSortOrder
    let isRefreshing: Bool
    let refreshStatus: PodcastRefreshStatus?
    let refreshProgress: PodcastRefreshProgress?
    let episodeCount: (PodcastSubscription) -> Int
    let newEpisodeCount: (PodcastSubscription) -> Int
    let isInactive: (PodcastSubscription) -> Bool
    let newestPublicationDate: (PodcastSubscription) -> Date?
    let hasPodcastIssue: (PodcastSubscription) -> Bool
    let artworkURL: (PodcastSubscription) -> URL?
    let allowsInsecureArtwork: (PodcastSubscription) -> Bool
    let onAdd: () -> Void
    let onRefresh: () -> Void
    let onRefreshSubscription: (PodcastSubscription) -> Void
    let onEdit: (PodcastSubscription) -> Void
    let onDelete: (PodcastSubscription) -> Void
    let onDeleteSubscriptions: ([PodcastSubscription]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    sortOrder = Self.reversedSortOrder(sortOrder)
                } label: {
                    HStack(spacing: 5) {
                        Text("Podcasts")
                            .font(.headline)
                        Image(systemName: Self.sortDirectionIcon(for: sortOrder))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.sortDirectionHelpText(for: sortOrder))
                .help(Self.sortDirectionHelpText(for: sortOrder))

                Spacer()

                HoverIconMenu(
                    systemName: "line.3.horizontal",
                    helpText: "Choose podcast sort field"
                ) {
                    Picker("Sort by", selection: Binding(
                        get: { Self.sortCriterion(for: sortOrder) },
                        set: { sortOrder = Self.defaultSortOrder(for: $0) }
                    )) {
                        Text("Name").tag(PodcastSidebarSortCriterion.name)
                        Text("Recently Updated").tag(PodcastSidebarSortCriterion.recentlyUpdated)
                    }
                }

                HoverIconButton(systemName: "plus", helpText: "Add podcast", action: onAdd)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                        .help("Refreshing podcasts")
                } else {
                    HoverIconButton(
                        systemName: "arrow.clockwise",
                        helpText: "Refresh podcasts",
                        action: onRefresh
                    )
                }
            }

            List {
                let sortedSubscriptions = Self.sortedSubscriptions(
                    subscriptions,
                    by: sortOrder,
                    newestPublicationDate: newestPublicationDate
                )

                ForEach(sortedSubscriptions) { subscription in
                    let count = episodeCount(subscription)
                    let isSelected = selectedPodcastID == subscription.id
                    let hasIssue = hasPodcastIssue(subscription)
                    let activityStatus = Self.activityStatus(
                        newEpisodeCount: newEpisodeCount(subscription),
                        isInactive: isInactive(subscription),
                        hasPodcastIssue: hasIssue,
                        isEnabled: subscription.isEnabled
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            selectedPodcastID = Self.selection(
                                afterClicking: subscription.id,
                                currentSelection: selectedPodcastID
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
                                        .help("This podcast had a refresh problem")
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
                .onDelete { offsets in
                    onDeleteSubscriptions(offsets.compactMap { offset in
                        sortedSubscriptions.indices.contains(offset) ? sortedSubscriptions[offset] : nil
                    })
                }
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
                    ViewThatFits(in: .horizontal) {
                        Text(scope.progressText(refreshProgress))
                            .fixedSize(horizontal: true, vertical: false)
                        Text(scope.compactProgressText(refreshProgress))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .help(scope.progressText(refreshProgress))
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            case let .checked(scope, checkedPodcastCount, discoveredEpisodeCount):
                Label("\(checkedPodcastCount) checked", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .help(PodcastRefreshSummary(
                        scope: scope,
                        checkedPodcastCount: checkedPodcastCount,
                        discoveredEpisodeCount: discoveredEpisodeCount,
                        downloadedEpisodes: [],
                        remainingNewEpisodes: [],
                        issues: []
                    ).text)
            case let .completed(summary):
                if !summary.hasDetails {
                    Label("Up to date", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .help(summary.text)
                } else {
                    Button {
                        isShowingDownloadedEpisodes.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            ViewThatFits(in: .horizontal) {
                                refreshSummaryCounters(summary.counters, includesLabels: true)
                                refreshSummaryCounters(summary.counters, includesLabels: false)
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("\(summary.text). Show refresh details.")
                    .accessibilityLabel(summary.text)
                    .accessibilityHint("Show refresh details")
                    .popover(isPresented: $isShowingDownloadedEpisodes, arrowEdge: .bottom) {
                        refreshDetailsPopover(summary)
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

    private func refreshDetailsPopover(_ summary: PodcastRefreshSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Refresh Details")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if summary.checkedPodcastCount != nil || summary.discoveredEpisodeCount != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            if let checkedPodcastCount = summary.checkedPodcastCount {
                                Text("\(checkedPodcastCount) podcasts checked")
                                    .foregroundStyle(.secondary)
                            }
                            if let discoveredEpisodeCount = summary.discoveredEpisodeCount {
                                Text(discoveredEpisodeCount == 1
                                    ? "1 episode found"
                                    : "\(discoveredEpisodeCount) episodes found")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !summary.downloadedEpisodes.isEmpty {
                        refreshEpisodeSection(
                            "Downloaded",
                            systemImage: "checkmark.circle.fill",
                            color: .green,
                            episodes: summary.downloadedEpisodes
                        )
                    }
                    if !summary.remainingNewEpisodes.isEmpty {
                        refreshEpisodeSection(
                            "Still New",
                            systemImage: "circle.fill",
                            color: .accentColor,
                            episodes: summary.remainingNewEpisodes
                        )
                    }
                    if !summary.issues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Needs Attention", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            ForEach(summary.issues) { issue in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.title)
                                        .fontWeight(.medium)
                                    Text(issue.podcastTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(issue.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    private func refreshEpisodeSection(
        _ title: String,
        systemImage: String,
        color: Color,
        episodes: [PodcastRefreshEpisodeDetail]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            ForEach(episodes) { episode in
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

    private func refreshSummaryCounters(
        _ counters: [PodcastRefreshSummaryCounter],
        includesLabels: Bool
    ) -> some View {
        HStack(spacing: includesLabels ? 12 : 10) {
            ForEach(counters) { counter in
                HStack(spacing: 4) {
                    Image(systemName: counter.systemImage)
                    Text(includesLabels ? "\(counter.count) \(counter.label)" : "\(counter.count)")
                        .monospacedDigit()
                }
                .foregroundStyle(summaryColor(for: counter.tone))
                .fixedSize(horizontal: true, vertical: false)
                .help(counter.accessibilityText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(counter.accessibilityText)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func summaryColor(for tone: PodcastRefreshSummaryPart.Tone) -> Color {
        switch tone {
        case .neutral:
            .secondary
        case .discovery:
            .primary
        case .newEpisodes:
            .accentColor
        case .downloaded:
            .green
        case .warning:
            .orange
        }
    }

    static func selection(
        afterClicking subscriptionID: PodcastSubscription.ID,
        currentSelection: PodcastSubscription.ID?
    ) -> PodcastSubscription.ID? {
        currentSelection == subscriptionID ? nil : subscriptionID
    }

    static func activityStatus(
        newEpisodeCount: Int,
        isInactive: Bool,
        hasPodcastIssue: Bool,
        isEnabled: Bool
    ) -> PodcastSidebarActivityStatus? {
        guard isEnabled, !hasPodcastIssue else { return nil }
        if newEpisodeCount > 0 {
            return .newEpisodes(newEpisodeCount)
        }
        return isInactive ? .inactive : nil
    }

    static func newEpisodeLabel(for count: Int) -> String {
        count > 99 ? "99+ new" : "\(count) new"
    }

    static func sortedSubscriptions(
        _ subscriptions: [PodcastSubscription],
        by sortOrder: PodcastSortOrder,
        newestPublicationDate: (PodcastSubscription) -> Date?
    ) -> [PodcastSubscription] {
        subscriptions.sorted { first, second in
            if sortOrder == .recentlyUpdated || sortOrder == .leastRecentlyUpdated {
                switch (newestPublicationDate(first), newestPublicationDate(second)) {
                case let (firstDate?, secondDate?) where firstDate != secondDate:
                    return sortOrder == .recentlyUpdated
                        ? firstDate > secondDate
                        : firstDate < secondDate
                case (_?, nil):
                    return sortOrder == .recentlyUpdated
                case (nil, _?):
                    return sortOrder == .leastRecentlyUpdated
                default:
                    break
                }
            }

            let titleComparison = first.title.localizedCaseInsensitiveCompare(second.title)
            if titleComparison != .orderedSame {
                return sortOrder == .reverseAlphabetic
                    ? titleComparison == .orderedDescending
                    : titleComparison == .orderedAscending
            }
            return first.id.uuidString < second.id.uuidString
        }
    }

    static func reversedSortOrder(_ sortOrder: PodcastSortOrder) -> PodcastSortOrder {
        switch sortOrder {
        case .alphabetic:
            return .reverseAlphabetic
        case .reverseAlphabetic:
            return .alphabetic
        case .recentlyUpdated:
            return .leastRecentlyUpdated
        case .leastRecentlyUpdated:
            return .recentlyUpdated
        }
    }

    static func sortCriterion(for sortOrder: PodcastSortOrder) -> PodcastSidebarSortCriterion {
        switch sortOrder {
        case .alphabetic, .reverseAlphabetic:
            return .name
        case .recentlyUpdated, .leastRecentlyUpdated:
            return .recentlyUpdated
        }
    }

    static func defaultSortOrder(for criterion: PodcastSidebarSortCriterion) -> PodcastSortOrder {
        switch criterion {
        case .name:
            return .alphabetic
        case .recentlyUpdated:
            return .recentlyUpdated
        }
    }

    static func sortDirectionIcon(for sortOrder: PodcastSortOrder) -> String {
        switch sortOrder {
        case .alphabetic, .leastRecentlyUpdated:
            return "arrow.up"
        case .reverseAlphabetic, .recentlyUpdated:
            return "arrow.down"
        }
    }

    static func sortDirectionHelpText(for sortOrder: PodcastSortOrder) -> String {
        switch sortOrder {
        case .alphabetic:
            return "Sorted by name, A–Z. Click to reverse."
        case .reverseAlphabetic:
            return "Sorted by name, Z–A. Click to reverse."
        case .recentlyUpdated:
            return "Sorted by recently updated, newest first. Click to reverse."
        case .leastRecentlyUpdated:
            return "Sorted by recently updated, oldest first. Click to reverse."
        }
    }

    private func inactiveHelpText(for subscription: PodcastSubscription) -> String {
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
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("\(deviceName)  ·  \(podcastDirectoryPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
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

        return Toggle(
            isOn: Binding(
                get: { isSelected },
                set: { shouldSelect in
                    if shouldSelect != isSelected {
                        onToggleSelection(fileURL)
                    }
                }
            )
        ) {
            HStack {
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
        .toggleStyle(.checkbox)
        .tint(.red)
        .accessibilityLabel(relativePath(fileURL))
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
                urlRow(label: "RSS Feed URL", url: episode.sourceFeedURL)
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
