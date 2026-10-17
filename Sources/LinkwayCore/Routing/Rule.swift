import Foundation

public enum MatchTarget: String, Codable, Sendable, Hashable {
    case processed
    case original
}

public enum RuleOrigin: String, Codable, Sendable, Hashable {
    case manual
    case remembered
}

public struct Rule: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var condition: RuleCondition
    public var action: RuleAction
    public var matchTarget: MatchTarget
    public var origin: RuleOrigin

    public init(
        id: UUID = UUID(), name: String, isEnabled: Bool = true,
        condition: RuleCondition, action: RuleAction, matchTarget: MatchTarget = .processed,
        origin: RuleOrigin = .manual
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.condition = condition
        self.action = action
        self.matchTarget = matchTarget
        self.origin = origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        condition = try container.decode(RuleCondition.self, forKey: .condition)
        action = try container.decode(RuleAction.self, forKey: .action)
        matchTarget = try container.decode(MatchTarget.self, forKey: .matchTarget)
        origin = try container.decodeIfPresent(RuleOrigin.self, forKey: .origin) ?? .manual
    }
}

public enum RuleCondition: Codable, Sendable, Hashable {
    case hostExact(String)
    case hostIncludingSubdomains(String)
    case urlPrefix(String)
    case pathPattern(host: String?, pattern: String)
    /// Host with or without `www.`, and a path equal to `pathPrefix` or below it at a `/` boundary.
    case sitePath(host: String, pathPrefix: String)
    case sourceApp(bundleID: String)
    case mailRecipientDomain(String)
}

public enum RuleAction: Codable, Sendable, Hashable {
    case open(DestinationID, privateWindow: Bool)
    case showPicker
}
