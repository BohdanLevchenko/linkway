import Foundation

public struct WebmailAccount: Codable, Sendable, Hashable, Identifiable {
    public static let bundleID = "linkway.webmail"
    public let id: UUID
    public var provider: WebmailProvider
    public var displayName: String
    public var account: String?
    public var browser: DestinationID

    public init(id: UUID = UUID(), provider: WebmailProvider, displayName: String,
                account: String? = nil, browser: DestinationID) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.account = account
        self.browser = browser
    }

    public var destinationID: DestinationID { DestinationID(bundleID: Self.bundleID, profileKey: id.uuidString) }

    public func destination(target: Destination) -> Destination? {
        guard target.id == browser, target.kind == .browser else { return nil }
        return Destination(id: destinationID, kind: .mailClient, appName: provider.name,
                           profileName: displayName, appURL: target.appURL, supportsPrivateWindow: false,
                           avatarURL: target.avatarURL, highlightColorARGB: target.highlightColorARGB)
    }

    public func launchRequest(for url: URL) -> LaunchRequest? {
        guard let message = MailtoMessage(url: url) else { return nil }
        return LaunchRequest(url: provider.composeURL(for: message, account: account), destination: browser)
    }
}
