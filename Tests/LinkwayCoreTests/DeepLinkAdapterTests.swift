import Foundation
import Testing
@testable import LinkwayCore

private struct DeepLinkGolden: Sendable {
    let adapter: DeepLinkAdapter.ID
    let web: String
    let app: String
}

private let deepLinkGoldens: [DeepLinkGolden] = [
    .init(adapter: .figma, web: "https://www.figma.com/file/KEY/Name?node-id=1-2", app: "figma://file/KEY/Name?node-id=1-2"),
    .init(adapter: .linear, web: "https://linear.app/work/issue/ENG-1/title?q=a%2Bb#details", app: "linear://work/issue/ENG-1/title?q=a%2Bb#details"),
    .init(adapter: .notion, web: "https://www.notion.so/Some-Page-abc?v=123#section", app: "notion://www.notion.so/Some-Page-abc?v=123#section"),
    .init(adapter: .slack, web: "https://team.slack.com/archives/C123/p1234567890?thread_ts=1.2&cid=C123", app: "https://team.slack.com/archives/C123/p1234567890?thread_ts=1.2&cid=C123"),
    .init(adapter: .zoom, web: "https://company.zoom.us/j/123456789?pwd=a%2B%26+b&from=calendar", app: "zoommtg://zoom.us/join?confno=123456789&pwd=a%2B%26+b"),
    .init(adapter: .teams, web: "https://teams.microsoft.com/l/meetup-join/19%3Ameeting?context=%7B%22Tid%22%3A%22t%22%7D", app: "msteams:/l/meetup-join/19%3Ameeting?context=%7B%22Tid%22%3A%22t%22%7D"),
    .init(adapter: .spotify, web: "https://open.spotify.com/intl-uk/track/ABC123?si=tracking", app: "spotify:track:ABC123"),
    .init(adapter: .discord, web: "https://discord.com/channels/123/456/789?jump=1#message", app: "discord://discord.com/channels/123/456/789?jump=1#message"),
]

@Test(arguments: deepLinkGoldens)
private func deepLinkGoldenURLs(golden: DeepLinkGolden) throws {
    let adapter = try #require(DeepLinkCatalog.adapters.first { $0.id == golden.adapter })
    #expect(adapter.appURL(for: try #require(URL(string: golden.web)))?.absoluteString == golden.app)
}

@Test func supportedFigmaAndSpotifyGrammars() throws {
    let figma = try #require(DeepLinkCatalog.adapter(for: "com.figma.Desktop"))
    for type in ["file", "design", "board", "proto", "slides"] {
        #expect(figma.appURL(for: URL(string: "https://www.figma.com/\(type)/KEY/Some%20Name?node-id=1%3A2#part")!)?.absoluteString
                == "figma://\(type)/KEY/Some%20Name?node-id=1%3A2#part")
    }
    let spotify = try #require(DeepLinkCatalog.adapter(for: "com.spotify.client"))
    for type in ["track", "album", "artist", "playlist", "show", "episode"] {
        for locale in ["", "intl-de/"] {
            #expect(spotify.appURL(for: URL(string: "https://open.spotify.com/\(locale)\(type)/abc123?q=drop#drop")!)?.absoluteString
                    == "spotify:\(type):abc123")
        }
    }
}

@Test func deepLinksRejectUnsupportedPathsAndHosts() throws {
    let invalid: [DeepLinkAdapter.ID: [String]] = [
        .figma: ["https://www.figma.com/community/file/KEY", "https://www.figma.com/design", "https://figma.com/file/KEY"],
        .linear: ["https://linear.app/", "https://linear.app/work", "https://help.linear.app/work/issue", "https://linear.app/work@other/issue/ENG-1", "https://linear.app/work%2Fother/issue/ENG-1"],
        .notion: ["https://www.notion.so/", "https://workspace.notion.site/slug", "https://notion.so/page"],
        .slack: ["https://team.slack.com/messages/C123", "https://slack.com/archives/C123", "https://team.slack.com/archives/C123/pno", "https://team.slack.com/archives/C123/extra/path"],
        .zoom: ["https://zoom.us/s/123", "https://zoom.us/j/abc", "https://zoom.us/j/123?pwd=a&pwd=b"],
        .teams: ["https://teams.microsoft.com/v2/", "https://teams.microsoft.com/l/", "https://teams.live.com/l/chat/123"],
        .spotify: ["https://open.spotify.com/user/abc", "https://open.spotify.com/track/abc/extra", "https://open.spotify.com/intl-too-long/track/abc"],
        .discord: ["https://discord.com/invite/abc", "https://discord.com/channels/123", "https://discord.com/channels/a/b"],
    ]
    for adapter in DeepLinkCatalog.adapters {
        for input in try #require(invalid[adapter.id]) {
            #expect(adapter.appURL(for: URL(string: input)!) == nil, "\(adapter.id): \(input)")
        }
        let golden = try #require(deepLinkGoldens.first { $0.adapter == adapter.id })
        let url = try #require(URL(string: golden.web))
        var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.host = try #require(url.host) + ".evil.example"
        #expect(adapter.appURL(for: try #require(components.url)) == nil)
        components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.scheme = "http"
        #expect(adapter.appURL(for: try #require(components.url)) == nil)
        components.scheme = "https"
        components.user = "user"
        #expect(adapter.appURL(for: try #require(components.url)) == nil)
    }
}

