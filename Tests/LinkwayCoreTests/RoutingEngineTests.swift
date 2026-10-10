import Foundation
import Testing
import LinkwayCore

private let browser = DestinationID(bundleID: "com.example.browser")
private let mail = DestinationID(bundleID: "com.example.mail")

private func link(_ value: String = "https://example.com/original", forced: Bool = false, sender: String? = nil) throws -> IncomingLink {
    IncomingLink(url: try #require(URL(string: value)), receivedAt: Date(), senderBundleID: sender, forcePicker: forced)
}

@Test func orderedRulesAndUnavailableTarget() throws {
    let input = try link()
    let first = Rule(name: "first", condition: .hostExact("example.com"), action: .open(browser, privateWindow: true))
    let second = Rule(name: "second", condition: .hostExact("example.com"), action: .showPicker)
    let engine = RoutingEngine(rules: [first, second], fallback: .showPicker)
    #expect(engine.decide(input, processedURL: input.url, availableDestinations: [browser]) ==
        .launch(LaunchRequest(url: input.url, destination: browser, privateWindow: true), matchedRule: first.id))
    #expect(engine.decide(input, processedURL: input.url, availableDestinations: []) ==
        .showPicker(.ruleTargetUnavailable(first.id, browser)))
    #expect(engine.explain(input, processedURL: input.url, availableDestinations: []).evaluations.count == 1)
}

@Test func disabledRulesAndExplanation() throws {
    let input = try link()
    let disabled = Rule(name: "disabled", isEnabled: false, condition: .hostExact("example.com"), action: .open(browser, privateWindow: false))
    let miss = Rule(name: "miss", condition: .hostIncludingSubdomains("other.com"), action: .showPicker)
    let match = Rule(name: "match", condition: .hostExact("example.com"), action: .showPicker)
    let engine = RoutingEngine(rules: [disabled, miss, match], fallback: .open(browser))
    let explanation = engine.explain(input, processedURL: input.url, availableDestinations: [browser])
    #expect(explanation.decision == .showPicker(.ruleRequestsPicker(match.id)))
    #expect(explanation.evaluations.map(\.matched) == [false, false, true])
    #expect(explanation.evaluations[0].reason == "rule is disabled")
    #expect(explanation.evaluations[1].reason == "host example.com is not other.com or a subdomain")
    #expect(explanation.evaluations.map(\.ruleID) == [disabled.id, miss.id, match.id])
}

@Test func forcePickerPrecedesRulesAndFallback() throws {
    let input = try link(forced: true)
    let rule = Rule(name: "all", condition: .hostExact("example.com"), action: .open(browser, privateWindow: false))
    let explanation = RoutingEngine(rules: [rule], fallback: .open(browser))
        .explain(input, processedURL: input.url, availableDestinations: [browser])
    #expect(explanation.decision == .showPicker(.forcedByUser))
    #expect(explanation.evaluations.isEmpty)
}

@Test func originalMatchingLaunchesProcessedURL() throws {
    let input = try link("https://short.example/a")
    let processed = try #require(URL(string: "https://expanded.example/clean"))
    let original = Rule(name: "short", condition: .hostExact("short.example"), action: .open(browser, privateWindow: false), matchTarget: .original)
    let engine = RoutingEngine(rules: [original], fallback: .showPicker)
    #expect(engine.decide(input, processedURL: processed, availableDestinations: [browser]) ==
        .launch(LaunchRequest(url: processed, destination: browser), matchedRule: original.id))
    #expect(engine.explain(input, processedURL: processed, availableDestinations: [browser]).evaluations.first?.url == input.url)
    var defaultRule = original
    defaultRule.matchTarget = .processed
    #expect(RoutingEngine(rules: [defaultRule], fallback: .showPicker).decide(input, processedURL: processed, availableDestinations: [browser]) == .showPicker(.noMatch))
}

@Test(arguments: ["https://example.com", "mailto:a@example.com", "file:///tmp/a.html", "custom://example.com"])
func separateFallbacks(value: String) throws {
    let input = try link(value)
    let engine = RoutingEngine(rules: [], fallbacks: FallbackPolicies(web: .open(browser), mail: .open(mail)))
    let expected: RoutingDecision
    switch input.kind {
    case .web: expected = .launch(LaunchRequest(url: input.url, destination: browser), matchedRule: nil)
    case .mail: expected = .launch(LaunchRequest(url: input.url, destination: mail), matchedRule: nil)
    case .custom, .localFile: expected = .showPicker(.noMatch)
    }
    #expect(engine.decide(input, processedURL: input.url, availableDestinations: [browser, mail]) == expected)
    #expect(engine.decide(input, processedURL: input.url, availableDestinations: []) == .showPicker(.noMatch))
}

@Test(arguments: ["https://example.com", "mailto:a@example.com", "file:///tmp/a.html", "custom://example.com"])
func decideAndExplainAgreement(value: String) throws {
    let rules = [
        Rule(name: "web", condition: .hostIncludingSubdomains("example.com"), action: .open(browser, privateWindow: true)),
        Rule(name: "mail", condition: .mailRecipientDomain("example.com"), action: .open(mail, privateWindow: false)),
        Rule(name: "custom", condition: .urlPrefix("custom:"), action: .showPicker),
        Rule(name: "sender", condition: .sourceApp(bundleID: "com.example.sender"), action: .showPicker),
    ]
    let engine = RoutingEngine(rules: rules, fallback: .open(browser))
    for forced in [false, true] {
        for available: Set<DestinationID> in [[], [browser], [browser, mail]] {
            for sender in [nil, "com.example.sender"] {
                let input = try link(value, forced: forced, sender: sender)
                #expect(engine.decide(input, processedURL: input.url, availableDestinations: available) ==
                    engine.explain(input, processedURL: input.url, availableDestinations: available).decision)
            }
        }
    }
}

@Test func localAndCustomConditionsAreRestricted() throws {
    for value in ["file://example.com/tmp/a.html", "custom://example.com/a"] {
        let input = try link(value)
        let disallowed: [RuleCondition] = [.hostExact("example.com"), .hostIncludingSubdomains("example.com"), .pathPattern(host: nil, pattern: "**"), .mailRecipientDomain("example.com")]
        let rules = disallowed.map { Rule(name: "restricted", condition: $0, action: .open(browser, privateWindow: false)) }
        let engine = RoutingEngine(rules: rules, fallback: .open(browser))
        #expect(engine.decide(input, processedURL: input.url, availableDestinations: [browser]) == .showPicker(.noMatch))
    }
}

@Test func ruleSuggestionOnlyStripsWWW() throws {
    for (url, host) in [("https://WWW.Example.com/path", "example.com"), ("https://a.example.co.uk", "a.example.co.uk"), ("https://www.bücher.de", "xn--bcher-kva.de")] {
        let rule = RuleSuggestion.suggestedRule(for: try #require(URL(string: url)), destination: browser, privateWindow: true)
        #expect(rule.name == host)
        #expect(rule.condition == .hostIncludingSubdomains(host))
        #expect(rule.action == .open(browser, privateWindow: true))
        #expect(rule.matchTarget == .processed)
    }
}
