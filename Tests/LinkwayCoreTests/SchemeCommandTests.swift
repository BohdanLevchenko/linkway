import Foundation
import LinkwayCore
import Testing

@Test(arguments: [
    ("linkway", "open", SchemeCommand.Mode.route),
    ("linkway", "prompt", .prompt(scope: .all)),
    ("x-choosy", "open", .route),
    ("x-choosy", "prompt.all", .prompt(scope: .all)),
    ("x-choosy", "prompt.running", .prompt(scope: .running)),
    ("x-choosy", "best.all", .best(scope: .all)),
    ("x-choosy", "best.running", .best(scope: .running)),
])
func schemeActions(scheme: String, action: String, mode: SchemeCommand.Mode) throws {
    for separator in ["://", ":/", ":"] {
        let command = try SchemeCommand.parse(scheme + separator + action + "/https://example.com/a%2Fb?q=one%26two&v=2#fragment").get()
        #expect(command.link.absoluteString == "https://example.com/a%2Fb?q=one%26two&v=2#fragment")
        #expect(command.mode == mode)
    }
}

@Test(arguments: [
    "https://example.com/a?one=1&two=2#fragment?three=3",
    "https://example.com/%2F?q=a%26b&v=2#part%20two",
    "https://example.com/привіт?q=世界#café",
    "mailto:hello@example.com?subject=Hello%20世界&body=a%26b#fragment",
    "mailto:?subject=Hello%20world&body=a%26b",
    "mailto:",
    "http://example.com",
    "HTTPS://example.com",
])
func schemePayloadPreservation(payload: String) throws {
    let expected = try #require(URL(string: payload))
    for scheme in ["linkway", "x-choosy"] {
        #expect(try SchemeCommand.parse("\(scheme)://open/" + payload).get().link.absoluteString == expected.absoluteString)
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: payload), URLQueryItem(name: "v", value: "1")]
        let strict = try #require(components.url)
        #expect(try SchemeCommand.parse(strict.absoluteString).get().link.absoluteString == expected.absoluteString)
    }
}

@Test(arguments: ["linkway://open/https:/example.com/a?q=1#f", "x-choosy:prompt.running/http:/example.com/a?q=1#f"])
func normalizesSingleSlash(value: String) throws {
    let command = try SchemeCommand.parse(value).get()
    #expect(command.link.absoluteString == (value.contains("https:") ? "https://example.com/a?q=1#f" : "http://example.com/a?q=1#f"))
}

@Test(arguments: [
    ("other://open/https://example.com", SchemeCommandError.unsupportedCommandScheme),
    ("linkway://unknown/https://example.com", .unknownAction),
    ("linkway://best.all/https://example.com", .unknownAction),
    ("x-choosy://prompt/https://example.com", .unknownAction),
    ("linkway://open/", .emptyLink),
    ("linkway:open", .emptyLink),
    ("linkway://open?url=", .emptyLink),
    ("linkway://open?url=https%3A%2F%2Fexample.com&v=2", .unsupportedVersion),
    ("linkway://open?url=https%3A%2F%2Fexample.com&v=", .unsupportedVersion),
    ("linkway://open?url=https%3A%2F%2Fexample.com&v", .unsupportedVersion),
    ("linkway://open?url=https%3A%2F%2Fexample.com&v=1&v=2", .unsupportedVersion),
    ("linkway://open?url=https%3A%2F%2Fexample.com#fragment", .invalidQuery),
    ("linkway://open?v=1", .invalidQuery),
    ("linkway://open?url=a&url=b", .invalidQuery),
    ("linkway://open/not-a-url", .invalidLink),
    ("linkway://open/https://", .invalidLink),
    ("linkway://open/file:///tmp/a.html", .unsupportedLinkScheme),
    ("linkway://open/javascript:alert(1)", .unsupportedLinkScheme),
    ("linkway://open/linkway://open/https://example.com", .unsupportedLinkScheme),
    ("x-choosy://open/x-choosy://open/https://example.com", .unsupportedLinkScheme),
    ("linkway://open?url=x-choosy%3A%2F%2Fopen%2Fhttps%3A%2F%2Fexample.com", .unsupportedLinkScheme),
])
func rejectsSchemeCommand(value: String, error: SchemeCommandError) throws {
    #expect(SchemeCommand.parse(value) == .failure(error))
}

