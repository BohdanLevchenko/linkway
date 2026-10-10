import Foundation
import Testing
@testable import LinkwayCore

private struct MatchCase: Sendable {
    let condition: RuleCondition
    let url: String
    let sender: String?
    let expected: Bool

    init(_ condition: RuleCondition, _ url: String, _ expected: Bool, sender: String? = nil) {
        self.condition = condition
        self.url = url
        self.sender = sender
        self.expected = expected
    }
}

@Test(arguments: [
    MatchCase(.hostIncludingSubdomains("example.com"), "https://example.com", true),
    MatchCase(.hostIncludingSubdomains("example.com"), "https://a.b.example.com", true),
    MatchCase(.hostIncludingSubdomains("example.com"), "https://badexample.com", false),
    MatchCase(.hostExact("example.com"), "https://a.example.com", false),
    MatchCase(.hostExact("EXAMPLE.COM."), "https://ExAmPlE.com./a", true),
    MatchCase(.hostExact("example.com"), "https://example.com:8443", true),
    MatchCase(.hostExact("example.com:8443"), "https://example.com:8443", true),
    MatchCase(.hostExact("example.com:8443"), "https://example.com", false),
    MatchCase(.hostExact("example.com:443"), "https://example.com", true),
    MatchCase(.hostExact("example.com:80"), "http://example.com", true),
    MatchCase(.hostExact("example.com:80"), "https://example.com", false),
    MatchCase(.hostExact("example.com:443"), "https://example.com:443", true),
    MatchCase(.hostIncludingSubdomains("example.com:443"), "https://a.example.com", true),
    MatchCase(.hostIncludingSubdomains("example.com:443"), "https://a.example.com:8443", false),
    MatchCase(.hostExact("bücher.de"), "https://xn--bcher-kva.de", true),
    MatchCase(.hostExact("xn--bcher-kva.de"), "https://bücher.de", true),
    MatchCase(.hostExact("例え.テスト"), "https://xn--r8jz45g.xn--zckzah", true),
    MatchCase(.hostExact("xn--r8jz45g.xn--zckzah"), "https://例え.テスト", true),
    MatchCase(.hostExact("example.com/path"), "https://example.com", false),
    MatchCase(.urlPrefix("HTTPS://EXAMPLE.COM:443/~user"), "https://example.com/%7euser/a", true),
    MatchCase(.urlPrefix("http://example.com:80/A"), "HTTP://EXAMPLE.COM/A/b", true),
    MatchCase(.urlPrefix("https://example.com/A"), "https://example.com/a", false),
    MatchCase(.urlPrefix("https://example.com/a%2fb"), "https://example.com/a%2Fb", true),
    MatchCase(.urlPrefix("https://example.com/a/b"), "https://example.com/a%2Fb", false),
    MatchCase(.urlPrefix("https://bücher.de/"), "https://xn--bcher-kva.de/a", true),
    MatchCase(.urlPrefix("https://example.com"), "https://example.com:8443", true),
    MatchCase(.pathPattern(host: "example.com", pattern: "/a/*"), "https://example.com/a/b?q=/c#d", true),
    MatchCase(.pathPattern(host: nil, pattern: "/a/*"), "https://example.com/a/b/c", false),
    MatchCase(.pathPattern(host: nil, pattern: "/a/**"), "https://example.com/a/b/c", true),
    MatchCase(.pathPattern(host: nil, pattern: "/a/*"), "https://example.com/a/", true),
    MatchCase(.pathPattern(host: nil, pattern: "/~user/*"), "https://example.com/%7Euser/a", true),
    MatchCase(.pathPattern(host: nil, pattern: "/a%2fb"), "https://example.com/a%2Fb", true),
    MatchCase(.pathPattern(host: "other.com", pattern: "/**"), "https://example.com/a", false),
    MatchCase(.pathPattern(host: "example.com:80", pattern: "/**"), "http://example.com/a", true),
    MatchCase(.pathPattern(host: nil, pattern: "/A/*"), "https://example.com/a/b", false),
    MatchCase(.sourceApp(bundleID: "COM.Example.App"), "https://example.com", true, sender: "com.example.app"),
    MatchCase(.sourceApp(bundleID: "com.example.app"), "https://example.com", false),
    MatchCase(.sourceApp(bundleID: "com.example.app"), "mailto:a@example.com", true, sender: "com.example.app"),
    MatchCase(.mailRecipientDomain("EXAMPLE.COM"), "mailto:a@other.com,b@Example.com", true),
    MatchCase(.mailRecipientDomain("example.com"), "mailto:a@other.com?to=b%40example.com,c%40another.com", true),
    MatchCase(.mailRecipientDomain("example.com"), "mailto:a%40other.com?TO=b%40EXAMPLE.COM&to=c%40another.com", true),
    MatchCase(.mailRecipientDomain("example.com"), "mailto:a%40example.com", true),
    MatchCase(.mailRecipientDomain("example.com"), "mailto:a@badexample.com?cc=b@example.com", false),
    MatchCase(.mailRecipientDomain("example.com"), "mailto:a@other.com?subject=b@example.com", false),
    MatchCase(.mailRecipientDomain("example.com"), "https://example.com", false),
    MatchCase(.hostExact("example.com"), "mailto:a@example.com", false),
    MatchCase(.urlPrefix("mailto:"), "mailto:a@example.com", false),
    MatchCase(.pathPattern(host: nil, pattern: "**"), "mailto:a@example.com", false),
    MatchCase(.hostExact("example.com"), "custom://example.com/a", false),
    MatchCase(.hostIncludingSubdomains("example.com"), "custom://example.com/a", false),
    MatchCase(.pathPattern(host: nil, pattern: "**"), "file:///tmp/a.html", false),
    MatchCase(.urlPrefix("file:///tmp/"), "file:///tmp/a.html", true),
    MatchCase(.urlPrefix("CUSTOM://EXAMPLE.COM/a"), "custom://example.com/a/b", true),
    MatchCase(.sourceApp(bundleID: "com.example.app"), "file:///tmp/a.html", true, sender: "com.example.app"),
])
private func matchingSemantics(_ entry: MatchCase) throws {
    let url = try #require(URL(string: entry.url))
    let link = IncomingLink(url: url, receivedAt: Date(), senderBundleID: entry.sender, forcePicker: false)
    #expect(URLMatcher.matches(entry.condition, link: link, url: url) == entry.expected)
}

