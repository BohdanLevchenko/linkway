import Foundation

public enum RuleSuggestion {
    public static func suggestedRule(for url: URL, destination: DestinationID, privateWindow: Bool) -> Rule {
        Rule(name: siteHost(url) ?? "", condition: .hostIncludingSubdomains(siteHost(url) ?? ""),
             action: .open(destination, privateWindow: privateWindow))
    }

    /// Scopes a picker choice can be remembered for, broad to narrow: the site, then each leading path segment
    /// (up to `maxPathDepth`). Empty when the link has nothing stable to key on.
    public static func rememberTargets(for link: IncomingLink, maxPathDepth: Int = 2, matchTarget: MatchTarget = .processed) -> [RememberTarget] {
        switch link.kind {
        case .web:
            guard let host = siteHost(link.url) else { return [] }
            let path = URLComponents(url: link.url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
            let segments = path.split(separator: "/").prefix(maxPathDepth)
            let paths = segments.indices.map { "/" + segments[...$0].joined(separator: "/") }
            return [RememberTarget(label: host, condition: .hostIncludingSubdomains(host), matchTarget: matchTarget)] + paths.map {
                RememberTarget(label: host + ($0.removingPercentEncoding ?? $0), condition: .sitePath(host: host, pathPrefix: $0), matchTarget: matchTarget)
            }
        case .mail:
            let components = URLComponents(url: link.url, resolvingAgainstBaseURL: false)
            return URLMatcher.recipientDomains(components).first.flatMap(URLMatcher.normalizedHost).map {
                [RememberTarget(label: "mail to \($0)", condition: .mailRecipientDomain($0), matchTarget: matchTarget)]
            } ?? []
        case .localFile, .custom:
            return []
        }
    }

    private static func siteHost(_ url: URL) -> String? {
        guard var host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host.flatMap(URLMatcher.normalizedHost),
              !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}

private extension RuleCondition {
    var specificity: Int {
        switch self {
        case .sitePath(_, let pathPrefix): 1 + pathPrefix.split(separator: "/").count
        default: 1
        }
    }
}

public struct RememberTarget: Sendable, Hashable {
    public let label: String
    public let condition: RuleCondition
    public let matchTarget: MatchTarget

    public init(label: String, condition: RuleCondition, matchTarget: MatchTarget = .processed) {
        self.label = label
        self.condition = condition
        self.matchTarget = matchTarget
    }

    public func rule(destination: DestinationID, privateWindow: Bool) -> Rule {
        Rule(name: label, condition: condition, action: .open(destination, privateWindow: privateWindow), matchTarget: matchTarget, origin: .remembered)
    }
}

extension LinkwayConfiguration {
    /// A remembered choice is the user's latest explicit decision: it replaces any rule with the same condition and match target
    /// and joins the leading block of remembered rules, ahead of manual ones. Within that block, narrower paths
    /// go first so github.com/antiwork beats github.com; among equals, the newest goes first.
    public mutating func remember(_ target: RememberTarget, destination: DestinationID, privateWindow: Bool) {
        rules.removeAll { $0.condition == target.condition && $0.matchTarget == target.matchTarget }
        let rule = target.rule(destination: destination, privateWindow: privateWindow)
        let index = rules.firstIndex {
            $0.origin != .remembered || $0.condition.specificity <= rule.condition.specificity
        } ?? rules.endIndex
        rules.insert(rule, at: index)
    }

    public var rememberedRules: [Rule] { rules.filter { $0.origin == .remembered } }

    public mutating func forgetRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }
}
