import Foundation

public enum RuleSuggestion {
    public static func suggestedRule(for url: URL, destination: DestinationID, privateWindow: Bool) -> Rule {
        Rule(name: siteHost(url) ?? "", condition: .hostIncludingSubdomains(siteHost(url) ?? ""),
             action: .open(destination, privateWindow: privateWindow))
    }

    /// What a "remember this choice" from the picker would match, or nil when the link has nothing stable to key on.
    public static func rememberTarget(for link: IncomingLink) -> RememberTarget? {
        switch link.kind {
        case .web:
            return siteHost(link.url).map { RememberTarget(label: $0, condition: .hostIncludingSubdomains($0)) }
        case .mail:
            let components = URLComponents(url: link.url, resolvingAgainstBaseURL: false)
            return URLMatcher.recipientDomains(components).first.flatMap(URLMatcher.normalizedHost).map {
                RememberTarget(label: "mail to \($0)", condition: .mailRecipientDomain($0))
            }
        case .localFile, .custom:
            return nil
        }
    }

    private static func siteHost(_ url: URL) -> String? {
        guard var host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host.flatMap(URLMatcher.normalizedHost),
              !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}

public struct RememberTarget: Sendable, Hashable {
    public let label: String
    public let condition: RuleCondition

    public init(label: String, condition: RuleCondition) {
        self.label = label
        self.condition = condition
    }

    public func rule(destination: DestinationID, privateWindow: Bool) -> Rule {
        Rule(name: label, condition: condition, action: .open(destination, privateWindow: privateWindow), origin: .remembered)
    }
}

extension LinkwayConfiguration {
    /// A remembered choice is the user's latest explicit decision, so it replaces any rule with the same
    /// condition and goes first to beat broader rules.
    public mutating func remember(_ target: RememberTarget, destination: DestinationID, privateWindow: Bool) {
        rules.removeAll { $0.condition == target.condition }
        rules.insert(target.rule(destination: destination, privateWindow: privateWindow), at: 0)
    }

    public var rememberedRules: [Rule] { rules.filter { $0.origin == .remembered } }

    public mutating func forgetRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }
}
