import Foundation
import Testing
@testable import LinkwayCore

private struct CleaningFixture: Sendable {
    let input: String
    let expected: String
}
private let cleaningFixtures: [CleaningFixture] = [
    .init(input: "https://example.com/a?q=hello&id=1&v=2&page=3&utm_source=mail#part",
          expected: "https://example.com/a?q=hello&id=1&v=2&page=3#part"),
    .init(input: "https://example.com/a?b=2&utm_source=x&a=%26%2f&a=3&bare&empty=#%2F",
          expected: "https://example.com/a?b=2&a=%26%2f&a=3&bare&empty=#%2F"),
    .init(input: "https://example.com/a?%75TM_Source=x&FBCLID=y", expected: "https://example.com/a"),
    .init(input: "https://example.com/%2f?q=a%26b&utm_x=x#frag", expected: "https://example.com/%2f?q=a%26b#frag"),
    .init(input: "https://example.com/?utm_x=x#frag", expected: "https://example.com/#frag"),
    .init(input: "https://example.com/#fragment", expected: "https://example.com/#fragment"),
    .init(input: "https://例え.jp/a?utm_source=x&q=日本", expected: "https://例え.jp/a?q=日本"),
    .init(input: "https://bucket.s3.amazonaws.com/key?X-Amz-Signature=abc&utm_source=x",
          expected: "https://bucket.s3.amazonaws.com/key?X-Amz-Signature=abc&utm_source=x"),
    .init(input: "https://example.com/login/callback?utm_x=x", expected: "https://example.com/login/callback?utm_x=x"),
    .init(input: "https://example.com/cb?code=c&state=s&utm_x=x", expected: "https://example.com/cb?code=c&state=s&utm_x=x"),
    .init(input: "https://example.com/cb?code=c&utm_x=x", expected: "https://example.com/cb?code=c"),
    .init(input: "https://example.com/?si=x&pp=y&s=z&t=1&igsh=2&feature=share&ref=home",
          expected: "https://example.com/?si=x&pp=y&s=z&t=1&igsh=2&feature=share&ref=home"),
    .init(input: "https://www.youtube.com/watch?v=abc&si=x&feature=share&pp=y",
          expected: "https://www.youtube.com/watch?v=abc"),
    .init(input: "https://youtu.be/abc?si=x&feature=share", expected: "https://youtu.be/abc"),
    .init(input: "https://youtube.com/watch?v=abc&feature=embed", expected: "https://youtube.com/watch?v=abc&feature=embed"),
    .init(input: "https://open.spotify.com/track/abc?si=x", expected: "https://open.spotify.com/track/abc"),
    .init(input: "https://spotify.com/?si=x", expected: "https://spotify.com/?si=x"),
    .init(input: "https://instagram.com/a?igsh=x&id=1", expected: "https://instagram.com/a?id=1"),
    .init(input: "https://mobile.twitter.com/a?s=1&t=2&id=3", expected: "https://mobile.twitter.com/a?id=3"),
    .init(input: "https://x.com/a?s=1&t=2", expected: "https://x.com/a"),
    .init(input: "https://www.amazon.co.uk/a?ref=x&ref_=x&pf_rd_x=y&pd_rd_y=z&_encoding=u&psc=1&content-id=x&tag=ok",
          expected: "https://www.amazon.co.uk/a?tag=ok"),
    .init(input: "https://amazon.de/a?ref=x&id=3", expected: "https://amazon.de/a?id=3"),
    .init(input: "https://amazon.com.evil.test/?ref=x", expected: "https://amazon.com.evil.test/?ref=x"),
    .init(input: "https://notyoutube.com/?si=x", expected: "https://notyoutube.com/?si=x"),
    .init(input: "https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fa%3Futm_x%3Dx%26id%3D2",
          expected: "https://example.com/a?id=2"),
    .init(input: "https://www.google.de/url?url=https%3A%2F%2Fexample.com%2F", expected: "https://example.com/"),
    .init(input: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2F", expected: "https://example.com/"),
    .init(input: "https://lm.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2F", expected: "https://example.com/"),
    .init(input: "https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2F", expected: "https://example.com/"),
    .init(input: "https://a.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2F", expected: "https://example.com/"),
    .init(input: "https://out.reddit.com/?url=https%3A%2F%2Fexample.com%2F", expected: "https://example.com/"),
    .init(input: "https://www.youtube.com/redirect?q=https%3A%2F%2Fexample.com%2F", expected: "https://example.com/"),
    .init(input: "https://l.messenger.com/l.php?u=https%3A%2F%2Fexample.com%2F", expected: "https://example.com/"),
    .init(input: "https://google.com/url?q=javascript%3Aalert(1)", expected: "https://google.com/url?q=javascript%3Aalert(1)"),
    .init(input: "https://google.com/url?q=%2Frelative", expected: "https://google.com/url?q=%2Frelative"),
    .init(input: "mailto:a@example.com?utm_source=x", expected: "mailto:a@example.com?utm_source=x"),
    .init(input: "file:///tmp/a?utm_source=x", expected: "file:///tmp/a?utm_source=x"),
    .init(input: "myapp://a?utm_source=x", expected: "myapp://a?utm_source=x"),
]

@Test(arguments: cleaningFixtures)
private func goldenCleaning(_ fixture: CleaningFixture) throws {
    let input = try #require(URL(string: fixture.input))
    let result = TrackingCleaner(settings: .init()).clean(input)
    #expect(result.url.absoluteString == URL(string: fixture.expected)?.absoluteString)
}

@Test func cleanerSettingsAndRemovedNames() throws {
    let url = try #require(URL(string: "https://sub.example.com/?UTM_Source=x&custom_x=y&custom_x=z&id=4"))
    var settings = URLProcessingSettings(keptParameters: ["utm_source"])
    settings.extraTrackingParameters = ["custom_*"]
    let result = TrackingCleaner(settings: settings).clean(url)
    #expect(result.url.absoluteString == "https://sub.example.com/?UTM_Source=x&id=4")
    #expect(result.removedParameters == ["custom_x", "custom_x"])
    settings.cleanerExcludedHosts = ["example.com"]
    #expect(TrackingCleaner(settings: settings).clean(url).url == url)
    settings.cleanerExcludedHosts = ["notexample.com"]
    settings.cleanTracking = false
    #expect(TrackingCleaner(settings: settings).clean(url).url == url)
}

@Test(arguments: ["signature", "SIG", "x-goog-signature", "hmac", "TOKEN", "access_token", "id_token", "SAMLRequest", "oauth_nonce"])
func protectedParameter(name: String) throws {
    let url = try #require(URL(string: "https://example.com/?\(name)=x&utm_source=y"))
    #expect(TrackingCleaner(settings: .init()).clean(url).url == url)
}

@Test(arguments: ["/oauth/test", "/saml/test", "/sso", "/authorize", "/login/callback"])
func protectedPath(path: String) throws {
    let url = try #require(URL(string: "https://example.com\(path)?utm_x=y"))
    #expect(TrackingCleaner(settings: .init()).clean(url).url == url)
}

private func wrap(_ url: URL) -> URL {
    var components = URLComponents(string: "https://google.com/url")!
    components.queryItems = [.init(name: "q", value: url.absoluteString)]
    return components.url!
}
@Test func unwrapChainsBoundedAndConfigurable() {
    let target = URL(string: "https://example.com/?utm_x=x&id=3")!
    let chain = wrap(wrap(wrap(target)))
    let result = TrackingCleaner(settings: .init()).clean(chain)
    #expect(result.url.absoluteString == "https://example.com/?id=3")
    #expect(result.unwrappedFrom == chain)
    #expect(TrackingCleaner(settings: .init()).clean(wrap(chain)).url == wrap(target))
    #expect(TrackingCleaner(settings: .init(unwrapRedirectLinks: false)).clean(chain).url == chain)
    #expect(TrackingCleaner(settings: .init(cleanTracking: false)).clean(chain).url == target)
    let signed = URL(string: "https://example.com/?sig=x&utm_x=x")!
    #expect(TrackingCleaner(settings: .init()).clean(wrap(signed)).url == signed)
}

@Test func processingSettingsDecodeMissingFieldsAndLegacyConfiguration() throws {
    let defaults = URLProcessingSettings()
    #expect(try JSONDecoder().decode(URLProcessingSettings.self, from: Data("{}".utf8)) == defaults)
    let partial = try JSONDecoder().decode(URLProcessingSettings.self, from: Data(#"{"cleanTracking":false}"#.utf8))
    #expect(!partial.cleanTracking && partial.unwrapRedirectLinks && !partial.expandShortLinks)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(LinkwayConfiguration.default)) as? [String: Any])
    object.removeValue(forKey: "urlProcessing")
    #expect(try JSONDecoder().decode(LinkwayConfiguration.self, from: JSONSerialization.data(withJSONObject: object)).urlProcessing == defaults)
    #expect(!defaults.shortenerHosts.contains("youtu.be"))
    var config = LinkwayConfiguration.default
    config.urlProcessing = .init(cleanTracking: false, extraTrackingParameters: ["custom*"], keptParameters: ["utm_source"],
                                 cleanerExcludedHosts: ["example.com"], expandShortLinks: true, shortenerHosts: ["short.test"])
    let data = try JSONEncoder().encode(config)
    #expect(try ConfigurationStore.migrate(from: data) == config)
    #expect(!String(decoding: data, as: UTF8.self).contains("\"_0\""))
}

@Test(arguments: """
utm_source fbclid gclid dclid gbraid wbraid gclsrc msclkid twclid ttclid li_fat_id yclid mc_cid mc_eid _hsenc _hsmi __hssc __hstc __hsfp hsCtaTracking mkt_tok oly_anon_id oly_enc_id vero_id vero_conv _openstat igshid rb_clickid s_cid wickedid irclickid _kx ml_subscriber ml_subscriber_hash ref_src ref_url
""".split(separator: " ").map(String.init))
func everyGlobalParameterIsRemoved(name: String) {
    let url = URL(string: "https://example.com/?q=keep&\(name)=drop&ID=1")!
    let result = TrackingCleaner(settings: .init()).clean(url)
    #expect(result.url.absoluteString == "https://example.com/?q=keep&ID=1")
    #expect(result.removedParameters == [name])
}

@Test func rawURLPreservationAndEmptyQuery() {
    let input = URL(string: "https://EXAMPLE.com:8443/%2F%40?x=a+b&x=a%20b&utm_X=1&y=%2526&&flag#part?x=%2f")!
    let result = TrackingCleaner(settings: .init()).clean(input)
    #expect(result.url.absoluteString == "https://EXAMPLE.com:8443/%2F%40?x=a+b&x=a%20b&y=%2526&&flag#part?x=%2f")
    let empty = URL(string: "https://example.com/?")!
    #expect(TrackingCleaner(settings: .init()).clean(empty).url == empty)
}

@Test func excludedAndProtectedWrappersStayIntact() {
    let wrapper = wrap(URL(string: "https://example.com/?utm_x=x")!)
    #expect(TrackingCleaner(settings: .init(cleanerExcludedHosts: ["google.com"])).clean(wrapper).url == wrapper)
    let withSignature = URL(string: wrapper.absoluteString + "&sig=x")!
    #expect(TrackingCleaner(settings: .init()).clean(withSignature).url == withSignature)
}

@Test func keptSiteParameterWins() {
    let url = URL(string: "https://www.youtube.com/watch?v=abc&si=x&pp=y&utm_source=z")!
    let result = TrackingCleaner(settings: .init(keptParameters: ["SI", "utm_*"])).clean(url)
    #expect(result.url.absoluteString == "https://www.youtube.com/watch?v=abc&si=x&utm_source=z")
    #expect(result.removedParameters == ["pp"])
}

@Test(arguments: ["google.com", "www.google.com", "google.co.uk", "www.google.de", "google.com.ua", "www.google.co.kr"])
func explicitGoogleWrapperDomains(host: String) {
    let wrapped = URL(string: "https://\(host)/url?q=https%3A%2F%2Fexample.com%2F")!
    #expect(TrackingCleaner(settings: .init()).clean(wrapped).url.absoluteString == "https://example.com/")
}
@Test(arguments: ["www.google.example.com", "evil.google.com", "www.google.com.example.org", "google.example"])
func untrustedGoogleLookalikesStayWrapped(host: String) {
    let wrapped = URL(string: "https://\(host)/url?q=https%3A%2F%2Fexample.com%2F")!
    #expect(TrackingCleaner(settings: .init()).clean(wrapped).url == wrapped)
}
