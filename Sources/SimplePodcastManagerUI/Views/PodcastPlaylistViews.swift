import AppKit
import SwiftUI
import SimplePodcastManagerCore

enum PodcastLibraryMode: String, CaseIterable {
    case podcasts = "Podcasts"
    case playlists = "Playlists"
}

struct PodcastLibraryModePicker: View {
    @Binding var selection: PodcastLibraryMode

    var body: some View {
        Picker("Library", selection: $selection) {
            ForEach(PodcastLibraryMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.headline)
        .fixedSize()
        .help("Switch between Podcasts and Playlists")
        .accessibilityLabel("Library")
    }
}

struct PodcastPlaylistEditorPresentation: Identifiable {
    let id = UUID()
    let playlistID: PodcastPlaylist.ID?
    let initialName: String
    let initialIcon: PodcastPlaylistIcon
    let automaticRule: PodcastPlaylistAutomaticRule?

    init(playlist: PodcastPlaylist? = nil) {
        playlistID = playlist?.id
        initialName = playlist?.name ?? ""
        initialIcon = playlist?.icon ?? .music
        automaticRule = playlist?.automaticRule
    }
}

struct PodcastPlaylistEditorView: View {
    let title: String
    let initialName: String
    let initialIcon: PodcastPlaylistIcon
    let playlistID: PodcastPlaylist.ID?
    let initialAutomaticRule: PodcastPlaylistAutomaticRule?
    let podcasts: [PodcastSubscription]
    let onSave: (String, PodcastPlaylistIcon, PodcastPlaylistAutomaticRule?) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: PodcastPlaylistIcon
    @State private var automaticallyAddsEpisodes: Bool
    @State private var selectedPodcastIDs: Set<PodcastSubscription.ID>
    @State private var limitsEpisodeCount: Bool
    @State private var maximumEpisodeCount: Int
    @State private var errorMessage: String?

