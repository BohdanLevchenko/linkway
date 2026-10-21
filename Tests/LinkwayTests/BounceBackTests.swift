import Foundation
import LinkwayCore
import Testing
@testable import Linkway

@Test func bounceBackUsesLatestLaunchStartAtArrival() {
    var tracker = BounceBackTracker()
    let start = Date(timeIntervalSince1970: 100)
    func link(_ offset: TimeInterval, sender: String? = "COM.EXAMPLE.BROWSER") -> IncomingLink {
        IncomingLink(url: URL(string: "https://example.com/")!, receivedAt: start.addingTimeInterval(offset), senderBundleID: sender, forcePicker: false)
    }
    tracker.recordLaunch(bundleID: "com.example.browser", startedAt: start)
    let inFlightBounce = tracker.isBounceBack(link(0.1))
    #expect(inFlightBounce)
    #expect(!tracker.isBounceBack(link(-0.1)))
    #expect(tracker.isBounceBack(link(2.99)))
    #expect(!tracker.isBounceBack(link(3)))
    #expect(!tracker.isBounceBack(link(0.1, sender: nil)))
    #expect(!tracker.isBounceBack(link(0.1, sender: "other.browser")))
    tracker.recordLaunch(bundleID: "other.browser", startedAt: start.addingTimeInterval(0.2))
    #expect(tracker.isBounceBack(link(0.1)))
    tracker.recordLaunch(bundleID: "com.example.browser", startedAt: start.addingTimeInterval(10))
    #expect(tracker.isBounceBack(link(10.5)))
    #expect(!tracker.isBounceBack(link(9.9)))
    #expect(inFlightBounce)
}
