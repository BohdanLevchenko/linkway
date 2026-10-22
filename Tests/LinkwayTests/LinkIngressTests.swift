import Foundation
import LinkwayCore
import Testing
@testable import Linkway

@MainActor @Test func schemeIngressPreservesQueuedModesAndDropsSenders() throws {
    let ingress = LinkIngress()
    ingress.forcePickerModifier = nil
    ingress.receive(try #require(URL(string: "linkway://open/https://example.com/a?q=1#f")), senderBundleID: "com.example.sender")
    ingress.receive(try #require(URL(string: "x-choosy://prompt.running/mailto:a@example.com?subject=Hello")), senderBundleID: "com.example.sender")
    ingress.receive(try #require(URL(string: "x-choosy://best.all/https://example.com")))
    ingress.receive(try #require(URL(string: "https://ordinary.example")), senderBundleID: "com.example.sender")
    var links: [IncomingLink] = []
    ingress.onLink = { links.append($0) }
    #expect(links.count == 4)
    #expect(links.map(\.mode) == [.route, .prompt(scope: .running), .best(scope: .all), .route])
    #expect(links.map(\.senderBundleID) == [nil, nil, nil, "com.example.sender"])
    #expect(links[0].url.absoluteString == "https://example.com/a?q=1#f")
    #expect(links[1].url.absoluteString == "mailto:a@example.com?subject=Hello")
    #expect(links.allSatisfy { !$0.forcePicker })
}

@MainActor @Test func schemeIngressRejectsWithoutBlockingLaterLinks() throws {
    let ingress = LinkIngress()
    ingress.forcePickerModifier = nil
    var links: [IncomingLink] = []
    ingress.onLink = { links.append($0) }
    for value in ["linkway://unknown/https://example.com", "x-choosy://open/file:///tmp/a", "linkway://open/linkway://open/https://example.com"] {
        ingress.receive(try #require(URL(string: value)))
    }
    #expect(links.isEmpty)
    ingress.receive(try #require(URL(string: "linkway:open/https:/example.com")))
    #expect(links.count == 1)
    #expect(links.first?.url.absoluteString == "https://example.com")
}
