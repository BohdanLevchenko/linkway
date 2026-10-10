import Foundation

public enum RuleSuggestion {
    public static func suggestedRule(for url: URL, destination: DestinationID, privateWindow: Bool) -> Rule {
        var host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host.flatMap(URLMatcher.normalizedHost) ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return Rule(name: host, condition: .hostIncludingSubdomains(host), action: .open(destination, privateWindow: privateWindow))
    }
}
