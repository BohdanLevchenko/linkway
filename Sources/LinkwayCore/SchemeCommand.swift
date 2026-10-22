import Foundation

public struct SchemeCommand: Sendable, Hashable {
    public enum Scope: Sendable, Hashable {
        case all
        case running

        public func filter(_ destinations: [Destination], runningBundleIDs: Set<String>) -> [Destination] {
            guard self == .running else { return destinations }
            let bundleIDs = Set(runningBundleIDs.map { $0.lowercased() })
            let running = destinations.filter { bundleIDs.contains($0.id.bundleID.lowercased()) }
            return running.isEmpty ? destinations : running
        }
    }

    public enum Mode: Sendable, Hashable {
        case route
        case prompt(scope: Scope)
        case best(scope: Scope)

        public var scope: Scope {
            switch self {
            case .route: .all
            case .prompt(let scope), .best(let scope): scope
            }
        }
    }

    public let link: URL
    public let mode: Mode

    public static func handles(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "linkway" || url.scheme?.lowercased() == "x-choosy"
    }

    public static func parse(_ url: URL) -> Result<SchemeCommand, SchemeCommandError> {
        let original = url.absoluteString
        guard handles(url), let colon = original.firstIndex(of: ":") else {
            return .failure(.unsupportedCommandScheme)
        }
        var command = original[original.index(after: colon)...]
        if command.hasPrefix("//") { command = command.dropFirst(2) }
        else if command.hasPrefix("/") { command = command.dropFirst() }
        let actionEnd = command.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? command.endIndex
        let action = String(command[..<actionEnd])
        let mode: Mode
        switch (url.scheme?.lowercased(), action) {
        case (_, "open"): mode = .route
        case ("linkway", "prompt"), ("x-choosy", "prompt.all"): mode = .prompt(scope: .all)
        case ("x-choosy", "prompt.running"): mode = .prompt(scope: .running)
        case ("x-choosy", "best.all"): mode = .best(scope: .all)
        case ("x-choosy", "best.running"): mode = .best(scope: .running)
        default: return .failure(.unknownAction)
        }
        let remainder = command[actionEnd...]
        var payload: String
        if remainder.hasPrefix("/") {
            // The payload owns its query and fragment, including any v= item.
            payload = String(remainder.dropFirst())
        } else if action == "open", remainder.hasPrefix("?") {
            guard let components = URLComponents(string: String(remainder)),
                  components.fragment == nil else { return .failure(.invalidQuery) }
            let items = components.queryItems ?? []
            guard items.filter({ $0.name == "v" }).allSatisfy({ $0.value == "1" }) else {
                return .failure(.unsupportedVersion)
            }
            let links = items.filter { $0.name == "url" }
            guard links.count == 1 else { return .failure(.invalidQuery) }
            payload = links[0].value ?? ""
        } else {
            return .failure(.emptyLink)
        }
        guard !payload.isEmpty else { return .failure(.emptyLink) }
        for scheme in ["http", "https"] {
            let prefix = scheme + ":/"
            if payload.lowercased().hasPrefix(prefix), !payload.lowercased().hasPrefix(prefix + "/") {
                payload.insert("/", at: payload.index(payload.startIndex, offsetBy: prefix.count))
            }
        }
        guard let link = URL(string: payload), let scheme = link.scheme?.lowercased() else {
            return .failure(.invalidLink)
        }
        guard ["http", "https", "mailto"].contains(scheme) else { return .failure(.unsupportedLinkScheme) }
        if scheme != "mailto" {
            guard let host = link.host, !host.isEmpty else { return .failure(.invalidLink) }
        }
        return .success(SchemeCommand(link: link, mode: mode))
    }
}

public enum SchemeCommandError: String, Error, Sendable {
    case unsupportedCommandScheme
    case unknownAction
    case emptyLink
    case invalidQuery
    case unsupportedVersion
    case invalidLink
    case unsupportedLinkScheme
}
