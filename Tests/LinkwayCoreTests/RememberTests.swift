import Foundation
import Testing
import LinkwayCore

private let chrome = DestinationID(bundleID: "com.google.Chrome", profileKey: "Default")
private let firefox = DestinationID(bundleID: "org.mozilla.firefox")

private func link(_ value: String) throws -> IncomingLink {
    IncomingLink(url: try #require(URL(string: value)), receivedAt: Date(), senderBundleID: nil, forcePicker: false)
}

@Test func rememberTargetPerLinkKind() throws {
    #expect(RuleSuggestion.rememberTarget(for: try link("https://www.GitHub.com/a/b")) ==
        RememberTarget(label: "github.com", condition: .hostIncludingSubdomains("github.com")))
    #expect(RuleSuggestion.rememberTarget(for: try link("mailto:Ann%20<ann@Acme.com>,bob@other.org")) ==
        RememberTarget(label: "mail to acme.com", condition: .mailRecipientDomain("acme.com")))
    #expect(RuleSuggestion.rememberTarget(for: try link("mailto:?subject=hi")) == nil)
    #expect(RuleSuggestion.rememberTarget(for: try link("file:///tmp/a.html")) == nil)
}

@Test func rememberReplacesSameConditionAndGoesFirst() throws {
    let target = try #require(RuleSuggestion.rememberTarget(for: try link("https://github.com/x")))
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
