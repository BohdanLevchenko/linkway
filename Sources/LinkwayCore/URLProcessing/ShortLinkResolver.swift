import Foundation
import Darwin

public enum RedirectMethod: String, Sendable { case head = "HEAD", get = "GET" }
public struct RedirectResponse: Sendable {
    public let status: Int
    public let location: String?
    public init(status: Int, location: String? = nil) { self.status = status; self.location = location }
}
public protocol RedirectFetching: Sendable {
    func fetch(_ url: URL, method: RedirectMethod, timeout: TimeInterval) async throws -> RedirectResponse
    func fetch(_ url: URL, address: String, method: RedirectMethod, timeout: TimeInterval) async throws -> RedirectResponse
}
extension RedirectFetching {
    public func fetch(_ url: URL, address: String, method: RedirectMethod, timeout: TimeInterval) async throws -> RedirectResponse {
        try await fetch(url, method: method, timeout: timeout)
    }
}
public protocol HostAddressResolving: Sendable {
    func addresses(for host: String) async throws -> [String]
}
public enum ResolveFailure: String, Sendable, Hashable, Error {
    case unsafeAddress, invalidRedirect, loop, hopLimit, timeout, network, missingLocation
}
public struct ResolveResult: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case expanded, notShortLink, failed(ResolveFailure), cancelled
    }
    public let url: URL
    public let hops: [URL]
    public let outcome: Outcome
}
public struct ShortLinkResolver: Sendable {
    public static let maximumHops = 5
    public static let totalBudget: TimeInterval = 4
    public static let requestTimeout: TimeInterval = 3
    private let settings: URLProcessingSettings
    private let fetcher: any RedirectFetching
    private let addresses: any HostAddressResolving
    public init(settings: URLProcessingSettings, fetcher: any RedirectFetching = NetworkRedirectFetcher(),
                addresses: any HostAddressResolving = SystemHostAddressResolver()) {
        self.settings = settings; self.fetcher = fetcher; self.addresses = addresses
    }
    public func isShortLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && settings.shortenerHosts.contains { hostMatches(url.host ?? "", suffix: $0) }
    }
    public func resolve(_ url: URL) async -> ResolveResult {
        guard isShortLink(url) else { return .init(url: url, hops: [], outcome: .notShortLink) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(Self.totalBudget))
        var current = url
        var hops: [URL] = []
        var seen: Set<URL> = [url]
        do {
            var validated = try await check(current, deadline: deadline)
            for _ in 0..<Self.maximumHops {
                try Task.checkCancellation()
                var response = try await request(current, address: validated[0], method: .head, deadline: deadline)
                if response.status == 405 || response.status == 501 || response.location?.isEmpty != false {
                    validated = try await check(current, deadline: deadline)
                    response = try await request(current, address: validated[0], method: .get, deadline: deadline)
                }
                guard [301, 302, 303, 307, 308].contains(response.status),
                      let location = response.location, !location.isEmpty else { throw ResolveFailure.missingLocation }
                guard let next = URL(string: location, relativeTo: current)?.absoluteURL else {
                    throw ResolveFailure.invalidRedirect
                }
                validated = try await check(next, deadline: deadline)
                guard seen.insert(next).inserted else { throw ResolveFailure.loop }
                hops.append(next)
                current = next
                if !isShortLink(next) {
                    return .init(url: current, hops: hops, outcome: .expanded)
                }
            }
            throw ResolveFailure.hopLimit
        } catch is CancellationError {
            return .init(url: current, hops: hops, outcome: .cancelled)
        } catch let error as URLError where error.code == .timedOut {
            return .init(url: current, hops: hops, outcome: .failed(.timeout))
        } catch {
            return .init(url: current, hops: hops, outcome: .failed(error as? ResolveFailure ?? .network))
        }
    }
    private func request(_ url: URL, address: String, method: RedirectMethod, deadline: ContinuousClock.Instant) async throws -> RedirectResponse {
        let timeout = min(Self.requestTimeout, remaining(deadline))
        guard timeout > 0 else { throw ResolveFailure.timeout }
        return try await bounded(seconds: timeout) { try await fetcher.fetch(url, address: address, method: method, timeout: timeout) }
    }
    private func remaining(_ deadline: ContinuousClock.Instant) -> TimeInterval {
        let duration = ContinuousClock.now.duration(to: deadline)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
    private func check(_ url: URL, deadline: ContinuousClock.Instant) async throws -> [String] {
        try Task.checkCancellation()
        guard remaining(deadline) > 0 else { throw ResolveFailure.timeout }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let rawHost = url.host else { throw ResolveFailure.unsafeAddress }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.contains("%"), host != "localhost",
              !["local", "internal", "lan", "localhost"].contains(where: { hostMatches(host, suffix: $0) }) else {
            throw ResolveFailure.unsafeAddress
        }
        if let safe = PublicAddress.isPublic(host) {
            guard safe else { throw ResolveFailure.unsafeAddress }
            return [host]
        }
        guard host.contains(".") else { throw ResolveFailure.unsafeAddress }
        let timeout = remaining(deadline)
        guard timeout > 0 else { throw ResolveFailure.timeout }
        let resolved = try await bounded(seconds: timeout) { try await addresses.addresses(for: host) }
        guard !resolved.isEmpty, resolved.allSatisfy({ PublicAddress.isPublic($0) == true }) else {
            throw ResolveFailure.unsafeAddress
        }
        return resolved
    }
}

// A single completion gate also bounds injected I/O that does not cooperate with cancellation.
final class CompletionGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Result<Value, any Error>?
    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<Value, any Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
func bounded<Value: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
    let gate = CompletionGate<Value>()
    let work = Task {
        do { gate.finish(.success(try await operation())) }
        catch { gate.finish(.failure(error)) }
    }
    let timer = Task {
        do { try await Task.sleep(for: .seconds(seconds)); gate.finish(.failure(ResolveFailure.timeout)); work.cancel() }
        catch {}
    }
    defer { work.cancel(); timer.cancel() }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { gate.install($0) }
    } onCancel: {
        gate.finish(.failure(CancellationError()))
        work.cancel()
    }
}

enum PublicAddress {
    static func isPublic(_ text: String) -> Bool? {
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            let value = UInt32(bigEndian: v4.s_addr)
            let a = value >> 24, b = (value >> 16) & 255
            return !(a == 0 || a == 10 || a == 127 || a >= 224
                || (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254)
                || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168))
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 {
            let bytes = withUnsafeBytes(of: &v6) { Array($0) }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
                return isPublic(bytes.suffix(4).map(String.init).joined(separator: "."))
            }
            // Only global unicast; excludes unspecified, loopback, ULA, link-local and multicast.
            guard bytes[0] & 0xe0 == 0x20 else { return false }
            // IPv4 transition ranges can tunnel local addresses.
            if bytes[0] == 0x20 && bytes[1] == 0x02 { return false }
            if bytes.prefix(4) == [0x20, 0x01, 0, 0] { return false }
            return true
        }
        return nil
    }
}

public struct SystemHostAddressResolver: HostAddressResolving {
    public init() {}
    public func addresses(for host: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &result) == 0 else {
                    continuation.resume(throwing: ResolveFailure.network); return
                }
                defer { if let result { freeaddrinfo(result) } }
                var output: [String] = []
                var cursor = result
                while let entry = cursor {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer,
                                   socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                        output.append(String(decoding: bytes, as: UTF8.self))
                    }
                    cursor = entry.pointee.ai_next
                }
                continuation.resume(returning: output)
            }
        }
    }
}

