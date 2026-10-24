import Foundation

public struct DeepLinkAdapter: Sendable, Hashable, Identifiable {
    public enum ID: String, Sendable, Hashable, CaseIterable {
        case figma, linear, notion, slack, zoom, teams, spotify, discord
    }

    public enum Kind: Sendable, Hashable {
        case rewrite
        case openWebURLInApp
    }

    public let id: ID
    public let appBundleIDs: [String]
    public let displayName: String
    public let kind: Kind
    public let hosts: [String]
    public let includesSubdomains: Bool

    public func matchesHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return hosts.contains { host == $0 || (includesSubdomains && host.hasSuffix("." + $0)) }
    }

    /// Returns the launch URL, including the unchanged HTTPS URL for direct app delivery.
    public func appURL(for webURL: URL) -> URL? {
        guard var components = URLComponents(url: webURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host, matchesHost(host),
              components.user == nil, components.password == nil, components.port == nil else { return nil }
        let path = components.percentEncodedPath
        let normalizedPath = path.lowercased()
        guard !path.contains("\\"), !normalizedPath.contains("%2f"), !normalizedPath.contains("%5c"),
              let decodedPath = path.removingPercentEncoding,
              !decodedPath.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else { return nil }
        switch id {
        case .figma:
            guard parts.count >= 2, Self.figmaPaths.contains(parts[0]) else { return nil }
            return URL(string: "figma://" + parts.joined(separator: "/") + Self.suffix(components))
        case .linear:
            guard parts.count >= 2, parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return nil }
            return URL(string: "linear://" + parts.joined(separator: "/") + Self.suffix(components))
        case .notion:
            components.scheme = "notion"
            return components.url
        case .slack:
            let team = host.lowercased().dropLast(".slack.com".count)
            guard host.lowercased() != "slack.com", !team.isEmpty, !team.contains("."),
                  parts.count == 2 || parts.count == 3, parts[0] == "archives",
                  Self.isIdentifier(parts[1]),
                  parts.count == 2 || (parts[2].hasPrefix("p") && Self.isDigits(String(parts[2].dropFirst())))
            else { return nil }
            return webURL
        case .zoom:
            guard parts.count == 2, parts[0] == "j", Self.isDigits(parts[1]) else { return nil }
            var target = URLComponents()
            target.scheme = "zoommtg"
            target.host = "zoom.us"
            target.path = "/join"
            // Keep the encoded password intact, including literal plus signs.
            let passwords = (components.percentEncodedQuery ?? "").split(separator: "&")
                .filter { $0.split(separator: "=", maxSplits: 1).first == "pwd" }
            guard passwords.count <= 1 else { return nil }
            target.percentEncodedQuery = "confno=" + parts[1] + passwords.map { "&" + $0 }.joined()
            return target.url
        case .teams:
            guard parts.count >= 2, parts[0] == "l" else { return nil }
            return URL(string: "msteams:" + path + Self.suffix(components))
        case .spotify:
            var content = parts
            if let prefix = content.first, prefix.count == "intl-xx".count,
               prefix.hasPrefix("intl-"), prefix.suffix(2).allSatisfy({ $0.isASCII && $0.isLetter }) {
                content.removeFirst()
            }
            guard content.count == 2, Self.spotifyTypes.contains(content[0]), Self.isIdentifier(content[1]) else { return nil }
            return URL(string: "spotify:" + content.joined(separator: ":"))
        case .discord:
            guard parts.count >= 3, parts.count <= 4, parts[0] == "channels",
                  parts[1] == "@me" || Self.isDigits(parts[1]),
                  parts.dropFirst(2).allSatisfy(Self.isDigits) else { return nil }
            components.scheme = "discord"
            return components.url
        }
    }

    private static let figmaPaths: Set<String> = ["file", "design", "board", "proto", "slides"]
    private static let spotifyTypes: Set<String> = ["track", "album", "artist", "playlist", "show", "episode"]

    private static func suffix(_ components: URLComponents) -> String {
        (components.percentEncodedQuery.map { "?" + $0 } ?? "")
            + (components.percentEncodedFragment.map { "#" + $0 } ?? "")
    }

    private static func isDigits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
    }
}

public enum DeepLinkCatalog {
    public static let adapters: [DeepLinkAdapter] = [
        .init(id: .figma, appBundleIDs: ["com.figma.Desktop"], displayName: "Figma", kind: .rewrite,
              hosts: ["www.figma.com"], includesSubdomains: false),
        .init(id: .linear, appBundleIDs: ["com.linear"], displayName: "Linear", kind: .rewrite,
              hosts: ["linear.app"], includesSubdomains: false),
        .init(id: .notion, appBundleIDs: ["notion.id"], displayName: "Notion", kind: .rewrite,
              hosts: ["www.notion.so"], includesSubdomains: false),
        .init(id: .slack, appBundleIDs: ["com.tinyspeck.slackmacgap"], displayName: "Slack", kind: .openWebURLInApp,
              hosts: ["slack.com"], includesSubdomains: true),
        .init(id: .zoom, appBundleIDs: ["us.zoom.xos"], displayName: "Zoom", kind: .rewrite,
              hosts: ["zoom.us"], includesSubdomains: true),
        .init(id: .teams, appBundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"], displayName: "Microsoft Teams", kind: .rewrite,
              hosts: ["teams.microsoft.com"], includesSubdomains: false),
        .init(id: .spotify, appBundleIDs: ["com.spotify.client"], displayName: "Spotify", kind: .rewrite,
              hosts: ["open.spotify.com"], includesSubdomains: false),
        .init(id: .discord, appBundleIDs: ["com.hnc.Discord"], displayName: "Discord", kind: .rewrite,
              hosts: ["discord.com"], includesSubdomains: false),
    ]

    public static func adapter(for bundleID: String) -> DeepLinkAdapter? {
        adapters.first { $0.appBundleIDs.contains(bundleID) }
    }

    public static func supports(_ destination: Destination, url: URL, disabledAdapters: [String]) -> Bool {
        guard destination.kind == .app else { return true }
        guard let adapter = adapter(for: destination.id.bundleID), destination.id.profileKey == nil,
              !disabledAdapters.contains(adapter.id.rawValue) else { return false }
        return adapter.appURL(for: url) != nil
    }

    public static func matchingApps(in destinations: [Destination], for url: URL, disabledAdapters: [String]) -> [Destination] {
        destinations.filter { $0.kind == .app && supports($0, url: url, disabledAdapters: disabledAdapters) }
    }
}
