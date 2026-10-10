import Foundation

public enum MatchTarget: String, Codable, Sendable, Hashable {
    case processed
    case original
}

public struct Rule: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var condition: RuleCondition
    public var action: RuleAction
    public var matchTarget: MatchTarget

    public init(
        id: UUID = UUID(), name: String, isEnabled: Bool = true,
        condition: RuleCondition, action: RuleAction, matchTarget: MatchTarget = .processed
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.condition = condition
        self.action = action
        self.matchTarget = matchTarget
    }
}

public enum RuleCondition: Codable, Sendable, Hashable {
    case hostExact(String)
    case hostIncludingSubdomains(String)
    case urlPrefix(String)
    case pathPattern(host: String?, pattern: String)
    case sourceApp(bundleID: String)
    case mailRecipientDomain(String)
}

public enum RuleAction: Codable, Sendable, Hashable {
    case open(DestinationID, privateWindow: Bool)
    case showPicker
}
