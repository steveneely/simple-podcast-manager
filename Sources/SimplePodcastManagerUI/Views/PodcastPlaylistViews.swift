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

    init(playlist: PodcastPlaylist? = nil) {
        playlistID = playlist?.id
        initialName = playlist?.name ?? ""
    }
}

struct PodcastPlaylistEditorView: View {
    let title: String
    let initialName: String
    let onSave: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var errorMessage: String?

    init(title: String, initialName: String, onSave: @escaping (String) throws -> Void) {
        self.title = title
        self.initialName = initialName
        self.onSave = onSave
        self._name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Playlist Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

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
        .frame(width: 380)
    }

    private func save() {
        do {
            try onSave(name)
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
                                PodcastPlaylistIconView()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.headline)
                                    Text("\(playlist.entries.count) episode\(playlist.entries.count == 1 ? "" : "s")")
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
                                HoverIconButton(systemName: "pencil", helpText: "Rename playlist") {
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
            Image(systemName: "music.note.list")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

struct PodcastPlaylistDetailView: View {
    let playlist: PodcastPlaylist?
    let isOnDevice: (Episode) -> Bool
    let isDownloaded: (Episode) -> Bool
    let onAddPlaylist: () -> Void
    let onMove: (IndexSet, Int) -> Void
    let onRemove: (PodcastPlaylistEntry) -> Void

    @StateObject private var dragCursorController = PodcastPlaylistDragCursorController()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let playlist {
                Text(playlist.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                if playlist.entries.isEmpty {
                    ContentUnavailableView(
                        "No Episodes Yet",
                        systemImage: "music.note.list",
                        description: Text("Add episodes from the Podcasts view.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(playlist.entries) { entry in
                            HStack(spacing: 10) {
                                PodcastPlaylistDragHandle(
                                    onHover: dragCursorController.setHovering
                                )

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
                                ) { onRemove(entry) }
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove(perform: onMove)
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
        .onAppear {
            dragCursorController.startMonitoring()
        }
        .onDisappear {
            dragCursorController.stopMonitoring()
        }
    }

    private func statusText(for episode: Episode) -> String {
        if isOnDevice(episode) { return "On MP3 player" }
        if isDownloaded(episode) { return "Ready to sync" }
        return "Unavailable"
    }
}

private struct PodcastPlaylistDragHandle: View {
    let onHover: (Bool) -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .help("Drag to reorder")
            .accessibilityLabel("Drag to reorder")
            .onHover(perform: onHover)
    }
}

@MainActor
private final class PodcastPlaylistDragCursorController: ObservableObject {
    private var eventMonitor: Any?
    private var isHovering = false
    private var isDragging = false

    func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event.type)
            return event
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isHovering = false
        isDragging = false
        NSCursor.arrow.set()
    }

    func setHovering(_ isHovering: Bool) {
        self.isHovering = isHovering
        updateCursor()
    }

    private func handle(_ eventType: NSEvent.EventType) {
        switch eventType {
        case .leftMouseDown where isHovering:
            isDragging = true
        case .leftMouseUp:
            isDragging = false
        default:
            return
        }
        updateCursor()
    }

    private func updateCursor() {
        if isDragging {
            NSCursor.closedHand.set()
        } else if isHovering {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
