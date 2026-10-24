import Foundation

/// Compose adapter compatibility (provider sign-in is required):
///
/// | Provider | Status |
/// | --- | --- |
/// | Gmail | Verified by docs |
/// | Outlook Personal / Work | Verified by docs |
/// | Yahoo | Verified by docs |
/// | Fastmail | Best effort |
/// | Proton Mail | Best effort |
public enum WebmailProvider: String, Codable, Sendable, Hashable, CaseIterable {
    case gmail, outlookPersonal, outlookWork, yahoo, fastmail, proton

    public var name: String {
        switch self {
        case .gmail: "Gmail"
        case .outlookPersonal: "Outlook Personal"
        case .outlookWork: "Outlook Work"
        case .yahoo: "Yahoo Mail"
        case .fastmail: "Fastmail"
        case .proton: "Proton Mail"
        }
    }

    private static let queryAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public func composeURL(for message: MailtoMessage, account: String? = nil) -> URL {
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed)!
        }
        if self == .fastmail {
            return URL(string: "https://app.fastmail.com/action/compose/?mailto=" + encode(message.originalURL.absoluteString))!
        }
        if self == .proton {
            return URL(string: "https://mail.proton.me/u/0/inbox#mailto=" + encode(message.originalURL.absoluteString))!
        }
        let base: String
        var fields: [(String, String)] = []
        switch self {
        case .gmail:
            base = "https://mail.google.com/mail/"
            fields = [("view", "cm"), ("fs", "1")]
        case .outlookPersonal: base = "https://outlook.live.com/mail/0/deeplink/compose"
        case .outlookWork: base = "https://outlook.office.com/mail/deeplink/compose"
        case .yahoo: base = "https://compose.mail.yahoo.com/"
        case .fastmail, .proton: preconditionFailure("Handled above")
        }
        fields += [("to", message.to.joined(separator: ",")), ("cc", message.cc.joined(separator: ",")),
                   ("bcc", message.bcc.joined(separator: ",")), (self == .gmail ? "su" : "subject", message.subject ?? ""),
                   ("body", message.body ?? "")]
        if self == .gmail, let account { fields.append(("authuser", account)) }
        let query = fields.filter { !$0.1.isEmpty }.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: base + (query.isEmpty ? "" : "?" + query))!
    }
}
