import AppKit
import Testing
@testable import SimplePodcastManagerUI
import SimplePodcastManagerCore

@Suite("Application appearance")
struct ApplicationAppearanceTests {
    @Test("System removes the application appearance override")
    func systemAppearanceHasNoOverride() {
        #expect(ApplicationAppearance.appearance(for: .system) == nil)
    }

    @Test("Explicit preferences use their matching application appearance")
    func explicitAppearances() {
        #expect(ApplicationAppearance.appearance(for: .light)?.name == .aqua)
        #expect(ApplicationAppearance.appearance(for: .dark)?.name == .darkAqua)
    }
}
