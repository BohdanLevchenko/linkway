import Foundation
import Testing
@testable import LinkwayCore

@Test func mailtoPreservesFieldsAndDecodesOnce() throws {
    let url = try #require(URL(string: "MAILTO:first+tag@example.com,second@example.com?TO=third%40example.com&to=fourth@example.com,fifth@example.com&CC=cc@example.com&cc=other@example.com&BCC=b@example.com&bcc=c@example.com&SUBJECT=Hello%20%E4%B8%96%E7%95%8C%20%26%20%3D%20+%20%2520&BODY=line%201%0D%0Aline%202%26x%3Dy+z&X-Ignored=secret"))
    let message = try #require(MailtoMessage(url: url))
    #expect(message.originalURL == url)
    #expect(message.to == ["first+tag@example.com", "second@example.com", "third@example.com", "fourth@example.com", "fifth@example.com"])
    #expect(message.cc == ["cc@example.com", "other@example.com"])
    #expect(message.bcc == ["b@example.com", "c@example.com"])
    #expect(message.subject == "Hello 世界 & = + %20")
    #expect(message.body == "line 1\r\nline 2&x=y+z")
}

@Test func mailtoUsesSharedQuoteAwareSplitter() throws {
    let message = try #require(MailtoMessage(url: URL(string: "mailto:%22Last,%20First%22%20%3Cme@example.com%3E,%22a,b%22@example.net?to=%E7%94%A8%E6%88%B7@example.org")!))
    #expect(message.to == ["\"Last, First\" <me@example.com>", "\"a,b\"@example.net", "用户@example.org"])
    #expect(URLMatcher.recipientDomains(URLComponents(url: message.originalURL, resolvingAgainstBaseURL: false)) == ["example.com", "example.net", "example.org"])
}

@Test(arguments: ["mailto:", "mailto:?to=&TO&cc=,,&bcc=&subject=&body=&other=x", "mailto:,,?to=%20,%20"])
func mailtoEmptyRecipients(raw: String) throws {
    let message = try #require(MailtoMessage(url: URL(string: raw)!))
    #expect(message.to.isEmpty && message.cc.isEmpty && message.bcc.isEmpty)
}

@Test func mailtoSingletonsAndNoRecipient() throws {
    let message = try #require(MailtoMessage(url: URL(string: "mailto:?subject=&SUBJECT=later&body=first&BODY=later")!))
    #expect(message.subject == "")
    #expect(message.body == "first")
    #expect(MailtoMessage(url: URL(string: "https://example.com")!) == nil)
    let noRecipient = try #require(MailtoMessage(url: URL(string: "mailto:?subject=Hello")!))
    #expect(WebmailProvider.yahoo.composeURL(for: noRecipient).absoluteString == "https://compose.mail.yahoo.com/?subject=Hello")
}

@Test func webmailGoldenURLs() throws {
    let message = try #require(MailtoMessage(url: URL(string: "mailto:a+x@example.com,b@example.com?cc=c@example.com&bcc=d@example.com&subject=Hi%20%E4%B8%96%E7%95%8C%26%3D%2B%23%3F&body=A%0D%0AB")!))
    let recipients = "to=a%2Bx%40example.com%2Cb%40example.com&cc=c%40example.com&bcc=d%40example.com"
    let text = "Hi%20%E4%B8%96%E7%95%8C%26%3D%2B%23%3F&body=A%0D%0AB"
    let fixtures: [(WebmailProvider, String)] = [
        (.gmail, "https://mail.google.com/mail/?view=cm&fs=1&" + recipients + "&su=" + text + "&authuser=me%2Bwork%40example.com"),
        (.outlookPersonal, "https://outlook.live.com/mail/0/deeplink/compose?" + recipients + "&subject=" + text),
        (.outlookWork, "https://outlook.office.com/mail/deeplink/compose?" + recipients + "&subject=" + text),
        (.yahoo, "https://compose.mail.yahoo.com/?" + recipients + "&subject=" + text),
        (.fastmail, "https://app.fastmail.com/action/compose/?mailto=mailto%3Aa%2Bx%40example.com%2Cb%40example.com%3Fcc%3Dc%40example.com%26bcc%3Dd%40example.com%26subject%3DHi%2520%25E4%25B8%2596%25E7%2595%258C%2526%253D%252B%2523%253F%26body%3DA%250D%250AB"),
        (.proton, "https://mail.proton.me/u/0/inbox#mailto=mailto%3Aa%2Bx%40example.com%2Cb%40example.com%3Fcc%3Dc%40example.com%26bcc%3Dd%40example.com%26subject%3DHi%2520%25E4%25B8%2596%25E7%2595%258C%2526%253D%252B%2523%253F%26body%3DA%250D%250AB"),
    ]
    for (provider, expected) in fixtures {
        #expect(provider.composeURL(for: message, account: "me+work@example.com").absoluteString == expected)
    }
}

