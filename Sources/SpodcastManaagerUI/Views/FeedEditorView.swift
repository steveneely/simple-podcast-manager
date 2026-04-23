import SwiftUI

public struct FeedEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FeedDraft
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?
    private let title: String
    private let initialDraft: FeedDraft
    private let onSave: @Sendable (FeedDraft) async throws -> Void
    private let retentionOptions: [Int] = [1, 2, 3, 5, 10, 20, .max]

    private enum Field: Hashable {
        case rssURL
    }

    public init(
        title: String,
        draft: FeedDraft,
        onSave: @escaping @Sendable (FeedDraft) async throws -> Void
    ) {
        self.title = title
        self.initialDraft = draft
        self._draft = State(initialValue: draft)
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dialogTitle)
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                LabeledField(title: "Feed URL") {
                    TextField("https://example.com/feed.xml", text: $draft.rssURLString)
                        .focused($focusedField, equals: .rssURL)
                        .inputFieldStyle(isFocused: focusedField == .rssURL)
                }

                LabeledField(title: "Keep Episodes") {
                    Picker("Keep", selection: $draft.retentionEpisodeLimit) {
                        ForEach(retentionOptions, id: \.self) { option in
                            Text(retentionLabel(for: option))
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

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
            draft = initialDraft
            focusedField = isCreatingFeed ? .rssURL : nil
        }
    }

    private var isCreatingFeed: Bool {
        draft.id == nil
    }

    private var dialogTitle: String {
        if let currentTitle = draft.currentTitle, !currentTitle.isEmpty {
            return currentTitle
        }
        return title
    }

    private func retentionLabel(for value: Int) -> String {
        value == .max ? "∞" : "\(value)"
    }
}
