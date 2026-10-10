import Foundation

public enum LinkKind: Sendable, Hashable {
    case web
    case mail
    case localFile
    case custom
}

public struct IncomingLink: Sendable, Hashable {
    public let url: URL
    public let receivedAt: Date
    public let senderBundleID: String?
    public let forcePicker: Bool

    public init(url: URL, receivedAt: Date, senderBundleID: String?, forcePicker: Bool) {
        self.url = url
        self.receivedAt = receivedAt
        self.senderBundleID = senderBundleID
        self.forcePicker = forcePicker
    }

    public var kind: LinkKind {
        switch url.scheme?.lowercased() {
        case "http", "https": .web
        case "mailto": .mail
        case "file": .localFile
        default: .custom
        }
    }
}
