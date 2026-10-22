import Foundation

public enum FallbackPolicy: Codable, Sendable, Hashable {
    case showPicker
    case open(DestinationID)

    enum OpenCodingKeys: String, CodingKey { case _0 = "destination" }
}

public struct FallbackPolicies: Codable, Sendable, Hashable {
    public var web: FallbackPolicy
    public var mail: FallbackPolicy

    public init(web: FallbackPolicy = .showPicker, mail: FallbackPolicy = .showPicker) {
        self.web = web
        self.mail = mail
    }
}

public enum RoutingDecision: Sendable, Hashable {
    case launch(LaunchRequest, matchedRule: UUID?)
    case showPicker(PickerReason)
}

public enum PickerReason: Sendable, Hashable {
    case noMatch
    case forcedByUser
    case ruleRequestsPicker(UUID)
    case ruleTargetUnavailable(UUID, DestinationID)
}

public struct RuleEvaluation: Sendable, Hashable {
    public let ruleID: UUID
    public let url: URL
    public let matched: Bool
    public let reason: String
}

public struct RoutingExplanation: Sendable, Hashable {
    public let processedURL: URL?
    public let removedParameters: [String]
    public let wouldExpandShortLink: Bool
    public init(evaluations: [RuleEvaluation], decision: RoutingDecision, processedURL: URL? = nil,
                removedParameters: [String] = [], wouldExpandShortLink: Bool = false) {
        self.evaluations = evaluations
        self.decision = decision
        self.processedURL = processedURL
        self.removedParameters = removedParameters
        self.wouldExpandShortLink = wouldExpandShortLink
    }
    public let evaluations: [RuleEvaluation]
    public let decision: RoutingDecision
}

public struct RoutingEngine: Sendable {
    public let rules: [Rule]
    public let fallbacks: FallbackPolicies

    public init(rules: [Rule], fallback: FallbackPolicy) {
        self.init(rules: rules, fallbacks: FallbackPolicies(web: fallback, mail: fallback))
    }

    public init(rules: [Rule], fallbacks: FallbackPolicies) {
        self.rules = rules
        self.fallbacks = fallbacks
    }

    public func decide(_ link: IncomingLink, processedURL: URL, availableDestinations: Set<DestinationID>, pickerOrder: [DestinationID] = []) -> RoutingDecision {
        explain(link, processedURL: processedURL, availableDestinations: availableDestinations, pickerOrder: pickerOrder).decision
    }

    public func explain(_ link: IncomingLink, processedURL: URL, availableDestinations: Set<DestinationID>, pickerOrder: [DestinationID] = []) -> RoutingExplanation {
        if case .prompt = link.mode {
            return RoutingExplanation(evaluations: [], decision: .showPicker(.forcedByUser))
        }
        if link.mode == .route && link.forcePicker {
            return RoutingExplanation(evaluations: [], decision: .showPicker(.forcedByUser))
        }
        var evaluations: [RuleEvaluation] = []
        for rule in rules {
            let url = rule.matchTarget == .original ? link.url : processedURL
            guard rule.isEnabled else {
                evaluations.append(RuleEvaluation(ruleID: rule.id, url: url, matched: false, reason: "rule is disabled"))
                continue
            }
            let result = URLMatcher.evaluate(rule.condition, link: link, url: url)
            evaluations.append(RuleEvaluation(ruleID: rule.id, url: url, matched: result.matched, reason: result.reason))
            guard result.matched else { continue }
            let decision: RoutingDecision
            switch rule.action {
            case .showPicker:
                decision = .showPicker(.ruleRequestsPicker(rule.id))
            case .open(let destination, let privateWindow):
                if availableDestinations.contains(destination) {
                    decision = .launch(LaunchRequest(url: processedURL, destination: destination, privateWindow: privateWindow), matchedRule: rule.id)
                } else {
                    decision = .showPicker(.ruleTargetUnavailable(rule.id, destination))
                }
            }
            return RoutingExplanation(evaluations: evaluations, decision: decision)
        }
        if case .best = link.mode {
            let decision: RoutingDecision = pickerOrder.first(where: { availableDestinations.contains($0) })
                .map { .launch(LaunchRequest(url: processedURL, destination: $0), matchedRule: nil) }
                ?? .showPicker(.noMatch)
            return RoutingExplanation(evaluations: evaluations, decision: decision)
        }
        let fallback: FallbackPolicy
        switch link.kind {
        case .web: fallback = fallbacks.web
        case .mail: fallback = fallbacks.mail
        case .localFile, .custom: fallback = .showPicker
        }
        let decision: RoutingDecision
        switch fallback {
        case .showPicker:
            decision = .showPicker(.noMatch)
        case .open(let destination):
            if availableDestinations.contains(destination) {
                decision = .launch(LaunchRequest(url: processedURL, destination: destination), matchedRule: nil)
            } else {
                decision = .showPicker(.noMatch)
            }
        }
        return RoutingExplanation(evaluations: evaluations, decision: decision)
    }
}
