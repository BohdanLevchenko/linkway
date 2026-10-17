import Foundation

public enum URLMatcher {
    public static func matches(_ condition: RuleCondition, link: IncomingLink, url: URL) -> Bool {
        evaluate(condition, link: link, url: url).matched
    }

    static func evaluate(_ condition: RuleCondition, link: IncomingLink, url: URL) -> (matched: Bool, reason: String) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let scheme = components?.scheme?.lowercased()
        let isWeb = link.kind == .web && (scheme == "http" || scheme == "https")
        switch condition {
        case .hostExact(let value):
            /// Exact web host uses case-insensitive ACE names, ignores a trailing dot, and honors explicit ports.
            let matched = isWeb && hostMatches(value, components: components, subdomains: false)
            return (matched, "host \(components?.host ?? "(none)") \(matched ? "is" : "is not") \(value)")
        case .hostIncludingSubdomains(let value):
            /// Web subdomains match only at a dot boundary; host and port normalization is identical to exact matching.
            let matched = isWeb && hostMatches(value, components: components, subdomains: true)
            return (matched, "host \(components?.host ?? "(none)") \(matched ? "is" : "is not") \(value) or a subdomain")
        case .urlPrefix(let prefix):
            /// Non-mail URLs compare literal prefixes after scheme/host, default-port, and unreserved percent normalization.
            let normalized = normalizedURL(url)
            let candidate = URL(string: prefix).flatMap(normalizedURL)
            let matched = link.kind != .mail && scheme != "mailto" && candidate != nil
                && normalized.map { $0.hasPrefix(candidate ?? "") } == true
            return (matched, matched ? "URL has prefix \(prefix)" : "URL does not have prefix \(prefix)")
        case .pathPattern(let host, let pattern):
            /// Web paths exclude query/fragment; a literal * in a pattern is a wildcard.
            /// * stays within a segment, ** crosses slashes, and %2A matches an encoded literal star.
            let path = normalizePercent(components?.percentEncodedPath ?? "")
            let matched = isWeb && (host.map { hostMatches($0, components: components, subdomains: false) } ?? true)
                && glob(pattern: normalizePercent(pattern), path: path)
            return (matched, "path \(path) \(matched ? "matches" : "does not match") \(pattern)")
        case .sourceApp(let bundleID):
            /// Sender bundle identifiers compare case-insensitively for every link kind; an unknown sender never matches.
            let matched = link.senderBundleID.map { $0.caseInsensitiveCompare(bundleID) == .orderedSame } ?? false
            return (matched, "sender \(link.senderBundleID ?? "(unknown)") \(matched ? "matches" : "does not match") \(bundleID)")
        case .mailRecipientDomain(let domain):
            /// Mail-only matching examines quote-aware path and repeated to-query recipients after one percent decode.
            let expected = normalizedHost(domain)
            let domains = recipientDomains(components)
            let matched = link.kind == .mail && scheme == "mailto" && expected != nil
                && domains.contains { normalizedHost($0) == expected }
            return (matched, matched ? "a to recipient has domain \(domain)" : "no to recipient has domain \(domain)")
        }
    }

    static func normalizedHost(_ value: String) -> String? {
        // URLComponents handles URL host syntax; the encoder also handles hosts Foundation leaves as Unicode.
        guard let components = URLComponents(string: "https://\(value)"),
              let host = components.host, components.user == nil, components.password == nil,
              components.port == nil, components.percentEncodedPath.isEmpty,
              components.query == nil, components.fragment == nil else { return nil }
        var lowered = host.precomposedStringWithCanonicalMapping.lowercased()
        if lowered.hasSuffix(".") { lowered.removeLast() }
        guard !lowered.isEmpty else { return nil }
        if lowered.hasPrefix("[") && lowered.hasSuffix("]") { return lowered }
        let labels = lowered.split(separator: ".", omittingEmptySubsequences: false)
        var encoded: [String] = []
        for label in labels {
            guard !label.isEmpty, let ace = Punycode.encode(String(label)) else { return nil }
            encoded.append(ace)
        }
        return encoded.joined(separator: ".")
    }

    private static func hostMatches(_ value: String, components: URLComponents?, subdomains: Bool) -> Bool {
        guard let rule = URLComponents(string: "https://\(value)"), rule.user == nil, rule.password == nil,
              rule.percentEncodedPath.isEmpty, rule.query == nil, rule.fragment == nil,
              let ruleHost = rule.host.flatMap(normalizedHost),
              let actualHost = components?.host.flatMap(normalizedHost) else { return false }
        guard actualHost == ruleHost || (subdomains && actualHost.hasSuffix(".\(ruleHost)")) else { return false }
        guard let port = rule.port else { return true }
        let defaultPort = components?.scheme?.lowercased() == "https" ? 443 : 80
        return (components?.port ?? defaultPort) == port
    }

    private static func normalizedURL(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        components.scheme = scheme
        if let host = components.host, !host.isEmpty {
            guard let normalized = normalizedHost(host) else { return nil }
            components.host = normalized
        }
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        components.percentEncodedPath = normalizePercent(components.percentEncodedPath)
        components.percentEncodedQuery = components.percentEncodedQuery.map(normalizePercent)
        components.percentEncodedFragment = components.percentEncodedFragment.map(normalizePercent)
        return components.string
    }

    /// Canonical NFC UTF-8 escapes, decoding only unreserved ASCII and Unicode.
    /// Reserved escapes (especially %2F) remain encoded, preserving path boundaries.
    static func normalizePercent(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var result = ""
        var literal: [UInt8] = []
        func flushLiteral() {
            let normalized = String(bytes: literal, encoding: .utf8)?.precomposedStringWithCanonicalMapping
            for byte in normalized.map({ Array($0.utf8) }) ?? literal {
                if byte < 128 {
                    result.append(Character(UnicodeScalar(byte)))
                } else {
                    result += String(format: "%%%02X", byte)
                }
            }
            literal.removeAll(keepingCapacity: true)
        }
        var index = 0
        while index < bytes.count {
            if bytes[index] == 37, index + 2 < bytes.count,
               let byte = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                if byte >= 128 || (65...90).contains(byte) || (97...122).contains(byte)
                    || (48...57).contains(byte) || [45, 46, 95, 126].contains(byte) {
                    literal.append(byte)
                } else {
                    flushLiteral()
                    result += String(format: "%%%02X", byte)
                }
                index += 3
            } else {
                literal.append(bytes[index])
                index += 1
            }
        }
        flushLiteral()
        return result
    }

    static func recipientDomains(_ components: URLComponents?) -> [String] {
        var recipients = [components?.percentEncodedPath.removingPercentEncoding ?? ""]
        recipients += (components?.queryItems ?? []).filter { $0.name.caseInsensitiveCompare("to") == .orderedSame }
            .compactMap(\.value)
        return recipients.flatMap(splitAddressList).compactMap(recipientDomain)
    }

    /// RFC 5322-lite: quoted strings support backslash escapes; angle addresses may
    /// carry a display name. Comments, groups, and obsolete address syntax are unsupported.
    private static func splitAddressList(_ value: String) -> [String] {
        var entries: [String] = []
        var entry = ""
        var quoted = false, escaped = false
        var angleDepth = 0
        for character in value {
            if escaped {
                escaped = false
            } else if quoted && character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted {
                if character == "<" { angleDepth += 1 }
                if character == ">" { angleDepth -= 1 }
                if character == "," && angleDepth == 0 {
                    entries.append(entry)
                    entry = ""
                    continue
                }
            }
            entry.append(character)
        }
        entries.append(entry)
        return entries
    }

    private static func recipientDomain(_ entry: String) -> String? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        var quoted = false, escaped = false
        var open: String.Index?, close: String.Index?
        for index in trimmed.indices {
            let character = trimmed[index]
            if character.isNewline || character == "\0" { return nil }
            if escaped { escaped = false; continue }
            if quoted && character == "\\" { escaped = true; continue }
            if character == "\"" { quoted.toggle(); continue }
            if !quoted {
                if character == "<" {
                    guard open == nil, close == nil else { return nil }
                    open = index
                } else if character == ">" {
                    guard open != nil, close == nil else { return nil }
                    close = index
                } else if character == "\\" { return nil }
            }
        }
        guard !quoted, !escaped, (open == nil) == (close == nil) else { return nil }
        let address: String
        if let open, let close {
            // Reject unsupported display-name syntax rather than salvaging an angle address.
            quoted = false
            for character in trimmed[..<open] {
                if escaped { escaped = false; continue }
                if quoted && character == "\\" { escaped = true; continue }
                if character == "\"" { quoted.toggle(); continue }
                if !quoted && "@,;:()[]".contains(character) { return nil }
            }
            guard trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            address = trimmed[trimmed.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        } else {
            address = trimmed
        }
        var at: String.Index?
        quoted = false
        for index in address.indices {
            let character = address[index]
            if escaped { escaped = false; continue }
            if quoted && character == "\\" { escaped = true; continue }
            if character == "\"" { quoted.toggle() }
            if !quoted && character == "@" { at = index }
        }
        guard let at else { return nil }
        let local = String(address[..<at])
        let domain = String(address[address.index(after: at)...])
        guard validLocalPart(local), !domain.isEmpty else { return nil }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.first != "-" && label.last != "-"
                && label.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        }) else { return nil }
        return domain
    }

    private static func validLocalPart(_ local: String) -> Bool {
        guard !local.isEmpty else { return false }
        if local.first == "\"" {
            var escaped = false
            for index in local.indices.dropFirst() {
                let character = local[index]
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "\"" { return index == local.index(before: local.endIndex) }
            }
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "!#$%&'*+-/=?^_`{|}~."))
        return !local.hasPrefix(".") && !local.hasSuffix(".") && !local.contains("..")
            && local.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func glob(pattern: String, path: String) -> Bool {
        let pattern = Array(pattern), path = Array(path)
        var previous = Array(repeating: false, count: path.count + 1)
        previous[0] = true
        var index = 0
        while index < pattern.count {
            let star = pattern[index] == "*"
            let across = star && index + 1 < pattern.count && pattern[index + 1] == "*"
            var next = Array(repeating: false, count: path.count + 1)
            if star { next[0] = previous[0] }
            for offset in path.indices {
                if star {
                    next[offset + 1] = previous[offset + 1] || (next[offset] && (across || path[offset] != "/"))
                } else {
                    next[offset + 1] = previous[offset] && pattern[index] == path[offset]
                }
            }
            previous = next
            index += across ? 2 : 1
        }
        return previous[path.count]
    }
}

