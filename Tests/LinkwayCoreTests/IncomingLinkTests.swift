import Foundation
import LinkwayCore
import Testing

@Test(arguments: [
    ("http://example.com", LinkKind.web),
    ("https://example.com/path?q=hello#fragment", .web),
    ("HTTPS://example.com", .web),
    ("mailto:hello@example.com?subject=Hello", .mail),
    ("file:///tmp/example.html", .localFile),
    ("linkway://open", .custom),
    ("other://example", .custom),
    ("relative/path", .custom),
])
func classifiesLinkKind(value: String, expected: LinkKind) throws {
    let url = try #require(URL(string: value))
    let link = IncomingLink(
        url: url, receivedAt: Date(), senderBundleID: nil, forcePicker: false
    )
    #expect(link.kind == expected)
}
