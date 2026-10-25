import Foundation
import LinkwayCore
import Testing
@testable import Linkway

@MainActor
@Test func webmailRegistryTracksTargetsAndAccountChanges() throws {
    let registry = DestinationRegistry()
    let browser = Destination(id: DestinationID(bundleID: "com.example.browser"), kind: .browser,
                              appName: "Browser", profileName: nil, appURL: URL(filePath: "/fake/Browser.app"),
                              supportsPrivateWindow: true)
    let profile = Destination(id: DestinationID(bundleID: browser.id.bundleID, profileKey: "Work"), kind: .browser,
                              appName: "Browser", profileName: "Work", appURL: browser.appURL,
                              supportsPrivateWindow: true)
    var account = WebmailAccount(provider: .gmail, displayName: "Work mail", browser: profile.id)
    registry.setWebmailAccounts([account])
    #expect(!registry.availableIDs.contains(account.destinationID))
    let snapshot = DestinationDiscovery.Snapshot(destinations: [browser], resolvable: [browser, profile], watchPaths: [])
    registry.apply(snapshot)
    #expect(registry.hasLoaded)
    #expect(registry.availableIDs.contains(account.destinationID))
    #expect(registry.destinations.map(\.id) == [browser.id, account.destinationID])
    #expect(registry.ruleTargets.contains { $0.id == account.destinationID })
    #expect(registry.webmailAccount(for: account.destinationID) == account)
    account.displayName = "Renamed"
    account.account = "me@example.com"
    registry.setWebmailAccounts([account])
    #expect(registry.destination(for: account.destinationID)?.profileName == "Renamed")
    #expect(registry.webmailAccount(for: account.destinationID)?.account == "me@example.com")
    registry.apply(.init(destinations: [browser], resolvable: [browser], watchPaths: []))
    #expect(registry.destination(for: account.destinationID) == nil)
    #expect(!registry.availableIDs.contains(account.destinationID))
    registry.apply(snapshot)
    #expect(registry.availableIDs.contains(account.destinationID))
    registry.setWebmailAccounts([])
    #expect(registry.destination(for: account.destinationID) == nil)
    #expect(!registry.availableIDs.contains(account.destinationID))
}

@MainActor
@Test func webmailRejectsMailClientAsBrowserTarget() {
    let registry = DestinationRegistry()
    let mail = Destination(id: DestinationID(bundleID: "com.example.mail"), kind: .mailClient,
                           appName: "Mail", profileName: nil, appURL: URL(filePath: "/fake/Mail.app"),
                           supportsPrivateWindow: false)
    let account = WebmailAccount(provider: .gmail, displayName: "Invalid", browser: mail.id)
    registry.setWebmailAccounts([account])
    registry.apply(.init(destinations: [mail], resolvable: [mail], watchPaths: []))
    #expect(account.destination(target: mail) == nil)
    #expect(!registry.availableIDs.contains(account.destinationID))
}

@MainActor
@Test func runningMailModesResolveWebmailBrowserAndKeepFavorites() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let browser = Destination(id: .init(bundleID: "test.chrome", profileKey: "Personal"), kind: .browser,
                              appName: "Chrome", profileName: "Personal", appURL: URL(filePath: "/fake/Chrome.app"),
                              supportsPrivateWindow: true)
    let stoppedBrowser = Destination(id: .init(bundleID: "test.stopped"), kind: .browser, appName: "Stopped",
                                     profileName: nil, appURL: URL(filePath: "/fake/Stopped.app"), supportsPrivateWindow: true)
    let mail = Destination(id: .init(bundleID: "test.mail"), kind: .mailClient, appName: "Mail",
                           profileName: nil, appURL: URL(filePath: "/fake/Mail.app"), supportsPrivateWindow: false)
    let gmail = WebmailAccount(provider: .gmail, displayName: "Personal", browser: browser.id)
    let yahoo = WebmailAccount(provider: .yahoo, displayName: "Personal", browser: stoppedBrowser.id)
    let registry = DestinationRegistry()
    registry.apply(.init(destinations: [mail, browser, stoppedBrowser], resolvable: [mail, browser, stoppedBrowser], watchPaths: []))
    var running: Set<String> = [browser.id.bundleID, mail.id.bundleID]
    let router = LinkRouter(registry: registry, store: ConfigurationStore(fileURL: directory.appending(path: "config.json")),
                            isRunning: { running.contains($0) })
    let config = LinkwayConfiguration(favoriteDestinations: [gmail.destinationID, mail.id, yahoo.destinationID],
                                      webmailAccounts: [gmail, yahoo])
    let input = directory.appending(path: "import.json")
    try JSONEncoder().encode(config).write(to: input)
    try await router.importConfiguration(from: input)
    for action in ["prompt.running", "best.running"] {
        let command = try SchemeCommand.parse("x-choosy://\(action)/mailto:a@example.com").get()
        let link = IncomingLink(url: command.link, receivedAt: Date(), senderBundleID: nil, forcePicker: false, mode: command.mode)
        let order = router.pickerDestinations(for: link).map(\.id)
        #expect(order == [gmail.destinationID, mail.id])
        let engine = RoutingEngine(rules: [], fallbacks: .init())
        let decision = engine.decide(link, processedURL: link.url, availableDestinations: router.availableIDs(for: link.url), pickerOrder: order)
        #expect(decision == (action == "prompt.running" ? .showPicker(.forcedByUser)
                            : .launch(.init(url: link.url, destination: gmail.destinationID), matchedRule: nil)))
        running = [mail.id.bundleID]
        #expect(router.pickerDestinations(for: link).map(\.id) == [mail.id])
        running = []
        #expect(router.pickerDestinations(for: link).map(\.id) == [gmail.destinationID, mail.id, yahoo.destinationID])
        running = [browser.id.bundleID, mail.id.bundleID]
    }
}