/// RFC 3492 encoding of a single Unicode label; ASCII labels pass through unchanged.
enum Punycode {
    static func encode(_ label: String) -> String? {
        let input = label.unicodeScalars.map { UInt64($0.value) }
        guard !input.isEmpty, input.count <= 256 else { return nil }
        let basic = input.filter { $0 < 128 }
        var output = String(String.UnicodeScalarView(basic.compactMap { UnicodeScalar(UInt32($0)) }))
        if basic.count == input.count { return output }
        if !basic.isEmpty { output += "-" }
        var handled = basic.count
        var n: UInt64 = 128, delta: UInt64 = 0, bias: UInt64 = 72
        while handled < input.count {
            guard let minimum = input.filter({ $0 >= n }).min() else { return nil }
            delta += (minimum - n) * UInt64(handled + 1)
            n = minimum
            for scalar in input {
                if scalar < n { delta += 1 }
                if scalar == n {
                    var q = delta
                    var k: UInt64 = 36
                    while true {
                        let threshold = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias)
                        if q < threshold { break }
                        output += digit(threshold + (q - threshold) % (36 - threshold))
                        q = (q - threshold) / (36 - threshold)
                        k += 36
                    }
                    output += digit(q)
                    bias = adapt(delta, points: UInt64(handled + 1), first: handled == basic.count)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return "xn--" + output
    }

    private static func digit(_ value: UInt64) -> String {
        String(UnicodeScalar(UInt8(value < 26 ? value + 97 : value - 26 + 48)))
    }

    private static func adapt(_ value: UInt64, points: UInt64, first: Bool) -> UInt64 {
        var delta = first ? value / 700 : value / 2
        delta += delta / points
        var k: UInt64 = 0
        while delta > 455 { delta /= 35; k += 36 }
        return k + 36 * delta / (delta + 38)
    }
}
