import AppKit
import SwiftUI

/// Explicit native segment widths keep the criterion and direction divider stationary.
struct PodcastSortControl: NSViewRepresentable {
    let criterionTitle: String
    let criterionHelpText: String
    let directionSystemName: String
    let directionHelpText: String
    let onChangeCriterion: () -> Void
    let onReverseDirection: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(control: self)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: [criterionTitle, ""],
            trackingMode: .momentary,
            target: context.coordinator,
            action: #selector(Coordinator.activateSegment(_:))
        )
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        control.setWidth(62, forSegment: 0)
        control.setWidth(24, forSegment: 1)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.control = self
        control.setLabel(criterionTitle, forSegment: 0)
        control.setToolTip(criterionHelpText, forSegment: 0)
        control.setImage(
            NSImage(systemSymbolName: directionSystemName, accessibilityDescription: directionHelpText),
            forSegment: 1
        )
        control.setToolTip(directionHelpText, forSegment: 1)
        control.isEnabled = context.environment.isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    @MainActor
    final class Coordinator: NSObject {
        var control: PodcastSortControl

        init(control: PodcastSortControl) {
            self.control = control
        }

        @objc func activateSegment(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0: control.onChangeCriterion()
            case 1: control.onReverseDirection()
            default: break
            }
        }
    }
}
