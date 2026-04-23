import SwiftUI
import PodcastSwiftCore

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ffmpegExecutablePath: String
    @State private var dryRunByDefault: Bool
    @State private var ejectAfterSyncByDefault: Bool
    private let onSave: (AppSettings) -> Void

    public init(
        settings: AppSettings,
        onSave: @escaping (AppSettings) -> Void
    ) {
        self._ffmpegExecutablePath = State(initialValue: settings.ffmpegExecutablePath ?? "")
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
