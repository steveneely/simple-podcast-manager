import SwiftUI

public struct FeedEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FeedDraft
    @FocusState private var focusedField: Field?
    private let title: String
    private let onSave: (FeedDraft) -> Void

    private enum Field: Hashable {
        case title
        case rssURL
        case folderName
    }

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

            VStack(alignment: .leading, spacing: 14) {
                LabeledField(title: "Podcast Title") {
                    TextField("Example Podcast", text: $draft.title)
                        .focused($focusedField, equals: .title)
                        .inputFieldStyle(isFocused: focusedField == .title)
                }

                LabeledField(title: "RSS Feed URL") {
                    TextField("https://example.com/feed.xml", text: $draft.rssURLString)
                        .focused($focusedField, equals: .rssURL)
                        .inputFieldStyle(isFocused: focusedField == .rssURL)
                }

                LabeledField(
                    title: "Folder Name Override",
                    detail: "Optional. Leave blank to use the podcast title on the device."
                ) {
                    TextField("Example Podcast", text: $draft.podcastFolderName)
                        .focused($focusedField, equals: .folderName)
                        .inputFieldStyle(isFocused: focusedField == .folderName)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Episode Retention")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Stepper(
                        "Keep latest \(draft.retentionEpisodeLimit) episode\(draft.retentionEpisodeLimit == 1 ? "" : "s")",
                        value: $draft.retentionEpisodeLimit,
                        in: 1...100
                    )
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Toggle("Feed enabled", isOn: $draft.isEnabled)
            }

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
        .frame(minWidth: 460)
        .onAppear {
            focusedField = .title
        }
    }
}
