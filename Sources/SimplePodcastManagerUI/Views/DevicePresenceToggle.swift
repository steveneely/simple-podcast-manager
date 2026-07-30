import SwiftUI

struct DevicePresenceState: Equatable {
    let isSelectedForRemoval: Bool

    var shouldRemainOnDevice: Bool {
        !isSelectedForRemoval
    }

    var label: String {
        isSelectedForRemoval ? "Remove on next sync" : "On MP3 player"
    }

    var systemImage: String {
        isSelectedForRemoval ? "minus.circle.fill" : "externaldrive.fill"
    }

    func shouldToggleSelection(whenChangedTo shouldRemainOnDevice: Bool) -> Bool {
        shouldRemainOnDevice != self.shouldRemainOnDevice
    }
}

struct DevicePresenceToggle: View {
    let isSelectedForRemoval: Bool
    let onToggleSelection: () -> Void

    private var state: DevicePresenceState {
        DevicePresenceState(isSelectedForRemoval: isSelectedForRemoval)
    }

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { state.shouldRemainOnDevice },
                set: { shouldRemainOnDevice in
                    if state.shouldToggleSelection(whenChangedTo: shouldRemainOnDevice) {
                        onToggleSelection()
                    }
                }
            )
        ) {
            Label(state.label, systemImage: state.systemImage)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .font(.caption)
        .foregroundStyle(isSelectedForRemoval ? Color.red : Color.secondary)
        .help(
            isSelectedForRemoval
                ? "Keep this episode on the MP3 player"
                : "Clear this checkbox to remove the episode on the next sync"
        )
    }
}
