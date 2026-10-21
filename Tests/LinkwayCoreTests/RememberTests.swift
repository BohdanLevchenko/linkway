import Foundation
import Testing
import LinkwayCore

private let chrome = DestinationID(bundleID: "com.google.Chrome", profileKey: "Default")
private let firefox = DestinationID(bundleID: "org.mozilla.firefox")

private func link(_ value: String) throws -> IncomingLink {
    IncomingLink(url: try #require(URL(string: value)), receivedAt: Date(), senderBundleID: nil, forcePicker: false)
}

@Test func rememberTargetsPerLinkKind() throws {
    #expect(RuleSuggestion.rememberTargets(for: try link("https://www.GitHub.com/antiwork/gumroad/pulls?q=1")) == [
        RememberTarget(label: "github.com", condition: .hostIncludingSubdomains("github.com")),
        RememberTarget(label: "github.com/antiwork", condition: .sitePath(host: "github.com", pathPrefix: "/antiwork")),
        RememberTarget(label: "github.com/antiwork/gumroad", condition: .sitePath(host: "github.com", pathPrefix: "/antiwork/gumroad")),
    ])
    #expect(RuleSuggestion.rememberTargets(for: try link("https://example.com/")).count == 1)
    #expect(RuleSuggestion.rememberTargets(for: try link("mailto:Ann%20<ann@Acme.com>,bob@other.org")) ==
        [RememberTarget(label: "mail to acme.com", condition: .mailRecipientDomain("acme.com"))])
    #expect(RuleSuggestion.rememberTargets(for: try link("mailto:?subject=hi")).isEmpty)
    #expect(RuleSuggestion.rememberTargets(for: try link("file:///tmp/a.html")).isEmpty)
}

@Test func sitePathMatchesAtSegmentBoundary() throws {
    let condition = RuleCondition.sitePath(host: "github.com", pathPrefix: "/spf13")
    for value in ["https://github.com/spf13", "https://www.github.com/spf13/cobra", "http://github.com/spf13/"] {
        #expect(URLMatcher.matches(condition, link: try link(value), url: try link(value).url), "\(value)")
    }
    for value in ["https://github.com/spf13x", "https://gist.github.com/spf13", "https://github.com/", "mailto:spf13@github.com"] {
        #expect(!URLMatcher.matches(condition, link: try link(value), url: try link(value).url), "\(value)")
    }
}

@Test func narrowerRememberedPathsWin() throws {
    let brave = DestinationID(bundleID: "com.brave.Browser")
    func targets(_ value: String) throws -> [RememberTarget] { RuleSuggestion.rememberTargets(for: try link(value)) }
    var configuration = LinkwayConfiguration(rules: [Rule(name: "manual", condition: .hostExact("github.com"), action: .showPicker)])
    configuration.remember(try targets("https://github.com/antiwork/x")[1], destination: firefox, privateWindow: false)
    configuration.remember(try targets("https://github.com/spf13")[1], destination: brave, privateWindow: false)
    configuration.remember(try targets("https://github.com/")[0], destination: chrome, privateWindow: false)
    #expect(configuration.rules.map(\.name) == ["github.com/spf13", "github.com/antiwork", "github.com", "manual"])

    let engine = RoutingEngine(rules: configuration.rules, fallbacks: configuration.fallbacks)
    let available: Set = [chrome, firefox, brave]
    for (value, expected) in [("https://github.com/antiwork/gumroad", firefox), ("https://github.com/spf13/viper", brave),
                              ("https://github.com/apple/swift", chrome)] {
        let input = try link(value)
        guard case .launch(let request, _) = engine.decide(input, processedURL: input.url, availableDestinations: available) else {
            Issue.record("expected launch for \(value)")
            continue
        }
        #expect(request.destination == expected, "\(value)")
    }
}

@Test func rememberReplacesSameConditionAndGoesFirst() throws {
    let target = try #require(RuleSuggestion.rememberTargets(for: try link("https://github.com/x")).first)
    var configuration = LinkwayConfiguration(rules: [
        Rule(name: "broad", condition: .urlPrefix("https://github.com"), action: .showPicker),
        Rule(name: "old", condition: .hostIncludingSubdomains("github.com"), action: .open(firefox, privateWindow: false)),
    ])
    configuration.remember(target, destination: chrome, privateWindow: true)
    #expect(configuration.rules.map(\.name) == ["github.com", "broad"])
    #expect(configuration.rules[0].action == .open(chrome, privateWindow: true))
    #expect(configuration.rememberedRules.count == 1)

    let engine = RoutingEngine(rules: configuration.rules, fallbacks: configuration.fallbacks)
    let input = try link("https://gist.github.com/y")
    guard case .launch(let request, _) = engine.decide(input, processedURL: input.url, availableDestinations: [chrome]) else {
        Issue.record("expected launch")
        return
    }
    #expect(request.destination == chrome)

    configuration.forgetRule(id: configuration.rules[0].id)
    #expect(configuration.rememberedRules.isEmpty)
}

@Test func ruleWithoutOriginDecodesAsManual() throws {
    let rule = Rule(name: "r", condition: .hostExact("a.com"), action: .showPicker, origin: .remembered)
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
    #expect(json["origin"] as? String == "remembered")
    json["origin"] = nil
    let decoded = try JSONDecoder().decode(Rule.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.origin == .manual)
}

@Test func rememberOriginalURLSurvivesProcessingAndRoundTrip() throws {
    let original = try link("https://bit.ly/a")
    let processed = try #require(URL(string: "https://example.com/article"))
    let target = try #require(RuleSuggestion.rememberTargets(for: original, matchTarget: .original).first)
    #expect(target.label == "bit.ly")
    #expect(target.matchTarget == .original)
    var configuration = LinkwayConfiguration()
    configuration.remember(target, destination: chrome, privateWindow: false)
    configuration = try JSONDecoder().decode(LinkwayConfiguration.self, from: JSONEncoder().encode(configuration))
    #expect(configuration.rules.first?.matchTarget == .original)
    let decision = RoutingEngine(rules: configuration.rules, fallbacks: configuration.fallbacks)
        .decide(original, processedURL: processed, availableDestinations: [chrome])
    guard case .launch(let request, _) = decision else { Issue.record("original remembered rule did not match"); return }
    #expect(request.destination == chrome)
}

@Test func rememberReplacementIncludesMatchTarget() {
    let condition = RuleCondition.hostIncludingSubdomains("bit.ly")
    var configuration = LinkwayConfiguration()
    configuration.remember(RememberTarget(label: "processed", condition: condition), destination: chrome, privateWindow: false)
    configuration.remember(RememberTarget(label: "original", condition: condition, matchTarget: .original), destination: firefox, privateWindow: false)
    configuration.remember(RememberTarget(label: "updated", condition: condition, matchTarget: .original), destination: chrome, privateWindow: true)
    #expect(configuration.rules.count == 2)
    #expect(configuration.rules.filter { $0.matchTarget == .processed }.first?.name == "processed")
    #expect(configuration.rules.filter { $0.matchTarget == .original }.first?.action == .open(chrome, privateWindow: true))
}
