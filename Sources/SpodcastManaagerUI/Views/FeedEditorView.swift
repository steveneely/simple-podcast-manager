import SwiftUI

public struct FeedEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FeedDraft
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?
    private let title: String
    private let onSave: @Sendable (FeedDraft) async throws -> Void

    private enum Field: Hashable {
        case rssURL
    }

    public init(
        title: String,
        draft: FeedDraft,
        onSave: @escaping @Sendable (FeedDraft) async throws -> Void
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
                LabeledField(title: "RSS Feed URL") {
                    TextField("https://example.com/feed.xml", text: $draft.rssURLString)
                        .focused($focusedField, equals: .rssURL)
                        .inputFieldStyle(isFocused: focusedField == .rssURL)
                }

                if let currentTitle = draft.currentTitle, !currentTitle.isEmpty {
                    LabeledField(
                        title: "Podcast Title",
                        detail: "This comes from the RSS feed and updates when you refresh."
                    ) {
                        Text(currentTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
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

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(isSaving ? "Saving..." : "Save") {
                    Task {
                        isSaving = true
                        defer { isSaving = false }

                        do {
                            try await onSave(draft)
                            dismiss()
                        } catch {
                            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave || isSaving)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            focusedField = .rssURL
        }
    }
}
