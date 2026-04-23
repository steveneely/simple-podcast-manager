import SwiftUI
import PodcastSwiftCore

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ffmpegExecutablePath: String
    @State private var podcastIndexAPIKey: String
    @State private var podcastIndexAPISecret: String
    @State private var dryRunByDefault: Bool
    @State private var ejectAfterSyncByDefault: Bool
    private let onSave: (AppSettings) -> Void

    public init(
        settings: AppSettings,
        onSave: @escaping (AppSettings) -> Void
    ) {
        self._ffmpegExecutablePath = State(initialValue: settings.ffmpegExecutablePath ?? "")
        self._podcastIndexAPIKey = State(initialValue: settings.podcastIndexAPIKey ?? "")
        self._podcastIndexAPISecret = State(initialValue: settings.podcastIndexAPISecret ?? "")
        self._dryRunByDefault = State(initialValue: settings.dryRunByDefault)
        self._ejectAfterSyncByDefault = State(initialValue: settings.ejectAfterSyncByDefault)
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("ffmpeg path (optional)", text: $ffmpegExecutablePath)
                TextField("Podcast Index API key (optional)", text: $podcastIndexAPIKey)
                SecureField("Podcast Index API secret (optional)", text: $podcastIndexAPISecret)
                Toggle("Dry-run by default", isOn: $dryRunByDefault)
                Toggle("Eject after sync by default", isOn: $ejectAfterSyncByDefault)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    onSave(
                        AppSettings(
                            ffmpegExecutablePath: ffmpegExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ffmpegExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines),
                            podcastIndexAPIKey: podcastIndexAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : podcastIndexAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            podcastIndexAPISecret: podcastIndexAPISecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : podcastIndexAPISecret.trimmingCharacters(in: .whitespacesAndNewlines),
                            dryRunByDefault: dryRunByDefault,
                            ejectAfterSyncByDefault: ejectAfterSyncByDefault
                        )
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