@Test(arguments: [
    ("bücher", "xn--bcher-kva"),
    ("例え", "xn--r8jz45g"),
    ("テスト", "xn--zckzah"),
    ("mañana", "xn--maana-pta"),
    ("日本語", "xn--wgv71a119e"),
    ("abc", "abc"),
])
func punycodeVectors(input: String, expected: String) {
    #expect(Punycode.encode(input) == expected)
}

@Test func fullIDNNormalization() {
    #expect(URLMatcher.normalizedHost("bücher.de") == "xn--bcher-kva.de")
    #expect(URLMatcher.normalizedHost("例え.テスト") == "xn--r8jz45g.xn--zckzah")
    #expect(URLMatcher.normalizedHost("BÜCHER.DE.") == "xn--bcher-kva.de")
}

@Test func percentNormalization() {
    #expect(URLMatcher.normalizePercent("/%41%7e%2f%3f%25%ff") == "/A~%2F%3F%25%FF")
    #expect(URLMatcher.normalizePercent("/日本語/%7e") == "/%E6%97%A5%E6%9C%AC%E8%AA%9E/~")
}


@Test(arguments: [
    MatchCase(.pathPattern(host: nil, pattern: "/日本語/*"), "https://example.com/%E6%97%A5%E6%9C%AC%E8%AA%9E/a", true),
    MatchCase(.pathPattern(host: nil, pattern: "/%e6%97%a5%e6%9c%ac%e8%aa%9e/*"), "https://example.com/日本語/a", true),
    MatchCase(.pathPattern(host: nil, pattern: "/café/*"), "https://example.com/cafe%CC%81/a", true),
    MatchCase(.pathPattern(host: nil, pattern: "/cafe\u{301}/*"), "https://example.com/caf%C3%A9/a", true),
    MatchCase(.pathPattern(host: nil, pattern: "/a/*"), "https://example.com/a%2Fb/c", false),
    MatchCase(.pathPattern(host: nil, pattern: "/a/*"), "https://example.com/a/b%2Fc", true),
    MatchCase(.pathPattern(host: nil, pattern: "/a%2F*"), "https://example.com/a/b", false),
    MatchCase(.pathPattern(host: nil, pattern: "/%2A"), "https://example.com/%2a", true),
    MatchCase(.pathPattern(host: nil, pattern: "/%2A"), "https://example.com/anything", false),
    MatchCase(.urlPrefix("https://example.com/日本語?q=café"), "https://example.com/%E6%97%A5%E6%9C%AC%E8%AA%9E?q=cafe%CC%81", true),
    MatchCase(.urlPrefix("https://example.com/cafe%CC%81?q=%E6%97%A5"), "https://example.com/café?q=日", true),
    MatchCase(.urlPrefix("https://example.com/cafe\u{301}?q=e\u{301}"), "https://example.com/caf%C3%A9?q=%C3%A9", true),
    MatchCase(.urlPrefix("https://example.com/a?q=x/y"), "https://example.com/a?q=x%2Fy", false),
])
private func URLMatcherUnicodeAndBoundaries(_ entry: MatchCase) throws {
    try matchingSemantics(entry)
}

