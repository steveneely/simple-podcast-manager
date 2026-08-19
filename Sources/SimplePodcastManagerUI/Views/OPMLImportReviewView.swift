import SwiftUI
import SimplePodcastManagerCore

public struct OPMLImportReviewView: View {
    private let preview: OPMLSubscriptionImportPreview
    private let onCancel: () -> Void
    private let onImport: () throws -> Void
    @State private var errorMessage: String?

    public init(
        preview: OPMLSubscriptionImportPreview,
        onCancel: @escaping () -> Void,
        onImport: @escaping () throws -> Void
    ) {
        self.preview = preview
        self.onCancel = onCancel
        self.onImport = onImport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Podcast Subscriptions")
                .font(.title2)
                .fontWeight(.semibold)

            Text(summaryText)
                .foregroundStyle(.secondary)

            if hasSkippedEntries {
                VStack(alignment: .leading, spacing: 4) {
                    if preview.alreadySubscribedCount > 0 {
                        Text("\(preview.alreadySubscribedCount) already subscribed")
                    }
                    if preview.duplicateEntryCount > 0 {
                        Text("\(preview.duplicateEntryCount) duplicate in this file")
                    }
                    if preview.invalidEntryCount > 0 {
                        Text("\(preview.invalidEntryCount) invalid feed URL")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            List(preview.subscriptionsToAdd) { subscription in
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.title)
                    Text(subscription.rssURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(height: min(max(CGFloat(preview.subscriptionsToAdd.count) * 50, 110), 280))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }

                Button("Add \(preview.subscriptionsToAdd.count) Podcast\(preview.subscriptionsToAdd.count == 1 ? "" : "s")") {
                    do {
                        try onImport()
                    } catch {
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.subscriptionsToAdd.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var summaryText: String {
        if preview.subscriptionsToAdd.isEmpty {
            return "No new podcast subscriptions can be added from this file."
        }
        return "Review the podcast subscriptions to add. Their titles and artwork will update when feeds refresh."
    }

    private var hasSkippedEntries: Bool {
        preview.alreadySubscribedCount > 0
            || preview.duplicateEntryCount > 0
            || preview.invalidEntryCount > 0
    }
}
