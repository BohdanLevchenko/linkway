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
        if request.destination.bundleID == WebmailAccount.bundleID {
            guard registry.destination(for: request.destination) != nil,
                  let account = registry.webmailAccount(for: request.destination),
                  let browserRequest = account.launchRequest(for: request.url) else {
                throw .destinationUnavailable(request.destination)
            }
            try await open(browserRequest, registry: registry)
            return
        }
        guard let destination = registry.destination(for: request.destination),
              destination.id.bundleID.caseInsensitiveCompare(DestinationRegistry.ownBundleID) != .orderedSame,
              FileManager.default.fileExists(atPath: destination.appURL.path(percentEncoded: false))
        else { throw .destinationUnavailable(request.destination) }

        do {
            try await serialized(destination.id.bundleID.lowercased()) {
                let state: BrowserRunningState = NSRunningApplication.runningApplications(
                    withBundleIdentifier: destination.id.bundleID
                ).isEmpty ? .stopped : .running
                if let plan = try self.commandLine(for: request, destination: destination, runningState: state) {
                    try await self.launch(destination, plan: plan)
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
            logger.error("Destination launch failed")
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
    private func commandLine(
        for request: LaunchRequest, destination: Destination, runningState: BrowserRunningState
    ) throws(LaunchError) -> BrowserLaunchPlan? {
        guard destination.id.profileKey != nil || request.privateWindow else { return nil }

        let browser = BrowserCatalog.browser(for: destination.id.bundleID)
        // An argument starting with "-" would be parsed as a browser switch.
        guard request.url.scheme != nil, !request.url.absoluteString.hasPrefix("-") else {
            throw .launchFailed("Refusing to pass a non-absolute URL on the command line")
        }

        if request.privateWindow && !destination.supportsPrivateWindow {
            throw .privateWindowUnsupported(destination.id)
        }
        if browser?.engine == .gecko {
            var profilePath: URL?
            if let key = destination.id.profileKey {
                guard case let .firefox(supportPath)? = browser?.enabledProfileAdapter else {
                    throw .destinationUnavailable(destination.id)
                }
                let support = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "Library/Application Support", directoryHint: .isDirectory)
                    .appending(path: supportPath, directoryHint: .isDirectory)
                profilePath = FirefoxProfiles.profilePath(forKey: key, supportDirectory: support)
                var isDirectory: ObjCBool = false
                guard let profilePath,
                      FileManager.default.fileExists(atPath: profilePath.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { throw .destinationUnavailable(destination.id) }
            }
            return .firefox(
                url: request.url, profilePath: profilePath,
                privateWindow: request.privateWindow, runningState: runningState
            )
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
        return BrowserLaunchPlan(arguments: arguments + [request.url.absoluteString], runningState: runningState)
    }

    // Firefox remotes by profile path; no --new-instance/-no-remote (they disable forwarding).
    // State             Delivery          Result (normal / private) — UNVERIFIED by hand
    // Stopped           Launch Services   Start target profile / private window
    // Same profile      Executable        Remote tab / private window to target
    // Other profile     Executable        Remote to target if present, otherwise start it
    // Arguments are identical across states: -profile <path> [-private-window] <url>.
    // Must run inside `serialized` so the running state is fresh.
    private func launch(_ destination: Destination, plan: BrowserLaunchPlan) async throws {
        if plan.delivery == .forward {
            try await forward(destination, arguments: plan.arguments)
            // Firefox's remote service raises the target; activating the first app may raise another profile.
            if BrowserCatalog.browser(for: destination.id.bundleID)?.engine != .gecko,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: destination.id.bundleID).first {
                NSApp.yieldActivation(to: app)
                app.activate()
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = plan.arguments
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