@Test(arguments: deepLinkGoldens)
private func trackingIsCleanedBeforeAdapters(golden: DeepLinkGolden) throws {
    let adapter = try #require(DeepLinkCatalog.adapters.first { $0.id == golden.adapter })
    let url = try #require(URL(string: golden.web))
    var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "utm_source", value: "mail")]
    let clean = TrackingCleaner(settings: .init()).clean(try #require(components.url))
    #expect(clean.removedParameters.contains("utm_source"))
    #expect(adapter.appURL(for: clean.url)?.absoluteString.contains("utm_source") == false)
    #expect(adapter.appURL(for: clean.url) != nil)
}

@Test func adapterKindsAndBundleAliases() throws {
    #expect(DeepLinkCatalog.adapter(for: "com.tinyspeck.slackmacgap")?.kind == .openWebURLInApp)
    #expect(DeepLinkCatalog.adapters.filter { $0.kind == .rewrite }.count == 7)
    #expect(DeepLinkCatalog.adapter(for: "com.microsoft.teams2") == DeepLinkCatalog.adapter(for: "com.microsoft.teams"))
    #expect(DeepLinkCatalog.adapter(for: "unknown.app") == nil)
    let slack = try #require(DeepLinkCatalog.adapter(for: "com.tinyspeck.slackmacgap"))
    let url = URL(string: "https://team.slack.com/archives/C123")!
    #expect(slack.appURL(for: url) == url)
    #expect(DeepLinkCatalog.adapter(for: "us.zoom.xos")?.appURL(for: URL(string: "https://zoom.us/j/123")!)?.absoluteString
            == "zoommtg://zoom.us/join?confno=123")
}

@Test func oldConfigurationDefaultsToEnabledAdapters() throws {
    let encoded = try JSONEncoder().encode(LinkwayConfiguration.default)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "disabledAppAdapters")
    let old = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(LinkwayConfiguration.self, from: old).disabledAppAdapters.isEmpty)
    var config = LinkwayConfiguration.default
    config.disabledAppAdapters = ["figma", "slack"]
    #expect(try JSONDecoder().decode(LinkwayConfiguration.self, from: JSONEncoder().encode(config)) == config)
}

@Test func appEligibilityControlsRulesAndFallbacks() throws {
    let figma = Destination(id: DestinationID(bundleID: "com.figma.Desktop"), kind: .app, appName: "Figma",
                            profileName: nil, appURL: URL(filePath: "/fake/Figma.app"), supportsPrivateWindow: false)
    let browser = Destination(id: DestinationID(bundleID: "browser"), kind: .browser, appName: "Browser",
                              profileName: nil, appURL: URL(filePath: "/fake/Browser.app"), supportsPrivateWindow: false)
    let url = URL(string: "https://www.figma.com/design/KEY/Name?node-id=1-2")!
    let other = URL(string: "https://www.figma.com/community")!
    let destinations = [browser, figma]
    #expect(DeepLinkCatalog.matchingApps(in: destinations, for: url, disabledAdapters: []) == [figma])
    #expect(DeepLinkCatalog.matchingApps(in: destinations, for: url, disabledAdapters: ["figma"]).isEmpty)
    #expect(DeepLinkCatalog.matchingApps(in: destinations, for: other, disabledAdapters: []).isEmpty)
    #expect(DeepLinkCatalog.matchingApps(in: [browser], for: url, disabledAdapters: []).isEmpty)
    let rule = Rule(name: "Figma", condition: .hostExact("www.figma.com"), action: .open(figma.id, privateWindow: false))
    for (input, disabled, canLaunch) in [(url, [String](), true), (other, [], false), (url, ["figma"], false)] {
        let available = Set(destinations.filter {
            DeepLinkCatalog.supports($0, url: input, disabledAdapters: disabled)
        }.map(\.id))
        #expect(available.contains(browser.id))
        let link = IncomingLink(url: input, receivedAt: Date(), senderBundleID: nil, forcePicker: false)
        let decision = RoutingEngine(rules: [rule], fallback: .showPicker)
            .decide(link, processedURL: input, availableDestinations: available)
        if canLaunch {
            #expect(decision == .launch(.init(url: input, destination: figma.id), matchedRule: rule.id))
        } else {
            #expect(decision == .showPicker(.ruleTargetUnavailable(rule.id, figma.id)))
            #expect(RoutingEngine(rules: [], fallback: .open(figma.id))
                .decide(link, processedURL: input, availableDestinations: available) == .showPicker(.noMatch))
        }
    }
}

@Test func deepLinksRejectAmbiguousPathsBeforeAdapterGrammar() throws {
    let invalidSegments = [".", "..", "%2e", "%2E", "%2e%2e", "%2E%2e", ".%2E", "%2e.",
                           "name%2fother", "name%2Fother", "name%5cother", "name%5Cother", "name\\other"]
    for (bundleID, base) in [("com.figma.Desktop", "https://www.figma.com/file/KEY/"),
                              ("com.microsoft.teams2", "https://teams.microsoft.com/l/")] {
        let adapter = try #require(DeepLinkCatalog.adapter(for: bundleID))
        for segment in invalidSegments {
            for suffix in ["", "/settings"] {
                let url = try #require(URL(string: base + segment + suffix))
                #expect(adapter.appURL(for: url) == nil, "\(url)")
                let app = Destination(id: .init(bundleID: bundleID), kind: .app, appName: "App",
                                      profileName: nil, appURL: URL(filePath: "/fake/App.app"), supportsPrivateWindow: false)
                #expect(DeepLinkCatalog.matchingApps(in: [app], for: url, disabledAdapters: []).isEmpty)
            }
        }
        #expect(adapter.appURL(for: try #require(URL(string: base + "../../settings"))) == nil)
        #expect(adapter.appURL(for: try #require(URL(string: base + "Design.v2"))) != nil)
        #expect(adapter.appURL(for: try #require(URL(string: base + "Design%2Ev2"))) != nil)
    }
}