    init(
        title: String,
        initialName: String,
        initialIcon: PodcastPlaylistIcon,
        playlistID: PodcastPlaylist.ID?,
        initialAutomaticRule: PodcastPlaylistAutomaticRule?,
        podcasts: [PodcastSubscription],
        onSave: @escaping (String, PodcastPlaylistIcon, PodcastPlaylistAutomaticRule?) throws -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.initialIcon = initialIcon
        self.playlistID = playlistID
        self.initialAutomaticRule = initialAutomaticRule
        self.podcasts = podcasts
        self.onSave = onSave
        self._name = State(initialValue: initialName)
        self._icon = State(initialValue: initialIcon)
        self._automaticallyAddsEpisodes = State(initialValue: initialAutomaticRule != nil)
        switch initialAutomaticRule?.source {
        case .selectedPodcasts(let includedPodcastIDs):
            self._selectedPodcastIDs = State(initialValue: includedPodcastIDs)
        case .allPodcasts:
            self._selectedPodcastIDs = State(initialValue: Set(podcasts.map(\.id)))
        case .recentlyDownloaded, nil:
            self._selectedPodcastIDs = State(initialValue: [])
        }
        self._limitsEpisodeCount = State(initialValue: initialAutomaticRule?.maximumEpisodeCount != nil)
        self._maximumEpisodeCount = State(initialValue: initialAutomaticRule?.maximumEpisodeCount ?? 25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Playlist Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            Picker("Icon", selection: $icon) {
                ForEach(PodcastPlaylistIcon.allCases, id: \.self) { icon in
                    Text(icon.glyph)
                        .tag(icon)
                        .help(icon.title)
                        .accessibilityLabel(icon.title)
                }
            }
            .pickerStyle(.palette)

            automaticRuleEditor

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var automaticRuleEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Automatically add episodes", isOn: $automaticallyAddsEpisodes)

            Text(automaticAdditionsDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if automaticallyAddsEpisodes {
                if podcasts.isEmpty {
                    Text("Add a Podcast before selecting Podcasts for automatic additions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Podcasts")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(podcasts) { podcast in
                                Toggle(
                                    podcast.title,
                                    isOn: Binding(
                                        get: { selectedPodcastIDs.contains(podcast.id) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedPodcastIDs.insert(podcast.id)
                                            } else {
                                                selectedPodcastIDs.remove(podcast.id)
                                            }
                                        }
                                    )
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Toggle("Limit automatically added episodes", isOn: $limitsEpisodeCount)
                if limitsEpisodeCount {
                    Stepper(
                        "Latest \(maximumEpisodeCount) episode\(maximumEpisodeCount == 1 ? "" : "s")",
                        value: $maximumEpisodeCount,
                        in: 1...500
                    )
                    .padding(.leading, 20)
                }
            }
        }
    }

    private var automaticAdditionsDescription: String {
        "Downloaded episodes from the selected Podcasts are added automatically. You can still add and reorder other episodes yourself."
    }

    private func save() {
        do {
            let automaticRule: PodcastPlaylistAutomaticRule?
            if automaticallyAddsEpisodes {
                automaticRule = PodcastPlaylistAutomaticRule(
                    source: .selectedPodcasts(selectedPodcastIDs),
                    maximumEpisodeCount: limitsEpisodeCount ? maximumEpisodeCount : nil
                )
            } else {
                automaticRule = nil
            }
            try onSave(name, icon, automaticRule)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct PodcastPlaylistSidebarView: View {
    let playlists: [PodcastPlaylist]
    @Binding var libraryMode: PodcastLibraryMode
    @Binding var selectedPlaylistID: PodcastPlaylist.ID?
    let onAdd: () -> Void
    let onEdit: (PodcastPlaylist) -> Void
    let onDelete: (PodcastPlaylist) -> Void
    let episodeCounts: [PodcastPlaylist.ID: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PodcastLibraryModePicker(selection: $libraryMode)
                Spacer()
                HoverIconButton(systemName: "plus", helpText: "Add playlist", action: onAdd)
            }

            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists Yet",
                    systemImage: "music.note.list",
                    description: Text("Create a playlist, then add downloaded episodes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(playlists) { playlist in
                    let isSelected = selectedPlaylistID == playlist.id
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            selectedPlaylistID = playlist.id
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                PodcastPlaylistIconView(
                                    icon: playlist.icon,
                                    automaticallyAddsEpisodes: playlist.automaticallyAddsEpisodes
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.headline)
                                    let count = episodeCounts[playlist.id] ?? playlist.entries.count
                                    Text("\(count) episode\(count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isSelected {
                            HStack(spacing: 4) {
                                HoverIconButton(systemName: "pencil", helpText: "Edit playlist") {
                                    onEdit(playlist)
                                }
                                HoverIconButton(
                                    systemName: "trash",
                                    helpText: "Delete playlist",
                                    isDestructive: true
                                ) {
                                    onDelete(playlist)
                                }
                            }
                            .padding(.leading, 52)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                }
            }
        }
        .padding(14)
    }
}

private struct PodcastPlaylistIconView: View {
    let icon: PodcastPlaylistIcon
    let automaticallyAddsEpisodes: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.35),
                    Color.accentColor.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if icon == .music {
                Image(systemName: "music.note.list")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            } else {
                Text(icon.glyph)
                    .font(.system(size: 22))
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if automaticallyAddsEpisodes {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Color.accentColor))
                    .offset(x: 3, y: 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }
}

private extension PodcastPlaylistIcon {
    var title: String {
        switch self {
        case .music: "Music"
        case .favorite: "Favorite"
        case .news: "News"
        case .history: "History"
        case .technology: "Technology"
        case .cycling: "Cycling"
        case .exercise: "Exercise"
        case .commuting: "Commuting"
        case .home: "Home"
        case .outdoors: "Outdoors"
        case .sleep: "Sleep"
        }
    }

    var glyph: String {
        switch self {
        case .music: "♫"
        case .favorite: "⭐️"
        case .news: "📰"
        case .history: "🏛️"
        case .technology: "💻"
        case .cycling: "🚲"
        case .exercise: "🏃"
        case .commuting: "🚆"
        case .home: "🏠"
        case .outdoors: "🌿"
        case .sleep: "🌙"
        }
    }
}

struct PodcastPlaylistDetailView: View {
    let playlist: PodcastPlaylist?
    let entries: ResolvedPodcastPlaylistEntries
    let isOnDevice: (Episode) -> Bool
    let isDownloaded: (Episode) -> Bool
    let onAddPlaylist: () -> Void
    let onMove: (IndexSet, Int) -> Void
    let onRemoveExplicit: (PodcastPlaylistEntry) -> Void
    let onPinAutomatic: (PodcastPlaylistEntry) -> Void
    let onExcludeAutomatic: (PodcastPlaylistEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let playlist {
                HStack(spacing: 10) {
                    Text(playlist.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if playlist.automaticallyAddsEpisodes {
                        Label("Automatic", systemImage: "gearshape.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let automaticRule = playlist.automaticRule {
                    Text(automaticRuleDescription(automaticRule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if entries.all.isEmpty {
                    ContentUnavailableView(
                        "No Episodes Yet",
                        systemImage: "music.note.list",
                        description: Text(playlist.automaticallyAddsEpisodes
                            ? "Add an episode, or download one matching this playlist’s automatic settings."
                            : "Add episodes from the Podcasts view.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !entries.explicit.isEmpty {
                            Section(entries.automatic.isEmpty ? "Episodes" : "Manually Added") {
                                ForEach(entries.explicit) { entry in
                                    explicitEpisodeRow(entry)
                                }
                                .onMove(perform: onMove)
                            }
                        }
                        if !entries.automatic.isEmpty {
                            Section("Added Automatically") {
                                ForEach(entries.automatic) { entry in
                                    automaticEpisodeRow(entry)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "Choose a Playlist",
                        systemImage: "music.note.list",
                        description: Text("Select a playlist to browse its episodes, or create another playlist.")
                    )

                    Button("New Playlist", systemImage: "plus", action: onAddPlaylist)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
    }

    private func statusText(for episode: Episode) -> String {
        if isOnDevice(episode) { return "On MP3 player" }
        if isDownloaded(episode) { return "Ready to sync" }
        return "Unavailable"
    }

    private func automaticRuleDescription(_ rule: PodcastPlaylistAutomaticRule) -> String {
        if rule.source == .recentlyDownloaded {
            if let maximumEpisodeCount = rule.maximumEpisodeCount {
                let episodeLabel = maximumEpisodeCount == 1 ? "episode" : "episodes"
                return "Automatically includes the latest \(maximumEpisodeCount) recently downloaded \(episodeLabel)."
            }
            return "Automatically includes downloaded episodes until you remove them."
        }
        let sourceDescription: String
        switch rule.source {
        case .allPodcasts:
            sourceDescription = "all Podcasts"
        case .selectedPodcasts(let includedPodcastIDs):
            sourceDescription = "\(includedPodcastIDs.count) selected Podcast\(includedPodcastIDs.count == 1 ? "" : "s")"
        case .recentlyDownloaded:
            sourceDescription = "recent downloads"
        }
        if let maximumEpisodeCount = rule.maximumEpisodeCount {
            return "Automatically includes the latest \(maximumEpisodeCount) available episodes from \(sourceDescription)."
        }
        return "Automatically includes all available episodes from \(sourceDescription)."
    }

    private func explicitEpisodeRow(_ entry: PodcastPlaylistEntry) -> some View {
        HStack(spacing: 10) {
            PodcastPlaylistDragHandle()

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.episode.title)
                    .fontWeight(.medium)
                Text(entry.episode.podcastTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusText(for: entry.episode))
                    .font(.caption)
                    .foregroundStyle(isOnDevice(entry.episode) ? .green : .secondary)
            }
            Spacer()
            HoverIconButton(
                systemName: "minus.circle",
                helpText: "Remove from playlist",
                isDestructive: true
            ) { onRemoveExplicit(entry) }
        }
        .padding(.vertical, 4)
    }

    private func automaticEpisodeRow(_ entry: PodcastPlaylistEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.episode.title)
                    .fontWeight(.medium)
                Text(entry.episode.podcastTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusText(for: entry.episode))
                    .font(.caption)
                    .foregroundStyle(isOnDevice(entry.episode) ? .green : .secondary)
            }
            Spacer()
            let canPin = isDownloaded(entry.episode) || isOnDevice(entry.episode)
            HoverIconButton(
                systemName: "pin",
                helpText: canPin
                    ? "Pin as manually added"
                    : "Download this episode before pinning",
                isDisabled: !canPin
            ) { onPinAutomatic(entry) }
            HoverIconButton(
                systemName: "minus.circle",
                helpText: "Keep this episode out of the playlist"
            ) { onExcludeAutomatic(entry) }
        }
        .padding(.vertical, 4)
    }
}

private struct PodcastPlaylistDragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .help("Drag to reorder")
            .accessibilityLabel("Drag to reorder")
    }
}