@Test(arguments: [
    MatchCase(.mailRecipientDomain("evil.com"), "mailto:%22x%40evil.com%2Cy%22@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:%22x%40evil.com%2Cy%22@example.org", true),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:Name%20%3Calice@example.org%3E", true),
    MatchCase(.mailRecipientDomain("evil.com"), "mailto:%22name%40evil.com%2C%20x%22%20%3Ca@example.org%3E", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:%22name%2C%20x%22%20%3Ca@example.org%3E", true),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:%22x%5C%22%2Cy%22@example.org", true),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:%22x%5C%5C%22@example.org", true),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:a@first.org,b@second.org?to=c@third.org&to=%20Name%20%3Cd@example.org%3E%20,e@last.org", true),
    MatchCase(.mailRecipientDomain("second.org"), "mailto:a@first.org,b@second.org?to=c@third.org&to=d@example.org", true),
    MatchCase(.mailRecipientDomain("third.org"), "mailto:a@first.org,b@second.org?to=c@third.org&to=d@example.org", true),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:%22unclosed@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:Name%20%3Ca@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:a@example.org%3E", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:Name%20%3Ca@example.org%3Egarbage", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:Name%20%3C%3Ca@example.org%3E%3E", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:bad@display%20%3Ca@example.org%3E", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:Group:%20%3Ca@example.org%3E", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:a@other.org%20%3Cb@example.org%3E%20%3Cc@elsewhere.org%3E", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:%22x%5C%22@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:a%20b@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:%22a%22garbage@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:a@@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:a@example.org?to=%22x%40evil.com%2Cy%22@elsewhere.org", true),
    MatchCase(.mailRecipientDomain("evil.com"), "mailto:a@example.org?to=%22x%40evil.com%2Cy%22@elsewhere.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:a@example.org%0Ab@example.org", false),
    MatchCase(.mailRecipientDomain("example.org"), "mailto:a@?to=bad&to=b@example.org", true),
])
private func URLMatcherRecipientParsing(_ entry: MatchCase) throws {
    try matchingSemantics(entry)
}

@Test func URLMatcherCanonicalUnicodeEscapes() {
    #expect(URLMatcher.normalizePercent("/cafe\u{301}/e%CC%81/%c3%a9") == "/caf%C3%A9/%C3%A9/%C3%A9")
    #expect(URLMatcher.normalizePercent("/%2f%2a*%252F") == "/%2F%2A*%252F")
}
