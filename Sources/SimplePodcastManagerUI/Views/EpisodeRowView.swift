import SwiftUI
import SimplePodcastManagerCore

struct EpisodeRowView<Details: View>: View {
    let episode: Episode
    let isNoLongerInCurrentFeed: Bool
    let isNew: Bool
    let isExpanded: Bool
    let durationLabel: String?
    let downloadLabel: String?
    let downloadWarnings: [String]
    let downloadErrorMessage: String?
    let removedLabel: String?
    let isOnDevice: Bool
    let isSelectedForDeviceRemoval: Bool
    let isPrepared: Bool
    let isPreparing: Bool
    let playlists: [PodcastPlaylist]
    let automaticPlaylistIDs: Set<PodcastPlaylist.ID>
    let onToggleDetails: () -> Void
    let onToggleDeviceRemoval: () -> Void
    let onRemoveDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDownload: () -> Void
    let onTogglePlaylist: (PodcastPlaylist) -> Void
    @ViewBuilder let details: Details

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: onToggleDetails) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(episode.title)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    if isNew {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 7, height: 7)
                                            .help("New episode")
                                            .accessibilityLabel("New episode")
                                    }
                                    if let durationLabel {
                                        Text(durationLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                    }
                                }

                                if let publicationDate = episode.publicationDate {
                                    Text(publicationDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let downloadLabel {
                                    Text(downloadLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if isNoLongerInCurrentFeed {
                                    Text("No longer in current feed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(downloadWarnings, id: \.self) { warning in
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                if let downloadErrorMessage {
                                    Text(downloadErrorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                if let removedLabel {
                                    Text(removedLabel)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if isOnDevice {
                        DevicePresenceToggle(
                            isSelectedForRemoval: isSelectedForDeviceRemoval,
                            onToggleSelection: onToggleDeviceRemoval
                        )
                        .padding(.leading, 20)
                    }
                }

                Spacer()

                if !playlists.isEmpty {
                    let playlistIndicator = EpisodePlaylistIndicatorPresentation(
                        episode: episode,
                        playlists: playlists,
                        automaticPlaylistIDs: automaticPlaylistIDs
                    )
                    HoverIconMenu(
                        systemName: playlistIndicator.systemName,
                        helpText: playlistIndicator.helpText,
                        isActive: playlistIndicator.isIncluded
                    ) {
                        ForEach(playlists) { playlist in
                            Button {
                                onTogglePlaylist(playlist)
                            } label: {
                                switch playlistIndicator.membership(for: playlist.id) {
                                case .manual:
                                    Label(playlist.name, systemImage: "checkmark")
                                case .automatic:
                                    Label(
                                        "\(playlist.name) — Automatically added",
                                        systemImage: "gearshape"
                                    )
                                case .none:
                                    Text(playlist.name)
                                }
                            }
                        }
                    }
                }

                if isPrepared {
                    HoverIconButton(
                        systemName: "trash",
                        helpText: "Delete downloaded episode",
                        isDestructive: true,
                        action: onRemoveDownload
                    )
                } else if isPreparing {
                    Button(action: onCancelDownload) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Cancel")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel download")
                    .accessibilityLabel("Cancel download of \(episode.title)")
                } else {
                    HoverIconButton(
                        systemName: "arrow.down.circle",
                        helpText: "Download episode",
                        action: onDownload
                    )
                }
            }

            if isExpanded {
                details
                    .padding(.leading, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}

struct EpisodePlaylistIndicatorPresentation: Equatable {
    enum Membership: Equatable {
        case none
        case automatic
        case manual
    }

    let membershipsByPlaylistID: [PodcastPlaylist.ID: Membership]
    let includedPlaylistNames: [String]

    init(
        episode: Episode,
        playlists: [PodcastPlaylist],
        automaticPlaylistIDs: Set<PodcastPlaylist.ID>
    ) {
        var membershipsByPlaylistID: [PodcastPlaylist.ID: Membership] = [:]
        var includedPlaylistNames: [String] = []
        for playlist in playlists {
            let membership: Membership
            if playlist.contains(episode) {
                membership = .manual
            } else if automaticPlaylistIDs.contains(playlist.id) {
                membership = .automatic
            } else {
                membership = .none
            }
            membershipsByPlaylistID[playlist.id] = membership
            if membership != .none {
                includedPlaylistNames.append(playlist.name)
            }
        }
        self.membershipsByPlaylistID = membershipsByPlaylistID
        self.includedPlaylistNames = includedPlaylistNames
    }

    var isIncluded: Bool {
        !includedPlaylistNames.isEmpty
    }

    var systemName: String {
        isIncluded ? "text.badge.checkmark" : "text.badge.plus"
    }

    var helpText: String {
        switch includedPlaylistNames.count {
        case 0:
            "Add to playlist"
        case 1:
            "In playlist “\(includedPlaylistNames[0])” — click to manage"
        default:
            "In \(includedPlaylistNames.count) playlists — click to manage"
        }
    }

    func membership(for playlistID: PodcastPlaylist.ID) -> Membership {
        membershipsByPlaylistID[playlistID] ?? .none
    }
}
