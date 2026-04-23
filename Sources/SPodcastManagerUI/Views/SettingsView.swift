import SwiftUI
import SPodcastManagerCore

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ffmpegExecutablePath: String
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

            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    onSave(
                        AppSettings(
                            ffmpegExecutablePath: ffmpegExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ffmpegExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
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
