import SwiftUI

public struct FeedEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FeedDraft
    private let title: String
    private let onSave: (FeedDraft) -> Void

    public init(
        title: String,
        draft: FeedDraft,
        onSave: @escaping (FeedDraft) -> Void
    ) {
        self.title = title
        self._draft = State(initialValue: draft)
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Podcast title", text: $draft.title)
                TextField("RSS feed URL", text: $draft.rssURLString)
                TextField("Folder name override (optional)", text: $draft.podcastFolderName)
                Stepper("Keep latest \(draft.retentionEpisodeLimit) episode\(draft.retentionEpisodeLimit == 1 ? "" : "s")", value: $draft.retentionEpisodeLimit, in: 1...100)
                Toggle("Feed enabled", isOn: $draft.isEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