@Test func strictVariantsAndVersion() throws {
    for prefix in ["LINKWAY://open", "linkway:/open", "linkway:open", "x-choosy://open"] {
        #expect(try SchemeCommand.parse(prefix + "?v=1&url=https%3A%2F%2Fexample.com%2Fa%253Fb%3Fq%3D%2526%23f").get().link.absoluteString == "https://example.com/a%3Fb?q=%26#f")
    }
}

private func scopedDestination(_ bundleID: String, profile: String? = nil, kind: DestinationKind = .browser) -> Destination {
    Destination(id: DestinationID(bundleID: bundleID, profileKey: profile), kind: kind,
                appName: bundleID, profileName: profile, appURL: URL(fileURLWithPath: "/unused"), supportsPrivateWindow: false)
}

@Test func runningScopePreservesPickerOrderAndProfiles() {
    let destinations = [scopedDestination("com.example.closed"), scopedDestination("com.example.running", profile: "work"),
                        scopedDestination("com.example.running", profile: "personal"), scopedDestination("com.example.other")]
    #expect(SchemeCommand.Scope.running.filter(destinations, runningBundleIDs: ["COM.EXAMPLE.RUNNING"]) == Array(destinations[1...2]))
    #expect(SchemeCommand.Scope.running.filter(destinations, runningBundleIDs: []) == destinations)
    #expect(SchemeCommand.Scope.running.filter(destinations, runningBundleIDs: ["unrelated"]) == destinations)
    #expect(SchemeCommand.Scope.all.filter(destinations, runningBundleIDs: ["com.example.running"]) == destinations)
    #expect(SchemeCommand.Scope.running.filter([], runningBundleIDs: ["com.example.running"]).isEmpty)
    let mail = [scopedDestination("com.example.mail", kind: .mailClient)]
    #expect(SchemeCommand.Scope.running.filter(mail, runningBundleIDs: ["com.example.running"]) == mail)
}

@Test func schemeModesRespectRulesAndPickerOrder() throws {
    let original = try #require(URL(string: "https://example.com/?utm_source=test"))
    let processed = try #require(URL(string: "https://example.com/"))
    let first = DestinationID(bundleID: "com.example.first")
    let second = DestinationID(bundleID: "com.example.second")
    let fallback = DestinationID(bundleID: "com.example.fallback")
    let rule = Rule(name: "match", condition: .hostExact("example.com"), action: .open(second, privateWindow: true))
    let noMatch = Rule(name: "miss", condition: .hostExact("other.com"), action: .open(second, privateWindow: false))
    for mode: SchemeCommand.Mode in [.route, .prompt(scope: .all), .prompt(scope: .running), .best(scope: .all), .best(scope: .running)] {
        for forced in [false, true] {
            let link = IncomingLink(url: original, receivedAt: Date(), senderBundleID: nil, forcePicker: forced, mode: mode)
            let engine = RoutingEngine(rules: [rule], fallback: .open(fallback))
            let decision = engine.decide(link, processedURL: processed, availableDestinations: [first, second, fallback], pickerOrder: [first, second])
            switch mode {
            case .prompt:
                #expect(decision == .showPicker(.forcedByUser))
            case .route where forced:
                #expect(decision == .showPicker(.forcedByUser))
            default:
                #expect(decision == .launch(LaunchRequest(url: processed, destination: second, privateWindow: true), matchedRule: rule.id))
            }
            if case .best = mode {
                let misses = RoutingEngine(rules: [noMatch], fallback: .open(fallback))
                #expect(misses.decide(link, processedURL: processed, availableDestinations: [first, second, fallback], pickerOrder: [first, second]) ==
                    .launch(LaunchRequest(url: processed, destination: first), matchedRule: nil))
                #expect(misses.decide(link, processedURL: processed, availableDestinations: [second], pickerOrder: [first, second]) ==
                    .launch(LaunchRequest(url: processed, destination: second), matchedRule: nil))
                #expect(misses.decide(link, processedURL: processed, availableDestinations: [], pickerOrder: []) == .showPicker(.noMatch))
                #expect(engine.decide(link, processedURL: processed, availableDestinations: [first], pickerOrder: [first]) ==
                    .showPicker(.ruleTargetUnavailable(rule.id, second)))
                let pickerRule = Rule(name: "ask", condition: .hostExact("example.com"), action: .showPicker)
                #expect(RoutingEngine(rules: [pickerRule], fallback: .open(fallback))
                    .decide(link, processedURL: processed, availableDestinations: [first], pickerOrder: [first]) ==
                    .showPicker(.ruleRequestsPicker(pickerRule.id)))
            }
        }
    }
}

