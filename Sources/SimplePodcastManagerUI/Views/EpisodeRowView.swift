import SwiftUI
import SimplePodcastManagerCore

struct EpisodeRowView<Details: View>: View {
    let episode: Episode
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
    let onToggleDetails: () -> Void
    let onToggleDeviceRemoval: () -> Void
    let onRemoveDownload: () -> Void
    let onCancelDownload: () -> Void
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
