import AppKit
import LinkwayCore
import os

@MainActor
final class LinkRouter {
    private static let resolvingHUDDelay: Duration = .milliseconds(800)

    private let registry: DestinationRegistry
    private let store: ConfigurationStore
    private let launcher = Launcher()
    private let picker = PickerController()
    private let logger = Logger(subsystem: DestinationRegistry.ownBundleID, category: "router")

    private(set) var configuration: LinkwayConfiguration = .default
    private var configurationLoaded = false
    private var pending: [IncomingLink] = []
    private var pickerRequests = 0
    private var launchesInFlight = 0
    private var resolutionID: UUID?
    private var resolutionTask: Task<Void, Never>?
    private let resolvingPanel = ResolvingLinkController()
    private var bounceBacks = BounceBackTracker()
    /// False when the file on disk exists but could not be read; saving then would overwrite it with defaults.
    private var canPersist = true
    private var lastSave: Task<Void, Never>?

    var onOpenPreferences: (() -> Void)?
    var onConfigurationLoaded: ((LinkwayConfiguration) -> Void)?
    private var configurationObservers: [(LinkwayConfiguration) -> Void] = []
    private var destinationObservers: [() -> Void] = []

    init(registry: DestinationRegistry, store: ConfigurationStore) {
        self.registry = registry
        self.store = store
        registry.onChange = { [weak self] in self?.destinationsChanged() }
    }

    func start() {
        registry.refresh()
        Task {
            do {
                configuration = try await store.load()
            } catch {
                logger.error("Configuration unreadable, using defaults without saving: \(String(describing: error), privacy: .public)")
                canPersist = false
            }
            configurationLoaded = true
            onConfigurationLoaded?(configuration)
            notifyConfigurationChanged()
            drain()
        }
    }

    func handle(_ link: IncomingLink) {
        pending.append(bounceBacks.isBounceBack(link) ? link.forcingPicker() : link)
        drain()
    }

    var rememberedRules: [Rule] { configuration.rememberedRules }

    func forgetRule(id: UUID) {
        updateConfiguration { $0.forgetRule(id: id) }
    }

    // MARK: Preferences API

    /// Handlers run on every configuration change, including the initial load, imports, and remembered choices.
    func observeConfiguration(_ handler: @escaping (LinkwayConfiguration) -> Void) {
        configurationObservers.append(handler)
        if configurationLoaded { handler(configuration) }
    }

    func observeDestinations(_ handler: @escaping () -> Void) {
        destinationObservers.append(handler)
    }

    func updateConfiguration(_ change: (inout LinkwayConfiguration) -> Void) {
        var updated = configuration
        change(&updated)
        guard updated != configuration else { return }
        configuration = updated
        persist()
        notifyConfigurationChanged()
    }

    func importConfiguration(from url: URL) async throws {
        await lastSave?.value
        try await store.import(from: url)
        configuration = try await store.load()
        canPersist = true
        notifyConfigurationChanged()
    }

    func exportConfiguration(to url: URL) async throws {
        await lastSave?.value
        try await store.export(to: url)
    }

    /// Everything the picker can show, hidden entries included, in discovery order.
    var pickerEntries: [Destination] { registry.destinations }
    var ruleTargets: [Destination] { registry.ruleTargets }
    var availableIDs: Set<DestinationID> { registry.availableIDs }
    func destination(for id: DestinationID) -> Destination? { registry.destination(for: id) }
    func icon(for destination: Destination) -> NSImage { registry.icon(for: destination) }

    /// Dry run of routing for the rule tester; never launches anything.
    func explain(_ url: URL, senderBundleID: String?) -> RoutingExplanation {
        let link = IncomingLink(url: url, receivedAt: Date(), senderBundleID: senderBundleID, forcePicker: false)
        let settings = configuration.urlProcessing
        let cleaned = TrackingCleaner(settings: settings).clean(url)
        let explanation = RoutingEngine(rules: configuration.rules, fallbacks: configuration.fallbacks)
            .explain(link, processedURL: cleaned.url, availableDestinations: registry.availableIDs)
        return RoutingExplanation(evaluations: explanation.evaluations, decision: explanation.decision,
                                  processedURL: cleaned.url, removedParameters: cleaned.removedParameters,
                                  wouldExpandShortLink: ShortLinkResolver(settings: settings).isShortLink(url))
    }

    private func notifyConfigurationChanged() {
        for observer in configurationObservers { observer(configuration) }
    }

    func targetName(for action: RuleAction) -> String {
        switch action {
        case .showPicker:
            return "Picker"
        case .open(let id, let privateWindow):
            let name = registry.destination(for: id)?.displayName ?? id.rawValue
            return privateWindow ? "\(name) (private)" : name
        }
    }

