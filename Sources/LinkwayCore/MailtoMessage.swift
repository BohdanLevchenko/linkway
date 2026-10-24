import Foundation

public struct MailtoMessage: Sendable, Hashable {
    public let originalURL: URL
    public let to: [String]
    public let cc: [String]
    public let bcc: [String]
    public let subject: String?
    public let body: String?

    /// Repeated recipient fields accumulate. For repeated subject/body fields the first wins;
    /// RFC 6068 leaves repeated singleton fields undefined. Unknown headers are ignored.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "mailto" else { return nil }
        originalURL = url
        var to = Self.recipients(components.percentEncodedPath.removingPercentEncoding ?? "")
        var cc: [String] = [], bcc: [String] = []
        var subject: String?, body: String?
        for item in components.queryItems ?? [] {
            let value = item.value ?? ""
            switch item.name.lowercased() {
            case "to": to += Self.recipients(value)
            case "cc": cc += Self.recipients(value)
            case "bcc": bcc += Self.recipients(value)
            case "subject": if subject == nil { subject = value }
            case "body": if body == nil { body = value }
            default: break
            }
        }
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }

    private static func recipients(_ value: String) -> [String] {
        URLMatcher.splitAddressList(value).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
