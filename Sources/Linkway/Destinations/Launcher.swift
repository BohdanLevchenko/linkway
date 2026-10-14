import AppKit
import LinkwayCore
import os

enum LaunchError: Error, Equatable {
    case destinationUnavailable(DestinationID)
    case privateWindowUnsupported(DestinationID)
    case launchFailed(String)
}

@MainActor
final class Launcher {
    private let logger = Logger(subsystem: DestinationRegistry.ownBundleID, category: "launch")
    /// Last queued launch per bundle ID. Launches into one app run one at a time so two cold
    /// starts cannot race and drop the second one's arguments.
    private var queues: [String: Task<Void, Never>] = [:]
    private static let forwardTimeout: Duration = .seconds(3)

    func open(_ request: LaunchRequest, registry: DestinationRegistry) async throws(LaunchError) {
        guard let destination = registry.destination(for: request.destination),
              destination.id.bundleID.caseInsensitiveCompare(DestinationRegistry.ownBundleID) != .orderedSame,
              FileManager.default.fileExists(atPath: destination.appURL.path(percentEncoded: false))
        else { throw .destinationUnavailable(request.destination) }

        let arguments = try commandLine(for: request, destination: destination)
        do {
            try await serialized(destination.id.bundleID.lowercased()) {
                if let arguments {
                    try await self.launch(destination, arguments: arguments)
                } else {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    _ = try await NSWorkspace.shared.open(
                        [request.url], withApplicationAt: destination.appURL, configuration: configuration
                    )
                }
            }
        } catch let error as LaunchError {
            throw error
        } catch {
            logger.error("Launch of \(destination.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw .launchFailed(error.localizedDescription)
        }
    }

    private func serialized(_ key: String, _ body: @escaping @MainActor () async throws -> Void) async throws {
        let previous = queues[key]
        let task = Task { @MainActor in
            await previous?.value
            try await body()
        }
        let tail = Task { _ = await task.result }
        queues[key] = tail
        defer { if queues[key] == tail { queues[key] = nil } }
        try await task.value
    }

    /// `nil` means a plain Launch Services open is enough.
    private func commandLine(for request: LaunchRequest, destination: Destination) throws(LaunchError) -> [String]? {
        guard destination.id.profileKey != nil || request.privateWindow else { return nil }

        let browser = BrowserCatalog.browser(for: destination.id.bundleID)
        // An argument starting with "-" would be parsed as a browser switch.
        guard request.url.scheme != nil, !request.url.absoluteString.hasPrefix("-") else {
            throw .launchFailed("Refusing to pass a non-absolute URL on the command line")
        }

        var arguments: [String] = []
        if let profileKey = destination.id.profileKey {
            guard browser?.engine == .chromium else { throw .destinationUnavailable(destination.id) }
            arguments.append("--profile-directory=\(profileKey)")
        }
        if request.privateWindow {
            guard destination.supportsPrivateWindow, let flag = browser?.privateWindowArgument else {
                throw .privateWindowUnsupported(destination.id)
            }
            arguments.append(flag)
        }
        return arguments + [request.url.absoluteString]
    }

    /// `OpenConfiguration.arguments` is ignored by an already running app, so a running browser
    /// gets a second short-lived process that forwards the arguments to it. A cold start goes
    /// through Launch Services so the browser is not our child process.
    /// Must run inside `serialized` so the running check is fresh for this launch.
    private func launch(_ destination: Destination, arguments: [String]) async throws {
        let bundleID = destination.id.bundleID
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            try await forward(destination, arguments: arguments)
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                NSApp.yieldActivation(to: app)
                app.activate()
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = arguments
        _ = try await NSWorkspace.shared.openApplication(at: destination.appURL, configuration: configuration)
    }

    /// Waits for the forwarder to exit without blocking the main actor. A forwarder still running
    /// at the timeout most likely became the browser itself, so that counts as delivered.
    private func forward(_ destination: Destination, arguments: [String]) async throws {
        guard let executable = Bundle(url: destination.appURL)?.executableURL else {
            throw LaunchError.destinationUnavailable(destination.id)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let outcome: ForwardOutcome = try await withCheckedThrowingContinuation { continuation in
            let once = OneShot(continuation)
            process.terminationHandler = { finished in
                once.resume(with: .success(finished.terminationReason == .exit
                    ? .exited(finished.terminationStatus)
                    : .signaled(finished.terminationStatus)))
            }
            do {
                try process.run()
            } catch {
                once.resume(with: .failure(error))
                return
            }
            Task {
                try? await Task.sleep(for: Self.forwardTimeout)
                once.resume(with: .success(.timedOut))
            }
        }

        switch outcome {
        case .exited(0):
            return
        case let .exited(status):
            throw LaunchError.launchFailed("\(destination.appName) exited with status \(status)")
        case let .signaled(signal):
            throw LaunchError.launchFailed("\(destination.appName) was terminated by signal \(signal)")
        case .timedOut:
            logger.notice("Forwarder for \(destination.id, privacy: .public) still running after timeout; assuming delivered")
        }
    }
}

private enum ForwardOutcome: Sendable {
    case exited(Int32)
    case signaled(Int32)
    case timedOut
}

/// Resumes a continuation once; later calls are ignored.
private final class OneShot<Value: Sendable>: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<Value, any Error>?>

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    func resume(with result: Result<Value, any Error>) {
        continuation.withLock { $0.take() }?.resume(with: result)
    }
}