    private func persist() {
        guard canPersist else {
            logger.error("Configuration change kept in memory only: the file on disk was unreadable")
            return
        }
        let snapshot = configuration
        let previous = lastSave
        lastSave = Task { [store, logger] in
            await previous?.value
            do {
                try await store.save(snapshot)
            } catch {
                logger.error("Saving configuration failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private var isReady: Bool { configurationLoaded && registry.hasLoaded }

    private func drain() {
        guard isReady else { return }
        while resolutionID == nil && pickerRequests == 0 && launchesInFlight == 0 && !pending.isEmpty {
            route(pending.removeFirst())
        }
    }

    private func destinationsChanged() {
        picker.updateDestinations { [weak self] link in self?.pickerDestinations(for: link) ?? [] }
        for observer in destinationObservers { observer() }
        drain()
    }

    private func route(_ link: IncomingLink) {
        let settings = configuration.urlProcessing
        let resolver = ShortLinkResolver(settings: settings)
        guard link.kind == .web, settings.expandShortLinks, resolver.isShortLink(link.url) else {
            finishRouting(link, processing: TrackingCleaner(settings: settings).clean(link.url))
            return
        }
        let id = UUID()
        resolutionID = id
        let delayedHUD = Task { [weak self] in
            do { try await Task.sleep(for: Self.resolvingHUDDelay) } catch { return }
            guard let self, resolutionID == id else { return }
            resolvingPanel.show(url: link.url) { [weak self] in
                guard let self, resolutionID == id else { return }
                resolutionID = nil
                resolutionTask?.cancel()
                resolutionTask = nil
                logger.info("Short link cancelled by user")
                resolvingPanel.close()
                finishRouting(link, processing: .init(url: link.url))
                drain()
            }
        }
        resolutionTask = Task { [weak self] in
            let result = await resolver.resolve(link.url)
            delayedHUD.cancel()
            guard let self, resolutionID == id else { return }
            resolutionID = nil
            resolutionTask = nil
            resolvingPanel.close()
            let expanded = result.outcome == .expanded
            switch result.outcome {
            case .expanded: logger.info("Short link expanded; hops=\(result.hops.count, privacy: .public)")
            case .failed: logger.info("Short link failed")
            case .cancelled: logger.info("Short link cancelled")
            case .notShortLink: logger.info("Not a short link")
            }
            finishRouting(link, processing: TrackingCleaner(settings: settings).clean(expanded ? result.url : link.url),
                          expanded: expanded)
            drain()
        }
    }

    private func finishRouting(_ link: IncomingLink, processing: CleanResult, expanded: Bool = false) {
        let engine = RoutingEngine(rules: configuration.rules, fallbacks: configuration.fallbacks)
        let decision = engine.decide(
            link,
            processedURL: processing.url,
            availableDestinations: registry.availableIDs
        )
        logger.info("URL processing removed \(processing.removedParameters.count, privacy: .public) parameters")
        switch decision {
        case .launch(let request, _):
            logger.info("Routing to destination")
            launch(request, for: link, processing: processing, expanded: expanded)
        case .showPicker:
            logger.info("Routing to picker")
            showPicker(for: link, processing: processing, expanded: expanded)
        }
    }

    private func showPicker(for link: IncomingLink, processing: CleanResult, expanded: Bool = false) {
        pickerRequests += 1
        picker.present(
            link: link,
            processing: processing, expanded: expanded,
            destinations: pickerDestinations(for: link),
            rememberTargets: RuleSuggestion.rememberTargets(for: link),
            style: configuration.pickerStyle,
            avatarProvider: { [registry] in registry.avatar(for: $0) },
            onOpenPreferences: { [weak self] in self?.onOpenPreferences?() },
            iconProvider: { [registry] in registry.icon(for: $0) },
            completion: { [weak self] result in
                guard let self else { return }
                pickerRequests -= 1
                defer { drain() }
                guard case .open(let request, let remember) = result else { return }
                if let remember {
                    updateConfiguration { $0.remember(remember, destination: request.destination, privateWindow: request.privateWindow) }
                }
                launch(request, for: link, processing: processing, expanded: expanded)
            }
        )
    }

    private func launch(_ request: LaunchRequest, for link: IncomingLink, processing: CleanResult, expanded: Bool) {
        bounceBacks.recordLaunch(bundleID: request.destination.bundleID, startedAt: Date())
        launchesInFlight += 1
        Task {
            defer { launchesInFlight -= 1; drain() }
            do {
                try await launcher.open(request, registry: registry)
            } catch {
                logger.error("Launch failed")
                showPicker(for: link, processing: processing, expanded: expanded)
            }
        }
    }

    private func pickerDestinations(for link: IncomingLink) -> [Destination] {
        pickerDestinations(kind: link.kind == .mail ? .mailClient : .browser)
    }

    func pickerDestinations(kind: DestinationKind) -> [Destination] {
        let favorites = configuration.favoriteDestinations
        let order = configuration.destinationOrder
        func rank(_ id: DestinationID) -> (Int, Int) {
            if let index = favorites.firstIndex(of: id) { return (0, index) }
            if let index = order.firstIndex(of: id) { return (1, index) }
            return (2, 0)
        }
        return registry.destinations
            .enumerated()
            .filter { $0.element.kind == kind && !configuration.hiddenDestinations.contains($0.element.id) }
            .sorted { lhs, rhs in
                let (left, right) = (rank(lhs.element.id), rank(rhs.element.id))
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

private extension IncomingLink {
    func forcingPicker() -> IncomingLink {
        IncomingLink(url: url, receivedAt: receivedAt, senderBundleID: senderBundleID, forcePicker: true)
    }
}
