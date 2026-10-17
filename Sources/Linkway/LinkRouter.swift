import AppKit
import LinkwayCore
import os

@MainActor
final class LinkRouter {
    private static let bounceWindow: TimeInterval = 3

    private let registry: DestinationRegistry
    private let store: ConfigurationStore
    private let launcher = Launcher()
    private let picker = PickerController()
    private let logger = Logger(subsystem: DestinationRegistry.ownBundleID, category: "router")

    private(set) var configuration: LinkwayConfiguration = .default
    private var configurationLoaded = false
    private var pending: [IncomingLink] = []
    private var recentLaunches: [String: Date] = [:]
    /// False when the file on disk exists but could not be read; saving then would overwrite it with defaults.
    private var canPersist = true
    private var lastSave: Task<Void, Never>?

    var onConfigurationLoaded: ((LinkwayConfiguration) -> Void)?

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
            drain()
        }
    }

    func handle(_ link: IncomingLink) {
        pending.append(link)
        drain()
    }

    var rememberedRules: [Rule] { configuration.rememberedRules }

    func forgetRule(id: UUID) {
        configuration.forgetRule(id: id)
        persist()
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
        while !pending.isEmpty {
            route(pending.removeFirst())
        }
    }

    private func destinationsChanged() {
        picker.updateDestinations { [weak self] link in self?.pickerDestinations(for: link) ?? [] }
        drain()
    }

    private func route(_ link: IncomingLink) {
        let engine = RoutingEngine(rules: configuration.rules, fallbacks: configuration.fallbacks)
        let decision = engine.decide(
            isBounceBack(link) ? link.forcingPicker() : link,
            processedURL: link.url,
            availableDestinations: registry.availableIDs
        )
        logger.info("Routing \(String(describing: link.kind), privacy: .public) link: \(String(describing: decision), privacy: .public)")
        switch decision {
        case .launch(let request, _):
            launch(request, for: link)
        case .showPicker:
            showPicker(for: link)
        }
    }

    /// A link coming straight back from the app we just launched means that app handed it to the
    /// default handler again; re-applying the same rule would loop.
    private func isBounceBack(_ link: IncomingLink) -> Bool {
        guard let sender = link.senderBundleID, let launchedAt = recentLaunches[sender.lowercased()] else {
            return false
        }
        let elapsed = link.receivedAt.timeIntervalSince(launchedAt)
        return elapsed >= 0 && elapsed < Self.bounceWindow
    }

    private func showPicker(for link: IncomingLink) {
        picker.present(
            link: link,
            destinations: pickerDestinations(for: link),
            rememberTargets: RuleSuggestion.rememberTargets(for: link),
            iconProvider: { [registry] in registry.icon(for: $0) },
            completion: { [weak self] result in
                guard let self, case .open(let request, let remember) = result else { return }
                if let remember {
                    configuration.remember(remember, destination: request.destination, privateWindow: request.privateWindow)
                    persist()
                }
                launch(request, for: link)
            }
        )
    }

    private func launch(_ request: LaunchRequest, for link: IncomingLink) {
        let now = Date()
        recentLaunches = recentLaunches.filter { now.timeIntervalSince($0.value) < Self.bounceWindow }
        recentLaunches[request.destination.bundleID.lowercased()] = now
        Task {
            do {
                try await launcher.open(request, registry: registry)
                recentLaunches[request.destination.bundleID.lowercased()] = Date()
            } catch {
                logger.error("Launch failed for \(request.destination, privacy: .public): \(String(describing: error), privacy: .public)")
                showPicker(for: link)
            }
        }
    }

    private func pickerDestinations(for link: IncomingLink) -> [Destination] {
        let kind: DestinationKind = link.kind == .mail ? .mailClient : .browser
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