@Test func webmailOmitsEmptyFields() throws {
    let message = try #require(MailtoMessage(url: URL(string: "mailto:?to=&cc=&bcc=&subject=&body=")!))
    #expect(WebmailProvider.gmail.composeURL(for: message).absoluteString == "https://mail.google.com/mail/?view=cm&fs=1")
    #expect(WebmailProvider.gmail.composeURL(for: message, account: "").absoluteString == "https://mail.google.com/mail/?view=cm&fs=1")
    #expect(WebmailProvider.outlookPersonal.composeURL(for: message).absoluteString == "https://outlook.live.com/mail/0/deeplink/compose")
    #expect(WebmailProvider.outlookWork.composeURL(for: message).absoluteString == "https://outlook.office.com/mail/deeplink/compose")
    #expect(WebmailProvider.yahoo.composeURL(for: message).absoluteString == "https://compose.mail.yahoo.com/")
}

@Test func webmailConfigurationRoundTripAndLegacyDefault() throws {
    let browser = DestinationID(bundleID: "com.example.browser", profileKey: "Work")
    let accounts = WebmailProvider.allCases.map { WebmailAccount(provider: $0, displayName: $0.name, account: "me@example.com", browser: browser) }
    let config = LinkwayConfiguration(webmailAccounts: accounts)
    let data = try JSONEncoder().encode(config)
    #expect(try ConfigurationStore.migrate(from: data) == config)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["webmailAccounts"] != nil)
    #expect(!String(decoding: data, as: UTF8.self).contains("\"_0\""))
    var legacy = json
    legacy.removeValue(forKey: "webmailAccounts")
    #expect(try ConfigurationStore.migrate(from: JSONSerialization.data(withJSONObject: legacy)).webmailAccounts.isEmpty)
}

@Test func webmailDestinationAndLaunchRequest() throws {
    let browser = Destination(id: DestinationID(bundleID: "com.example.browser", profileKey: "Work"), kind: .browser,
                              appName: "Browser", profileName: "Work", appURL: URL(filePath: "/fake/Browser.app"),
                              supportsPrivateWindow: true, avatarURL: URL(filePath: "/fake/avatar.png"))
    let account = WebmailAccount(provider: .gmail, displayName: "Work mail", account: "me@example.com", browser: browser.id)
    let destination = try #require(account.destination(target: browser))
    #expect(destination.id == DestinationID(bundleID: "linkway.webmail", profileKey: account.id.uuidString))
    #expect(destination.kind == .mailClient && destination.appName == "Gmail" && destination.profileName == "Work mail")
    #expect(destination.appURL == browser.appURL && destination.avatarURL == browser.avatarURL)
    #expect(!destination.supportsPrivateWindow)
    let request = try #require(account.launchRequest(for: URL(string: "mailto:a@example.com")!))
    #expect(request.destination == browser.id && !request.privateWindow)
    #expect(request.url.absoluteString == "https://mail.google.com/mail/?view=cm&fs=1&to=a%40example.com&authuser=me%40example.com")
    #expect(account.launchRequest(for: URL(string: "https://example.com")!) == nil)
    let wrong = WebmailAccount(provider: .gmail, displayName: "Missing", browser: DestinationID(bundleID: "missing"))
    #expect(wrong.destination(target: browser) == nil)
    let link = IncomingLink(url: URL(string: "mailto:a@example.com")!, receivedAt: Date(), senderBundleID: nil, forcePicker: false)
    let fallback = FallbackPolicies(mail: .open(destination.id))
    let engine = RoutingEngine(rules: [], fallbacks: fallback)
    #expect(engine.decide(link, processedURL: link.url, availableDestinations: [destination.id]) == .launch(LaunchRequest(url: link.url, destination: destination.id), matchedRule: nil))
    #expect(engine.decide(link, processedURL: link.url, availableDestinations: []) == .showPicker(.noMatch))
}
