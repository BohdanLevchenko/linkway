import AppKit
import LinkwayCore
import os

@MainActor
final class DestinationRegistry {
    nonisolated static let ownBundleID = "io.github.bohdanlevchenko.linkway"

    /// What the picker shows: profiles when a browser has 2+, otherwise the browser itself.
    private(set) var destinations: [Destination] = []
    /// Every ID that `destination(for:)` resolves and the Launcher can open. Includes the
    /// browser-level ID and each profile regardless of profile count, so rule targets stay
    /// valid when profiles are added or removed.
    private(set) var availableIDs: Set<DestinationID> = []
    /// False until the first scan completes; `onChange` always fires for that first scan.
    private(set) var hasLoaded = false
    var onChange: (() -> Void)?

    private var index: [DestinationID: Destination] = [:]
    private var icons: [URL: NSImage] = [:]
    private var watcher: FileSystemWatcher?
    private var generation = 0
    private let logger = Logger(subsystem: ownBundleID, category: "destinations")

    func refresh() {
        generation += 1
        let current = generation
        let ownAppURL = Bundle.main.bundleURL
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                DestinationDiscovery.scan(excludingAppAt: ownAppURL)
            }.value
            guard current == generation else { return }
            apply(snapshot)
        }
    }

    func destination(for id: DestinationID) -> Destination? {
        index[id]
    }

    func icon(for destination: Destination) -> NSImage {
        if let cached = icons[destination.appURL] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: destination.appURL.path(percentEncoded: false))
        icons[destination.appURL] = icon
        return icon
    }

    private func apply(_ snapshot: DestinationDiscovery.Snapshot) {
        if watcher?.paths != snapshot.watchPaths {
            watcher = FileSystemWatcher(paths: snapshot.watchPaths, latency: 1.0) { [weak self] _ in
                self?.refresh()
            }
        }
        let resolvable = Dictionary(snapshot.resolvable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard !hasLoaded || snapshot.destinations != destinations || resolvable != index else { return }
        hasLoaded = true
        destinations = snapshot.destinations
        index = resolvable
        availableIDs = Set(resolvable.keys)
        icons = icons.filter { url, _ in snapshot.resolvable.contains { $0.appURL == url } }
        logger.info("Destinations updated: \(snapshot.destinations.count, privacy: .public)")
        onChange?()
    }
}

/// File reads and Launch Services queries, run off the main actor.
enum DestinationDiscovery {
    struct Snapshot: Sendable {
        let destinations: [Destination]
        /// `destinations` plus the browser-level and single-profile entries the picker hides.
        let resolvable: [Destination]
        /// App folders (recursive) and exact `Local State` file paths, so Chromium's constant
        /// profile writes elsewhere in the user-data dir never wake us.
        let watchPaths: [String]
    }

    private struct InstalledApp {
        let bundleID: String
        let url: URL
        let name: String
    }

    private static let webProbe = URL(string: "https://example.com")!
    private static let mailProbe = URL(string: "mailto:test@example.com")!

    static func scan(excludingAppAt ownAppURL: URL) -> Snapshot {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let supportDirectory = home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let ownPath = ownAppURL.resolvingSymlinksInPath().standardizedFileURL.path

        func installedApps(handling probe: URL) -> [InstalledApp] {
            let candidates = NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url -> InstalledApp? in
                guard url.resolvingSymlinksInPath().standardizedFileURL.path != ownPath,
                      let bundleID = Bundle(url: url)?.bundleIdentifier,
                      bundleID.caseInsensitiveCompare(DestinationRegistry.ownBundleID) != .orderedSame
                else { return nil }
                return InstalledApp(bundleID: bundleID, url: url, name: appName(at: url))
            }
            var chosen: [String: InstalledApp] = [:]
            for app in candidates {
                let key = app.bundleID.lowercased()
                if let existing = chosen[key], installRank(existing.url, home: home) <= installRank(app.url, home: home) {
                    continue
                }
                chosen[key] = app
            }
            return chosen.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        let browsers = installedApps(handling: webProbe).filter(isBrowser)
        let browserIDs = Set(browsers.map { $0.bundleID.lowercased() })
        let mailClients = installedApps(handling: mailProbe).filter { app in
            !browserIDs.contains(app.bundleID.lowercased()) && isMailClient(app)
        }

        var destinations: [Destination] = []
        var resolvable: [Destination] = []
        var watchPaths: [String] = []
        for app in browsers {
            let known = BrowserCatalog.browser(for: app.bundleID)
            let supportsPrivate = known?.privateWindowArgument != nil
            var profiles: [ChromiumProfile] = []
            if case let .chromium(userDataPath)? = known?.enabledProfileAdapter {
                let localState = supportDirectory
                    .appending(path: userDataPath, directoryHint: .isDirectory)
                    .appending(path: ChromiumLocalState.fileName)
                // FSEvents also reports a file that does not exist yet, e.g. before the first browser run.
                watchPaths.append(localState.path)
                profiles = chromiumProfiles(at: localState)
            }
            let browserLevel = Destination(
                id: DestinationID(bundleID: app.bundleID), kind: .browser, appName: app.name,
                profileName: nil, appURL: app.url, supportsPrivateWindow: supportsPrivate
            )
            let profileDestinations = profiles.map { profile in
                Destination(
                    id: DestinationID(bundleID: app.bundleID, profileKey: profile.directory),
                    kind: .browser, appName: app.name, profileName: profile.displayName,
                    appURL: app.url, supportsPrivateWindow: supportsPrivate
                )
            }
            destinations += profileDestinations.count >= 2 ? profileDestinations : [browserLevel]
            resolvable += [browserLevel] + profileDestinations
        }
        let mailDestinations = mailClients.map { app in
            Destination(
                id: DestinationID(bundleID: app.bundleID), kind: .mailClient, appName: app.name,
                profileName: nil, appURL: app.url, supportsPrivateWindow: false
            )
        }
        destinations += mailDestinations
        resolvable += mailDestinations

        let appDirectories = ["/Applications", home.appending(path: "Applications").path]
            .filter { fileManager.fileExists(atPath: $0) }
        return Snapshot(destinations: destinations, resolvable: resolvable, watchPaths: appDirectories + watchPaths)
    }

    /// Known apps skip the plist check so an unusual Info.plist cannot hide them.
    private static func isBrowser(_ app: InstalledApp) -> Bool {
        BrowserCatalog.browser(for: app.bundleID) != nil
            || infoPlist(of: app).map(HandlerEligibility.isBrowser) == true
    }

    private static func isMailClient(_ app: InstalledApp) -> Bool {
        MailClientCatalog.contains(app.bundleID)
            || infoPlist(of: app).map(HandlerEligibility.isMailClient) == true
    }

    private static func infoPlist(of app: InstalledApp) -> AppInfoPlist? {
        guard let data = try? Data(contentsOf: app.url.appending(path: "Contents/Info.plist")) else { return nil }
        return try? AppInfoPlist(data: data)
    }

    /// Finder's display name is localized but keeps ".app" when the user shows all extensions.
    private static func appName(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(".app".count)) : name
    }

    private static func chromiumProfiles(at localState: URL) -> [ChromiumProfile] {
        guard let data = try? Data(contentsOf: localState) else { return [] }
        return (try? ChromiumLocalState.profiles(from: data)) ?? []
    }

    private static func installRank(_ url: URL, home: URL) -> Int {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/Applications/") { return 0 }
        if path.hasPrefix(home.appending(path: "Applications").path + "/") { return 1 }
        if path.hasPrefix("/System/") { return 2 }
        return 3
    }
}
