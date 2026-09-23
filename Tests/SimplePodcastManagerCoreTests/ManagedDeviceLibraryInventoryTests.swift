import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct ManagedDeviceLibraryInventoryTests {
    @Test
    func retainingSubscriptionsRejectsNewPodcastsAndChangedDeviceOrFolder() {
        let podcast = PodcastSubscription(title: "News", rssURL: URL(string: "https://example.com/rss")!)
        let added = PodcastSubscription(title: "Added", rssURL: URL(string: "https://example.com/added")!)
        let device = DeviceInfo(name: "Test", rootURL: URL(fileURLWithPath: "/Volumes/TEST"),
                                podcastDirectoryURL: URL(fileURLWithPath: "/Volumes/TEST/music"))
        let inventory = ManagedDeviceLibraryInventory(device: device, subscriptions: [podcast],
            managedDirectoryURLsBySubscriptionID: [:], filesBySubscriptionID: [:])
        #expect(inventory.retaining(subscriptions: [], on: device)?.canBeUsed(on: device, subscriptions: []) == true)
        #expect(inventory.retaining(subscriptions: [podcast, added], on: device) == nil)
        var changedDevice = device
        changedDevice.rootURL = URL(fileURLWithPath: "/Volumes/OTHER")
        #expect(inventory.retaining(subscriptions: [], on: changedDevice) == nil)
        changedDevice = device
        changedDevice.podcastDirectoryURL = device.rootURL.appendingPathComponent("podcasts")
        #expect(inventory.retaining(subscriptions: [], on: changedDevice) == nil)
    }
}
