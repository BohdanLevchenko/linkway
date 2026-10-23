import Foundation

/// Stable identifier persisted in rules and preferences.
/// Format: `<bundleID>` for an app, `<bundleID>#<profileKey>` for a browser profile.
public struct DestinationID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let bundleID: String
    public let profileKey: String?

    public init(bundleID: String, profileKey: String? = nil) {
        self.bundleID = bundleID
        self.profileKey = profileKey
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "#", maxSplits: 1).map(String.init)
        guard let bundleID = parts.first, !bundleID.isEmpty else { return nil }
        self.init(bundleID: bundleID, profileKey: parts.count == 2 ? parts[1] : nil)
    }

    public var rawValue: String {
        profileKey.map { "\(bundleID)#\($0)" } ?? bundleID
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = DestinationID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Invalid destination id: \(raw)"
            ))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum DestinationKind: String, Sendable, Hashable, Codable {
    case browser
    case mailClient
    case app
}

public struct Destination: Sendable, Hashable, Identifiable {
    public let id: DestinationID
    public let kind: DestinationKind
    public let appName: String
    public let profileName: String?
    public let appURL: URL
    public let avatarURL: URL?
    public let firefoxAvatar: String?
    public let foregroundColorARGB: Int?
    public let highlightColorARGB: Int?
    public let supportsPrivateWindow: Bool

    public init(
        id: DestinationID,
        kind: DestinationKind,
        appName: String,
        profileName: String?,
        appURL: URL,
        supportsPrivateWindow: Bool,
        avatarURL: URL? = nil, highlightColorARGB: Int? = nil,
        firefoxAvatar: String? = nil, foregroundColorARGB: Int? = nil
    ) {
        self.firefoxAvatar = firefoxAvatar
        self.foregroundColorARGB = foregroundColorARGB
        self.avatarURL = avatarURL
        self.highlightColorARGB = highlightColorARGB
        self.id = id
        self.kind = kind
        self.appName = appName
        self.profileName = profileName
        self.appURL = appURL
        self.supportsPrivateWindow = supportsPrivateWindow
    }

    public var displayName: String {
        profileName.map { "\(appName) · \($0)" } ?? appName
    }
}

/// What the user or a rule asked for.
public struct LaunchRequest: Sendable, Hashable {
    public let url: URL
    public let destination: DestinationID
    public let privateWindow: Bool

    public init(url: URL, destination: DestinationID, privateWindow: Bool = false) {
        self.url = url
        self.destination = destination
        self.privateWindow = privateWindow
    }
}
