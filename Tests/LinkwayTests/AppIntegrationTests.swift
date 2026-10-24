import Foundation
import LinkwayCore
import Testing
@testable import Linkway

@MainActor
@Test func matchingAppsLeadBothPickerStylesAndResolveAsRuleTargets() {
    let registry = DestinationRegistry()
    let browser = Destination(id: DestinationID(bundleID: "test.browser"), kind: .browser, appName: "Browser",
                              profileName: nil, appURL: URL(filePath: "/fake/Browser.app"), supportsPrivateWindow: true)
    let figma = Destination(id: DestinationID(bundleID: "com.figma.Desktop"), kind: .app, appName: "Figma",
                            profileName: nil, appURL: URL(filePath: "/fake/Figma.app"), supportsPrivateWindow: false)
    registry.apply(.init(destinations: [browser, figma], resolvable: [browser, figma], watchPaths: []))
    let router = LinkRouter(registry: registry, store: ConfigurationStore(fileURL: URL(filePath: "/tmp/unused-app-test-config")))
    let original = URL(string: "https://example.com/short")!
    let processed = URL(string: "https://www.figma.com/design/KEY/Name?node-id=1-2")!
    func link(_ url: URL) -> IncomingLink {
        .init(url: url, receivedAt: Date(), senderBundleID: nil, forcePicker: false)
    }
    #expect(registry.destination(for: figma.id) == figma)
    #expect(registry.ruleTargets.contains(figma))
    #expect(router.availableIDs(for: processed).contains(figma.id))
    #expect(!router.availableIDs(for: original).contains(figma.id))
    #expect(router.pickerDestinations(for: link(original)) == [browser])
    for style in [PickerStyle.tiles, .list] {
        let model = PickerModel(link: link(original), destinations: router.pickerDestinations(for: link(processed)),
                                style: style, processing: .init(url: processed), expanded: true)
        model.onActiveLinkChange = { [weak model] in model?.updateDestinations(router.pickerDestinations(for: $0)) }
        #expect(model.destinations == [figma, browser])
        #expect(model.tiles.first == .destination(figma))
        #expect(model.rows.first?.destination == figma)
        var request: LaunchRequest?
        model.onResult = { if case .open(let value, _) = $0 { request = value } }
        model.openSelected()
        #expect(request?.url == processed)
        #expect(request?.destination == figma.id)
        model.toggleOriginal()
        #expect(model.destinations == [browser])
        model.toggleOriginal()
        #expect(model.destinations == [figma, browser])
    }
    registry.apply(.init(destinations: [browser], resolvable: [browser], watchPaths: []))
    #expect(!router.availableIDs(for: processed).contains(figma.id))
    #expect(router.pickerDestinations(for: link(processed)) == [browser])
}

@Test func webRuleEditorsOfferAppsAndMailRulesDoNot() {
    for kind in ConditionKind.allCases {
        #expect(kind.accepts(.app) == (kind != .mailRecipientDomain))
    }
    let draft = RuleDraft(rule: Rule(name: "Design", condition: .hostExact("www.figma.com"),
                                    action: .open(.init(bundleID: "com.figma.Desktop"), privateWindow: false)))
    #expect(draft.kind.accepts(.app))
    #expect(draft.rule(supportsPrivate: false).action == .open(.init(bundleID: "com.figma.Desktop"), privateWindow: false))
}

@MainActor
@Test func disabledIntegrationsUpdatePickerAndRuleResolution() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let registry = DestinationRegistry()
    let figma = Destination(id: DestinationID(bundleID: "com.figma.Desktop"), kind: .app, appName: "Figma",
                            profileName: nil, appURL: URL(filePath: "/fake/Figma.app"), supportsPrivateWindow: false)
    let browser = Destination(id: DestinationID(bundleID: "test.browser"), kind: .browser, appName: "Browser",
                              profileName: nil, appURL: URL(filePath: "/fake/Browser.app"), supportsPrivateWindow: true)
    registry.apply(.init(destinations: [browser, figma], resolvable: [browser, figma], watchPaths: []))
    let router = LinkRouter(registry: registry, store: ConfigurationStore(fileURL: directory.appending(path: "config.json")))
    let input = directory.appending(path: "import.json")
    let rule = Rule(name: "Design", condition: .hostExact("www.figma.com"), action: .open(figma.id, privateWindow: false))
    let url = URL(string: "https://www.figma.com/design/KEY/Name?utm_source=mail&node-id=1-2")!
    let link = IncomingLink(url: url, receivedAt: Date(), senderBundleID: nil, forcePicker: false)
    var config = LinkwayConfiguration(rules: [rule], favoriteDestinations: [browser.id], disabledAppAdapters: ["figma"])
    try JSONEncoder().encode(config).write(to: input)
    try await router.importConfiguration(from: input)
    #expect(router.pickerEntries.contains(figma))
    #expect(!router.ruleTargets.contains(figma))
    #expect(!router.availableIDs.contains(figma.id))
    #expect(!router.availableIDs(for: url).contains(figma.id))
    #expect(router.pickerDestinations(for: link) == [browser])
    #expect(router.explain(url, senderBundleID: nil).decision == .showPicker(.ruleTargetUnavailable(rule.id, figma.id)))
    config.disabledAppAdapters = []
    try JSONEncoder().encode(config).write(to: input)
    try await router.importConfiguration(from: input)
    #expect(router.ruleTargets.contains(figma))
    #expect(router.availableIDs.contains(figma.id))
    #expect(router.pickerDestinations(for: link) == [figma, browser])
    let explanation = router.explain(url, senderBundleID: nil)
    #expect(explanation.decision == .launch(.init(url: URL(string: "https://www.figma.com/design/KEY/Name?node-id=1-2")!,
                                                destination: figma.id), matchedRule: rule.id))
}
