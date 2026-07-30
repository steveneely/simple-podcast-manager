import Testing
@testable import SimplePodcastManagerUI

struct DevicePresenceStateTests {
    @Test
    func checkedStateKeepsEpisodeOnDevice() {
        let state = DevicePresenceState(isSelectedForRemoval: false)

        #expect(state.shouldRemainOnDevice)
        #expect(state.label == "On MP3 player")
        #expect(!state.shouldToggleSelection(whenChangedTo: true))
        #expect(state.shouldToggleSelection(whenChangedTo: false))
    }

    @Test
    func uncheckedStateSchedulesRemoval() {
        let state = DevicePresenceState(isSelectedForRemoval: true)

        #expect(!state.shouldRemainOnDevice)
        #expect(state.label == "Remove on next sync")
        #expect(!state.shouldToggleSelection(whenChangedTo: false))
        #expect(state.shouldToggleSelection(whenChangedTo: true))
    }
}
