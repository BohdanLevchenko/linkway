import Foundation

public struct CleanResult: Sendable, Hashable {
    public let url: URL
    public let removedParameters: [String]
    public let unwrappedFrom: URL?
    public init(url: URL, removedParameters: [String] = [], unwrappedFrom: URL? = nil) {
        self.url = url
        self.removedParameters = removedParameters
        self.unwrappedFrom = unwrappedFrom
    }
}

public struct TrackingCleaner: Sendable {
    private let settings: URLProcessingSettings
    public init(settings: URLProcessingSettings) { self.settings = settings }

    private struct ParameterRule: Sendable {
        let hosts: [String]
        let patterns: [String]
        var value: String? = nil
    }
    private static let global = """
    utm_* fbclid gclid dclid gbraid wbraid gclsrc msclkid twclid ttclid li_fat_id yclid mc_cid mc_eid _hsenc _hsmi __hssc __hstc __hsfp hsCtaTracking mkt_tok oly_anon_id oly_enc_id vero_id vero_conv _openstat igshid rb_clickid s_cid wickedid irclickid _kx ml_subscriber ml_subscriber_hash ref_src ref_url
    """.split(separator: " ").map(String.init)
    private static let amazonDomains = ["com", "co.uk", "de", "fr", "it", "es", "ca", "com.au", "co.jp", "in", "com.br", "com.mx", "nl", "se", "pl", "com.be", "com.tr", "ae", "sa", "sg", "eg", "co.za", "ie", "cn", "com.cn"]
    private static let scoped: [ParameterRule] = [
        .init(hosts: ["youtube.com", "youtu.be", "open.spotify.com"], patterns: ["si"]),
        .init(hosts: ["instagram.com"], patterns: ["igsh"]),
        .init(hosts: ["youtube.com", "youtu.be"], patterns: ["feature"], value: "share"),
        .init(hosts: ["youtube.com"], patterns: ["pp"]),
        .init(hosts: ["x.com", "twitter.com"], patterns: ["s", "t"]),
        .init(hosts: amazonDomains.map { "amazon." + $0 }, patterns: ["ref", "ref_", "pf_rd_*", "pd_rd_*", "_encoding", "psc", "content-id"]),
    ]
    private struct Wrapper: Sendable {
        let hosts: [String]
        let path: String?
        let parameters: [String]
        var exactHosts = false
    }
    private static let googleDomains: [String] = [
        "google.com", "google.co.uk", "google.de", "google.fr", "google.ca", "google.com.au",
        "google.co.in", "google.co.jp", "google.com.br", "google.es", "google.it", "google.nl",
        "google.pl", "google.com.ua", "google.ru", "google.com.mx", "google.co.kr",
    ]
    private static let wrappers: [Wrapper] = [
        .init(hosts: googleDomains.flatMap { [$0, "www." + $0] }, path: "/url", parameters: ["q", "url"], exactHosts: true),
        .init(hosts: ["l.facebook.com", "lm.facebook.com", "l.messenger.com"], path: "/l.php", parameters: ["u"]),
        .init(hosts: ["l.instagram.com"], path: nil, parameters: ["u"]),
        .init(hosts: ["safelinks.protection.outlook.com", "out.reddit.com"], path: nil, parameters: ["url"]),
        .init(hosts: ["www.youtube.com"], path: "/redirect", parameters: ["q"]),
    ]
    private static let maximumUnwraps = 3

    private func matches(_ name: String, patterns: [String]) -> Bool {
        patterns.contains {
            let pattern = $0.lowercased()
            return pattern.hasSuffix("*") ? name.hasPrefix(String(pattern.dropLast())) : name == pattern
        }
    }
    private func protected(_ components: URLComponents) -> Bool {
        let names = Set((components.queryItems ?? []).map { $0.name.lowercased() })
        let exact: Set<String> = ["signature", "sig", "x-amz-signature", "x-goog-signature", "hmac", "token", "access_token", "id_token"]
        return !names.isDisjoint(with: exact)
            || (names.contains("code") && names.contains("state"))
            || names.contains { $0.hasPrefix("saml") || $0.hasPrefix("oauth") }
            || ["/oauth", "/saml", "/sso", "/authorize", "/login/callback"].contains { components.path.lowercased().contains($0) }
    }
    private func skipped(_ components: URLComponents) -> Bool {
        protected(components) || settings.cleanerExcludedHosts.contains { hostMatches(components.host ?? "", suffix: $0) }
    }
    private func wrappedURL(_ components: URLComponents) -> URL? {
        let host = (components.host ?? "").lowercased()
        for wrapper in Self.wrappers where wrapper.hosts.contains(where: {
            wrapper.exactHosts ? host == $0 : hostMatches(host, suffix: $0)
        })
            && (wrapper.path == nil || wrapper.path == components.path) {
            for parameter in wrapper.parameters {
                for item in components.queryItems ?? [] where item.name.lowercased() == parameter {
                    if let value = item.value, let url = URL(string: value),
                       ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                        return url
                    }
                }
            }
        }
        return nil
    }
    public func clean(_ url: URL) -> CleanResult {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !skipped(components) else { return .init(url: url) }
        var current = url
        if settings.unwrapRedirectLinks {
            for _ in 0..<Self.maximumUnwraps {
                guard let inner = wrappedURL(components),
                      let next = URLComponents(url: inner, resolvingAgainstBaseURL: false) else { break }
                current = inner
                components = next
                if skipped(components) { break }
            }
        }
        let unwrapped = current == url ? nil : url
        guard settings.cleanTracking, !skipped(components), let query = components.percentEncodedQuery else {
            return .init(url: current, unwrappedFrom: unwrapped)
        }
        var removed: [String] = []
        let kept = query.components(separatedBy: "&").filter { item in
            let raw = String(item.prefix { $0 != "=" })
            let decoded = raw.removingPercentEncoding ?? raw
            let name = decoded.lowercased()
            if matches(name, patterns: settings.keptParameters) { return true }
            let value = item.firstIndex(of: "=").map { String(item[item.index(after: $0)...]).removingPercentEncoding ?? "" }
            let strip = matches(name, patterns: Self.global + settings.extraTrackingParameters)
                || Self.scoped.contains { rule in
                    rule.hosts.contains { hostMatches(components.host ?? "", suffix: $0) }
                        && matches(name, patterns: rule.patterns) && (rule.value == nil || value == rule.value)
                }
            if strip { removed.append(decoded) }
            return !strip
        }
        guard !removed.isEmpty else { return .init(url: current, unwrappedFrom: unwrapped) }
        // Splice only the raw query so Foundation cannot normalize other URL bytes.
        let text = current.absoluteString
        guard let question = text.firstIndex(of: "?") else { return .init(url: current, unwrappedFrom: unwrapped) }
        let fragment = text[question...].firstIndex(of: "#").map { String(text[$0...]) } ?? ""
        let newQuery = kept.joined(separator: "&")
        let result = String(text[..<question]) + (newQuery.isEmpty ? "" : "?" + newQuery) + fragment
        return .init(url: URL(string: result) ?? current, removedParameters: removed, unwrappedFrom: unwrapped)
    }
}
