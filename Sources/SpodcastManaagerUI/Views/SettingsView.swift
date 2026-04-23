import SwiftUI
import SpodcastManaagerCore

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ffmpegExecutablePath: String
    @State private var dryRunByDefault: Bool
    @State private var ejectAfterSyncByDefault: Bool
    @FocusState private var focusedField: Field?
    private let onSave: (AppSettings) -> Void

    private enum Field: Hashable {
        case ffmpeg
    }

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

            VStack(alignment: .leading, spacing: 14) {
                LabeledField(
                    title: "ffmpeg Path",
                    detail: "Required for converting non-MP3 audio."
                ) {
                    TextField("/opt/homebrew/bin/ffmpeg", text: $ffmpegExecutablePath)
                        .focused($focusedField, equals: .ffmpeg)
                        .inputFieldStyle(isFocused: focusedField == .ffmpeg)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Dry-run by default", isOn: $dryRunByDefault)
                    Toggle("Eject after sync by default", isOn: $ejectAfterSyncByDefault)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

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
        .frame(minWidth: 480)
        .onAppear {
            focusedField = .ffmpeg
        }
    }
}