@Test func bestRunningUsesScopedOrderWithoutLimitingRuleTargets() throws {
    let destinations = [scopedDestination("com.example.closed"), scopedDestination("com.example.running")]
    let input = IncomingLink(url: try #require(URL(string: "mailto:a@example.com?subject=Hello")), receivedAt: Date(),
                             senderBundleID: nil, forcePicker: false, mode: .best(scope: .running))
    for running: Set<String> in [[], ["com.example.running"]] {
        let order = input.mode.scope.filter(destinations, runningBundleIDs: running).map(\.id)
        let expected = running.isEmpty ? destinations[0].id : destinations[1].id
        let engine = RoutingEngine(rules: [], fallback: .showPicker)
        #expect(engine.decide(input, processedURL: input.url, availableDestinations: Set(destinations.map(\.id)), pickerOrder: order) ==
            .launch(LaunchRequest(url: input.url, destination: expected), matchedRule: nil))
        let rule = Rule(name: "mail", condition: .mailRecipientDomain("example.com"), action: .open(destinations[0].id, privateWindow: false))
        #expect(RoutingEngine(rules: [rule], fallback: .showPicker)
            .decide(input, processedURL: input.url, availableDestinations: Set(destinations.map(\.id)), pickerOrder: order) ==
            .launch(LaunchRequest(url: input.url, destination: destinations[0].id), matchedRule: rule.id))
    }
}

@Test func rawUnicodeLinkMatchesDirectParsing() throws {
    let command = try SchemeCommand.parse("linkway://open/https://bücher.de/é?q=✓#片").get()
    #expect(command.link.absoluteString == "https://xn--bcher-kva.de/%C3%A9?q=%E2%9C%93#%E7%89%87")
    let link = IncomingLink(url: command.link, receivedAt: Date(), senderBundleID: nil, forcePicker: false)
    #expect(URLMatcher.matches(.hostExact("xn--bcher-kva.de"), link: link, url: command.link))
}

@Test func strictPromptSharesOpenValidationAndVersionRules() throws {
    for action in ["open", "prompt"] {
        for (query, error): (String, SchemeCommandError) in [
            ("url=", .emptyLink),
            ("url=https%3A%2F%2Fexample.com&v=2", .unsupportedVersion),
            ("url=https%3A%2F%2Fexample.com&v=", .unsupportedVersion),
            ("url=https%3A%2F%2Fexample.com&v", .unsupportedVersion),
            ("url=https%3A%2F%2Fexample.com&v=1&v=2", .unsupportedVersion),
            ("url=https%3A%2F%2Fexample.com#fragment", .invalidQuery),
            ("v=1", .invalidQuery),
            ("url=a&url=b", .invalidQuery),
            ("url=javascript%3Aalert(1)", .unsupportedLinkScheme),
            ("url=linkway%3A%2F%2Fopen%2Fhttps%3A%2F%2Fexample.com", .unsupportedLinkScheme),
            ("url=https%3A%2F%2F", .invalidLink),
        ] {
            #expect(SchemeCommand.parse("linkway://\(action)?\(query)") == .failure(error))
        }
        for prefix in ["LINKWAY://", "linkway:/", "linkway:"] {
            for version in ["", "&v=1", "&v=1&v=1"] {
                let command = try SchemeCommand.parse(prefix + action + "?url=https%3A%2F%2Fexample.com%2Fa%253Fb%3Fq%3D%2526%23f" + version).get()
                #expect(command.link.absoluteString == "https://example.com/a%3Fb?q=%26#f")
                #expect(command.mode == (action == "open" ? .route : .prompt(scope: .all)))
            }
        }
    }
}
