import AppKit
import SwiftUI
import SimplePodcastManagerCore

struct PodcastEpisodeDownloadView: View {
    private static let checkboxInset: CGFloat = 10

    let podcastTitle: String
    let downloadedIDs: Set<Episode.ID>
    let queuedIDs: Set<Episode.ID>
    let onDownload: ([Episode]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: PodcastEpisodeDownloadSelection

    init(
        presentation: PodcastEpisodeDownloadPresentation,
        downloadedIDs: Set<Episode.ID>,
        queuedIDs: Set<Episode.ID>,
        onDownload: @escaping ([Episode]) -> Void
    ) {
        podcastTitle = presentation.podcastTitle
        self.downloadedIDs = downloadedIDs
        self.queuedIDs = queuedIDs
        self.onDownload = onDownload
        _selection = State(initialValue: PodcastEpisodeDownloadSelection(episodes: presentation.episodes))
    }

    private var unavailableIDs: Set<Episode.ID> { downloadedIDs.union(queuedIDs) }
    private var selectedEpisodes: [Episode] { selection.selectedEpisodes(unavailableIDs: unavailableIDs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Download Multiple Episodes")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(podcastTitle)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Toggle("Select All", isOn: Binding(
                    get: { selection.areAllSelected(unavailableIDs: unavailableIDs) },
                    set: { selection.setAllSelected($0, unavailableIDs: unavailableIDs) }
                ))
                    .toggleStyle(.checkbox)
                    .disabled(selection.episodes.allSatisfy { unavailableIDs.contains($0.id) })
                Spacer()
                Text("Shift-click for ranges.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Self.checkboxInset)

            List(selection.episodes) { episode in
                Toggle(isOn: Binding(
                    get: { selection.selectedIDs.contains(episode.id) && !unavailableIDs.contains(episode.id) },
                    set: { isSelected in
                        selection.setSelected(
                            isSelected,
                            episodeID: episode.id,
                            extendingRange: NSEvent.modifierFlags.contains(.shift),
                            unavailableIDs: unavailableIDs
                        )
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(episode.title)
                        if let date = episode.publicationDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if downloadedIDs.contains(episode.id) {
                            Text("Downloaded").font(.caption).foregroundStyle(.secondary)
                        } else if queuedIDs.contains(episode.id) {
                            Text("Queued for download").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .toggleStyle(.checkbox)
                .disabled(unavailableIDs.contains(episode.id))
                .listRowInsets(EdgeInsets(
                    top: 4, leading: Self.checkboxInset,
                    bottom: 4, trailing: Self.checkboxInset
                ))
            }
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)

            Divider()
            HStack {
                Text("\(selectedEpisodes.count) episode\(selectedEpisodes.count == 1 ? "" : "s") selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download \(selectedEpisodes.count) Episode\(selectedEpisodes.count == 1 ? "" : "s")") {
                    onDownload(selectedEpisodes)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedEpisodes.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 540)
    }
}
