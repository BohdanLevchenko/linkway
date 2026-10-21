import Foundation
import Testing
@testable import LinkwayCore

private struct StubDNS: HostAddressResolving {
    var values: [String] = ["93.184.216.34"]
    func addresses(for host: String) async throws -> [String] { values }
}
private actor StubFetcher: RedirectFetching {
    struct Call: Sendable, Equatable { let url: URL; let method: RedirectMethod }
    var calls: [Call] = []
    let responses: [RedirectResponse]
    let delay: Duration?
    init(_ responses: [RedirectResponse], delay: Duration? = nil) { self.responses = responses; self.delay = delay }
    func fetch(_ url: URL, method: RedirectMethod, timeout: TimeInterval) async throws -> RedirectResponse {
        calls.append(.init(url: url, method: method))
        if let delay { try await Task.sleep(for: delay) }
        guard responses.indices.contains(calls.count - 1) else { throw ResolveFailure.network }
        return responses[calls.count - 1]
    }
}

private let shortURL = URL(string: "https://bit.ly/a")!
private func resolver(_ fetcher: StubFetcher, dns: StubDNS = .init()) -> ShortLinkResolver {
    .init(settings: .init(), fetcher: fetcher, addresses: dns)
}
@Test func shortChainStopsBeforeDestination() async {
    let fetcher = StubFetcher([.init(status: 302, location: "https://t.co/b"),
                               .init(status: 301, location: "https://example.com/final?utm_x=y")])
    let result = await resolver(fetcher).resolve(shortURL)
    #expect(result.outcome == .expanded)
    #expect(result.url.absoluteString == "https://example.com/final?utm_x=y")
    #expect(result.hops.count == 2)
    #expect(await fetcher.calls.map(\.url) == [shortURL, URL(string: "https://t.co/b")!])
}
@Test func relativeRedirectAndGetFallback() async {
    let fetcher = StubFetcher([.init(status: 405), .init(status: 302, location: "/b"),
                               .init(status: 302), .init(status: 307, location: "//example.com/c")])
    let result = await resolver(fetcher).resolve(shortURL)
    #expect(result.outcome == .expanded)
    #expect(result.url.absoluteString == "https://example.com/c")
    #expect(await fetcher.calls.map(\.method) == [.head, .get, .head, .get])
    #expect(await fetcher.calls.map(\.url.path) == ["/a", "/a", "/b", "/b"])
}
@Test func redirectLoops() async {
    let fetcher = StubFetcher([.init(status: 302, location: "/a")])
    #expect(await resolver(fetcher).resolve(shortURL).outcome == .failed(.loop))
}
@Test func hopLimit() async {
    let fetcher = StubFetcher((1...6).map { .init(status: 302, location: "/\($0)") })
    let result = await resolver(fetcher).resolve(shortURL)
    #expect(result.outcome == .failed(.hopLimit))
    #expect(result.hops.count == 5)
    #expect(await fetcher.calls.count == 5)
}
@Test func finalDestinationAtFifthHop() async {
    let fetcher = StubFetcher((1...4).map { .init(status: 302, location: "/\($0)") }
        + [.init(status: 308, location: "https://example.com/")])
    #expect(await resolver(fetcher).resolve(shortURL).outcome == .expanded)
}
@Test(arguments: [
    "http://127.0.0.1/a", "http://10.0.0.1/", "http://172.16.0.1/", "http://192.168.1.1/",
    "http://169.254.169.254/", "http://100.64.0.1/", "http://224.0.0.1/", "http://0.0.0.0/",
    "http://[::1]/", "http://[::]/", "http://[fe80::1]/", "http://[fc00::1]/", "http://[ff02::1]/",
    "http://[::ffff:192.168.0.1]/", "http://localhost/", "http://a.local/", "http://a.internal/",
    "http://a.lan/", "http://single/", "https://user:pass@example.com/", "file:///tmp/a", "mailto:a@example.com"
])
func unsafeRedirect(location: String) async {
    let fetcher = StubFetcher([.init(status: 302, location: location)])
    #expect(await resolver(fetcher).resolve(shortURL).outcome == .failed(.unsafeAddress))
    #expect(await fetcher.calls.count == 1)
}
@Test func dnsRejectsAnyPrivateAddress() async {
    let fetcher = StubFetcher([.init(status: 302, location: "https://example.com/")])
    #expect(await resolver(fetcher, dns: .init(values: ["93.184.216.34", "10.0.0.1"])).resolve(shortURL).outcome == .failed(.unsafeAddress))
    #expect(await fetcher.calls.isEmpty)
}
private actor PerHostDNS: HostAddressResolving {
    func addresses(for host: String) async throws -> [String] {
        host == "bit.ly" ? ["93.184.216.34"] : ["127.0.0.1"]
    }
}
@Test func revalidatesDestinationDNS() async {
    let fetcher = StubFetcher([.init(status: 302, location: "https://example.com/")])
    let resolver = ShortLinkResolver(settings: .init(), fetcher: fetcher, addresses: PerHostDNS())
    #expect(await resolver.resolve(shortURL).outcome == .failed(.unsafeAddress))
    #expect(await fetcher.calls.count == 1)
}
@Test func nonShortLinkNeverRequests() async {
    let fetcher = StubFetcher([])
    for text in ["https://example.com/", "https://youtu.be/a", "https://evilbit.ly/a", "file://bit.ly/a"] {
        #expect(await resolver(fetcher).resolve(URL(string: text)!).outcome == .notShortLink)
    }
    #expect(await fetcher.calls.isEmpty)
}
@Test func subdomainShortLink() async {
    let fetcher = StubFetcher([.init(status: 303, location: "https://example.com/")])
    #expect(await resolver(fetcher).resolve(URL(string: "https://sub.bit.ly/a")!).outcome == .expanded)
}
@Test func failedResponseReturnsLastURL() async {
    let fetcher = StubFetcher([.init(status: 302, location: "/b"), .init(status: 200), .init(status: 200)])
    let result = await resolver(fetcher).resolve(shortURL)
    #expect(result.url.absoluteString == "https://bit.ly/b")
    #expect(result.outcome == .failed(.missingLocation))
}
@Test func resolverCancellation() async {
    let fetcher = StubFetcher([], delay: .seconds(10))
    let task = Task { await resolver(fetcher).resolve(shortURL) }
    task.cancel()
    #expect(await task.value.outcome == .cancelled)
}
@Test func resolverRequestTimeout() async {
    let fetcher = StubFetcher([], delay: .seconds(10))
    let clock = ContinuousClock()
    let start = clock.now
    #expect(await resolver(fetcher).resolve(shortURL).outcome == .failed(.timeout))
    #expect(start.duration(to: clock.now) < .seconds(4))
}
@Test(arguments: ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111", "::ffff:8.8.8.8"])
func publicAddresses(address: String) { #expect(PublicAddress.isPublic(address) == true) }

@Test func totalBudgetCoversAllHops() async {
    let fetcher = StubFetcher([.init(status: 302, location: "/b"), .init(status: 302, location: "https://example.com/")],
                              delay: .milliseconds(2200))
    let start = ContinuousClock.now
    let result = await resolver(fetcher).resolve(shortURL)
    #expect(result.outcome == .failed(.timeout))
    #expect(result.hops.count == 1)
    #expect(start.duration(to: .now) < .seconds(4.8))
}
private struct SlowDNS: HostAddressResolving {
    func addresses(for host: String) async throws -> [String] {
        try await Task.sleep(for: .seconds(20))
        return ["93.184.216.34"]
    }
}
@Test func cancellationDuringDNS() async throws {
    let fetcher = StubFetcher([])
    let resolver = ShortLinkResolver(settings: .init(), fetcher: fetcher, addresses: SlowDNS())
    let task = Task { await resolver.resolve(shortURL) }
    try await Task.sleep(for: .milliseconds(10))
    task.cancel()
    #expect(await task.value.outcome == .cancelled)
    #expect(await fetcher.calls.isEmpty)
}
@Test(arguments: [301, 302, 303, 307, 308])
func supportedRedirectStatuses(status: Int) async {
    let fetcher = StubFetcher([.init(status: status, location: "https://example.com/")])
    #expect(await resolver(fetcher).resolve(shortURL).outcome == .expanded)
}
@Test func head501RetriesOnce() async {
    let fetcher = StubFetcher([.init(status: 501), .init(status: 501)])
    #expect(await resolver(fetcher).resolve(shortURL).outcome == .failed(.missingLocation))
    #expect(await fetcher.calls.map(\.method) == [.head, .get])
}
private struct MixedDestinationDNS: HostAddressResolving {
    func addresses(for host: String) async throws -> [String] {
        host == "bit.ly" ? ["93.184.216.34"] : ["93.184.216.34", "fd00::1"]
    }
}
@Test func mixedDestinationDNSRejected() async {
    let fetcher = StubFetcher([.init(status: 302, location: "https://example.com/")])
    let resolver = ShortLinkResolver(settings: .init(), fetcher: fetcher, addresses: MixedDestinationDNS())
    #expect(await resolver.resolve(shortURL).outcome == .failed(.unsafeAddress))
    #expect(await fetcher.calls.count == 1)
}

@Test func initialPrivateShortenerRejected() async {
    let fetcher = StubFetcher([])
    let resolver = ShortLinkResolver(settings: .init(shortenerHosts: ["127.0.0.1"]),
                                     fetcher: fetcher, addresses: StubDNS())
    #expect(await resolver.resolve(URL(string: "https://127.0.0.1/")!).outcome == .failed(.unsafeAddress))
    #expect(await fetcher.calls.isEmpty)
}
@Test func emptyDNSResponseFailsClosed() async {
    let fetcher = StubFetcher([])
    #expect(await resolver(fetcher, dns: .init(values: [])).resolve(shortURL).outcome == .failed(.unsafeAddress))
    #expect(await fetcher.calls.isEmpty)
}

private actor ChangingDNS: HostAddressResolving {
    private var calls = 0
    let rebound: [String]
    init(rebound: [String]) { self.rebound = rebound }
    func addresses(for host: String) async throws -> [String] {
        calls += 1
        return calls == 1 ? ["93.184.216.34", "8.8.8.8"] : rebound
    }
}
private actor PinnedFetcher: RedirectFetching {
    private(set) var connected: [String] = []
    func fetch(_ url: URL, method: RedirectMethod, timeout: TimeInterval) async throws -> RedirectResponse {
        Issue.record("resolver must pass a validated address")
        throw ResolveFailure.network
    }
    func fetch(_ url: URL, address: String, method: RedirectMethod, timeout: TimeInterval) async throws -> RedirectResponse {
        connected.append(address)
        return method == .head ? .init(status: 405) : .init(status: 302, location: "https://example.com/")
    }
}
@Test func fallbackRevalidatesAndPinsEachConnection() async {
    let fetcher = PinnedFetcher()
    let resolver = ShortLinkResolver(settings: .init(), fetcher: fetcher, addresses: ChangingDNS(rebound: ["1.1.1.1"]))
    #expect(await resolver.resolve(shortURL).outcome == .expanded)
    #expect(await fetcher.connected == ["93.184.216.34", "1.1.1.1"])
}
@Test func rebindingToPrivateAddressBlocksFallback() async {
    let fetcher = PinnedFetcher()
    let resolver = ShortLinkResolver(settings: .init(), fetcher: fetcher, addresses: ChangingDNS(rebound: ["8.8.8.8", "127.0.0.1"]))
    #expect(await resolver.resolve(shortURL).outcome == .failed(.unsafeAddress))
    #expect(await fetcher.connected == ["93.184.216.34"])
}
