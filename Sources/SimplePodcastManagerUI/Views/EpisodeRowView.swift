import SwiftUI
import SimplePodcastManagerCore

struct EpisodeRowView<Details: View>: View {
    let episode: Episode
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
    let onToggleDetails: () -> Void
    let onToggleDeviceRemoval: () -> Void
    let onRemoveDownload: () -> Void
    let onDownload: () -> Void
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

                if isPrepared {
                    HoverIconButton(
                        systemName: "trash",
                        helpText: "Delete downloaded podcast",
                        isDestructive: true,
                        action: onRemoveDownload
                    )
                } else if isPreparing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Downloading")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .help("Downloading episode")
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
