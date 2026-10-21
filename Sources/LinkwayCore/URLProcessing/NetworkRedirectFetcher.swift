import Foundation
import Network
import Security

public struct NetworkRedirectFetcher: RedirectFetching {
    public init() {}

    public func fetch(_ url: URL, method: RedirectMethod, timeout: TimeInterval) async throws -> RedirectResponse {
        // Production connections require the resolver's validated address.
        throw ResolveFailure.unsafeAddress
    }

    public func fetch(_ url: URL, address: String, method: RedirectMethod, timeout: TimeInterval) async throws -> RedirectResponse {
        guard PublicAddress.isPublic(address) == true,
              let host = url.host, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.user == nil, url.password == nil,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let port = NWEndpoint.Port(rawValue: UInt16(exactly: url.port ?? (scheme == "https" ? 443 : 80)) ?? 0),
              port.rawValue != 0 else { throw ResolveFailure.unsafeAddress }
        let endpointHost: NWEndpoint.Host
        if let ip = IPv4Address(address) { endpointHost = .ipv4(ip) }
        else if let ip = IPv6Address(address) { endpointHost = .ipv6(ip) }
        else { throw ResolveFailure.unsafeAddress }
        let parameters: NWParameters
        if scheme == "https" {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
                let peer = sec_trust_copy_ref(trust).takeRetainedValue()
                let policy = SecPolicyCreateSSL(true, host as CFString)
                let valid = SecTrustSetPolicies(peer, policy) == errSecSuccess && SecTrustEvaluateWithError(peer, nil)
                complete(valid)
            }, DispatchQueue.global(qos: .utility))
            parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        } else { parameters = .tcp }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let target = path + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        let authority = host + (url.port.map { ":\($0)" } ?? "")
        let request = "\(method.rawValue) \(target) HTTP/1.1\r\nHost: \(authority)\r\nUser-Agent: Linkway\r\nAccept: */*\r\nConnection: close\r\n\r\n"
        guard !target.contains("\r"), !target.contains("\n"), !authority.contains("\r"), !authority.contains("\n") else {
            throw ResolveFailure.unsafeAddress
        }
        let connection = NWConnection(to: .hostPort(host: endpointHost, port: port), using: parameters)
        let exchange = HeaderExchange(connection: connection, request: Data(request.utf8))
        return try await bounded(seconds: timeout) { try await exchange.run() }
    }
}

enum HTTPResponseParser {
    static let maximumHeaderBytes = 16 * 1024
    static func parse(_ data: Data) throws -> RedirectResponse? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: delimiter)?.upperBound else {
            guard data.count < maximumHeaderBytes else { throw ResolveFailure.network }
            return nil
        }
        guard end <= maximumHeaderBytes else { throw ResolveFailure.network }
        let text = String(decoding: data[..<end], as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        let statusLine = lines[0].split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard lines[0].utf8.allSatisfy({ $0 >= 32 && $0 != 127 }),
              statusLine.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(statusLine[0]),
              statusLine[1].utf8.count == 3, statusLine[1].utf8.allSatisfy({ (48...57).contains($0) }),
              let status = Int(statusLine[1]), (100...599).contains(status) else { throw ResolveFailure.network }
        var location: String?
        for line in lines.dropFirst() where !line.isEmpty {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else {
                throw ResolveFailure.network
            }
            let name = line[..<colon]
            let token = "!#$%&'*+-.^_`|~"
            guard !name.isEmpty, name.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || token.utf8.contains($0)
            }) else { throw ResolveFailure.network }
            let value = line[line.index(after: colon)...]
            guard value.utf8.allSatisfy({ $0 == 9 || $0 >= 32 && $0 != 127 }) else { throw ResolveFailure.network }
            if name.lowercased() == "location" {
                guard location == nil else { throw ResolveFailure.network }
                location = value.trimmingCharacters(in: .whitespaces)
            }
        }
        return .init(status: status, location: location)
    }
}

// Connection callbacks and header buffering are confined to this serial queue.
private final class HeaderExchange: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Linkway.redirect.headers")
    private let connection: NWConnection
    private let request: Data
    private var headers = Data()
    private let gate = CompletionGate<RedirectResponse>()

    init(connection: NWConnection, request: Data) { self.connection = connection; self.request = request }

    func run() async throws -> RedirectResponse {
        defer {
            connection.cancel()
            queue.async { self.connection.stateUpdateHandler = nil }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                connection.stateUpdateHandler = { [self] state in
                    switch state {
                    case .ready:
                        connection.send(content: request, completion: .contentProcessed { [self] error in
                            if let error { gate.finish(.failure(error)); connection.cancel() }
                            else { receive() }
                        })
                    case .failed(let error): gate.finish(.failure(error)); connection.cancel()
                    case .cancelled: gate.finish(.failure(CancellationError()))
                    default: break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            self.gate.finish(.failure(CancellationError()))
            self.connection.cancel()
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: HTTPResponseParser.maximumHeaderBytes - headers.count) {
            [self] data, _, complete, error in
            if let data { headers.append(data) }
            do {
                if let response = try HTTPResponseParser.parse(headers) {
                    gate.finish(.success(response)); connection.cancel()
                } else if let error { gate.finish(.failure(error)); connection.cancel() }
                else if complete { gate.finish(.failure(ResolveFailure.network)); connection.cancel() }
                else { receive() }
            } catch { gate.finish(.failure(error)); connection.cancel() }
        }
    }
}
