import SwiftUI

struct PodcastPlaylistSyncPreflightView: View {
    let preflight: PodcastPlaylistSyncPreflight
    let onContinue: (PodcastPlaylistSyncChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: PodcastPlaylistSyncChoice = .download
    @State private var episodeListHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(preflight.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(preflight.message)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(preflight.unavailableEpisodes.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").accessibilityHidden(true)
                            Text(preflight.unavailableEpisodes[index].title)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    episodeListHeight = min(height, 150)
                }
            }
            .frame(height: episodeListHeight)

            Picker("Choose how to continue:", selection: $choice) {
                ForEach(PodcastPlaylistSyncChoice.allCases, id: \.self) { option in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preflight.choiceTitle(option))
                        Text(preflight.choiceDetail(option))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .tag(option)
                }
            }
            .pickerStyle(.radioGroup)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(choice.continueButtonTitle) { onContinue(choice) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580)
    }
}
