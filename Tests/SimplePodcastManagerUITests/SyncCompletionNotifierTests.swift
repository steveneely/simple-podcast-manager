import Foundation
import Testing
import UserNotifications
import SimplePodcastManagerCore
@testable import SimplePodcastManagerUI

@MainActor
struct SyncCompletionNotifierTests {
    @Test
    func completionNotificationIncludesSoundAndRequestsImmediateDelivery() {
        let request = SyncCompletionNotifier.makeNotificationRequest(result: SyncResult(copiedCount: 1))
        #expect(request.content.title == "Sync complete")
        #expect(request.content.body == "\n• 1 episode copied")
        #expect(request.content.sound == UNNotificationSound.default)
        #expect(request.trigger == nil)
        #expect(request.identifier != SyncCompletionNotifier.makeNotificationRequest(result: SyncResult(copiedCount: 1)).identifier)
    }

    @Test
    func summaryIncludesOnlyCompletedCountsAndSuccessfulEject() {
        var result = SyncResult(
            copiedCount: 3, deletedCount: 2, skippedCount: 8,
            completedActions: (1...8).map { .skip(reason: "Already on device: Episode \($0)") }
        )
        #expect(SyncCompletionNotifier.summary(for: result)
            == "• 3 episodes copied\n• 2 episodes deleted\n• 8 already on device")
        result.ejected = true
        #expect(SyncCompletionNotifier.summary(for: result)
            == "• 3 episodes copied\n• 2 episodes deleted\n• 8 already on device\n• Device ejected.")
    }

    @Test
    func summaryIncludesPlaylistChangesAlongsideEpisodesAndEject() {
        let result = SyncResult(
            copiedCount: 3, updatedPlaylistCount: 2, deletedPlaylistCount: 1, ejected: true
        )
        #expect(SyncCompletionNotifier.makeNotificationRequest(result: result).content.body
            == "\n• 3 episodes copied\n• 2 playlists updated\n• 1 playlist deleted\n• Device ejected.")
    }

    @Test
    func playlistOnlySummariesOmitZeroCountsAndUseCorrectPluralForms() {
        #expect(SyncCompletionNotifier.summary(for: SyncResult(updatedPlaylistCount: 1))
            == "• 1 playlist updated")
        #expect(SyncCompletionNotifier.summary(for: SyncResult(deletedPlaylistCount: 2))
            == "• 2 playlists deleted")
    }

    @Test
    func zeroCountsAreOmittedAndRemovedEpisodesAreNotReportedAsStillOnDevice() {
        let result = SyncResult(
            deletedCount: 1, skippedCount: 2,
            completedActions: [
                .skip(reason: "Selected for removal from device: Old episode"),
                .skip(reason: "Already on device: Retained episode")
            ]
        )
        #expect(SyncCompletionNotifier.summary(for: result) == "• 1 episode deleted\n• 1 already on device")
        #expect(SyncCompletionNotifier.summary(for: SyncResult()).isEmpty)
        #expect(SyncCompletionNotifier.makeNotificationRequest(result: SyncResult()).content.body.isEmpty)
        #expect(SyncCompletionNotifier.summary(for: SyncResult(ejected: true)) == "• Device ejected.")
    }

    @Test
    func backgroundNotificationReceivesActualSyncResult() async {
        let result = SyncResult(copiedCount: 3, deletedCount: 1, ejected: true)
        var deliveredResult: SyncResult?
        let notifier = SyncCompletionNotifier(
            isAppActive: { false },
            requestAuthorization: { true },
            currentAuthorization: { true },
            postNotification: { deliveredResult = $0 }
        )
        await notifier.prepareForSync()
        await notifier.syncSucceeded(result: result)
        #expect(deliveredResult == result)
    }

    @Test
    func backgroundCompletionNotifiesEvenWhenAppKitActivationFlagLags() async {
        var delivered = 0
        let notifier = SyncCompletionNotifier(
            isAppActive: {
                SyncCompletionNotifier.isAppFrontmost(
                    frontmostProcessID: 200,
                    currentProcessID: 100,
                    appKitIsActive: true
                )
            },
            requestAuthorization: { true },
            currentAuthorization: { true },
            postNotification: { _ in delivered += 1 }
        )
        await notifier.prepareForSync()
        await notifier.syncSucceeded(result: SyncResult())
        #expect(delivered == 1)
    }

    @Test
    func foregroundProcessTakesPrecedenceAndMissingProcessUsesAppKit() {
        #expect(SyncCompletionNotifier.isAppFrontmost(
            frontmostProcessID: 100, currentProcessID: 100, appKitIsActive: false
        ))
        #expect(SyncCompletionNotifier.isAppFrontmost(
            frontmostProcessID: nil, currentProcessID: 100, appKitIsActive: true
        ))
        #expect(!SyncCompletionNotifier.isAppFrontmost(
            frontmostProcessID: nil, currentProcessID: 100, appKitIsActive: false
        ))
    }

    @Test
    func usesFocusAtCompletionInsteadOfFocusAtStart() async {
        var active = true
        var delivered = 0
        let notifier = SyncCompletionNotifier(
            isAppActive: { active },
            requestAuthorization: { true },
            currentAuthorization: { true },
            postNotification: { _ in delivered += 1 }
        )
        await notifier.prepareForSync()
        active = false
        await notifier.syncSucceeded(result: SyncResult())
        #expect(delivered == 1)

        await notifier.prepareForSync()
        active = true
        await notifier.syncSucceeded(result: SyncResult())
        #expect(delivered == 1)
    }

    @Test
    func deniedOrFailedAuthorizationDoesNotNotifyAndCanBeRetried() async {
        var attempts = 0
        var delivered = 0
        let notifier = SyncCompletionNotifier(
            isAppActive: { false },
            requestAuthorization: {
                attempts += 1
                if attempts == 1 { throw CocoaError(.featureUnsupported) }
                return attempts == 3
            },
            currentAuthorization: { attempts == 3 },
            postNotification: { _ in delivered += 1 }
        )
        for _ in 0..<2 {
            await notifier.prepareForSync()
            await notifier.syncSucceeded(result: SyncResult())
        }
        #expect(delivered == 0)
        await notifier.prepareForSync()
        await notifier.syncSucceeded(result: SyncResult())
        #expect(delivered == 1)
    }

    @Test(arguments: [true, false])
    func permissionChangesDuringSyncUseCurrentSettings(initiallyAuthorized: Bool) async {
        var authorized = initiallyAuthorized
        var delivered = 0
        let notifier = SyncCompletionNotifier(
            isAppActive: { false },
            requestAuthorization: { authorized },
            currentAuthorization: { authorized },
            postNotification: { _ in delivered += 1 }
        )
        await notifier.prepareForSync()
        authorized.toggle()
        await notifier.syncSucceeded(result: SyncResult())
        #expect(delivered == (authorized ? 1 : 0))
    }

    @Test
    func returningToAppDuringPermissionLookupSuppressesNotification() async {
        var active = false
        var delivered = 0
        let notifier = SyncCompletionNotifier(
            isAppActive: { active },
            requestAuthorization: { true },
            currentAuthorization: {
                active = true
                return true
            },
            postNotification: { _ in delivered += 1 }
        )
        await notifier.prepareForSync()
        await notifier.syncSucceeded(result: SyncResult())
        #expect(delivered == 0)
    }

    @Test
    func deliveryFailureIsNonfatal() async {
        var attempts = 0
        let notifier = SyncCompletionNotifier(
            isAppActive: { false },
            requestAuthorization: { true },
            currentAuthorization: { true },
            postNotification: { _ in
                attempts += 1
                throw CocoaError(.featureUnsupported)
            }
        )
        await notifier.prepareForSync()
        await notifier.syncSucceeded(result: SyncResult())
        #expect(attempts == 1)
    }
}
