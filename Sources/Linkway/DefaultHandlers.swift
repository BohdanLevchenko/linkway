import AppKit
import Combine

enum HandlerRole {
    case browser, mail

    fileprivate var schemes: [String] {
        switch self {
        case .browser: ["http", "https"]
        case .mail: ["mailto"]
        }
    }
}

enum MakeDefaultOutcome {
    case alreadyDefault, changed, declined, failed(String)
}

@MainActor
final class DefaultHandlers: ObservableObject {
    @Published private(set) var isWorking = false

    func isDefault(_ role: HandlerRole) -> Bool {
        role.schemes.allSatisfy(isDefaultHandler)
    }

    func currentHandlerName(_ role: HandlerRole) -> String {
        let scheme = role == .browser ? "https" : "mailto"
        guard let handler = handlerURL(for: scheme) else { return "None" }
        if isOurApplication(handler) { return "Linkway" }
        return FileManager.default.displayName(atPath: handler.path)
    }

    func makeDefault(_ role: HandlerRole) async -> MakeDefaultOutcome {
        guard !isWorking else { return .declined }
        guard !isDefault(role) else { return .alreadyDefault }
        isWorking = true
        defer { isWorking = false }

        var failure: Error?
        // A confirmed http request can also change https. Recheck before each request.
        for scheme in role.schemes where !isDefaultHandler(scheme) {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme
                )
            } catch {
                failure = error
                break
            }
        }
        if isDefault(role) { return .changed }
        if let failure, !isUserCancellation(failure) {
            return .failed(failure.localizedDescription)
        }
        return .declined
    }

    private func handlerURL(for scheme: String) -> URL? {
        let value = scheme == "mailto" ? "mailto:hello@example.com" : "\(scheme)://example.com"
        guard let url = URL(string: value) else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    private func isDefaultHandler(_ scheme: String) -> Bool {
        handlerURL(for: scheme).map(isOurApplication) ?? false
    }

    private func isOurApplication(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError { return true }
        if error.domain == NSOSStatusErrorDomain && error.code == -128 { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isUserCancellation(underlying)
        }
        return false
    }
}
