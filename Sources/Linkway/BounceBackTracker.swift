import Foundation
import LinkwayCore

struct BounceBackTracker {
    static let window: TimeInterval = 3
    private var starts: [String: Date] = [:]

    mutating func recordLaunch(bundleID: String, startedAt: Date) {
        starts = starts.filter { startedAt.timeIntervalSince($0.value) < Self.window }
        starts[bundleID.lowercased()] = startedAt
    }

    func isBounceBack(_ link: IncomingLink) -> Bool {
        guard let sender = link.senderBundleID, let start = starts[sender.lowercased()] else { return false }
        let elapsed = link.receivedAt.timeIntervalSince(start)
        return elapsed >= 0 && elapsed < Self.window
    }
}
