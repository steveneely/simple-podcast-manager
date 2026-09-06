import SwiftUI

struct PodcastSortControl: View {
    let criterionTitle: String
    let criterionHelpText: String
    let directionSystemName: String
    let directionHelpText: String
    let onChangeCriterion: () -> Void
    let onReverseDirection: () -> Void

    var body: some View {
        ControlGroup {
            Button(action: onChangeCriterion) {
                Text(criterionTitle)
            }
            .help(criterionHelpText)
            .accessibilityLabel(criterionHelpText)

            Button(action: onReverseDirection) {
                Image(systemName: directionSystemName)
            }
            .help(directionHelpText)
            .accessibilityLabel(directionHelpText)
        }
        .controlSize(.small)
    }
}
