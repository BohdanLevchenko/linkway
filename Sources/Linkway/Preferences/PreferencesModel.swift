import AppKit
import Combine
import LinkwayCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PreferencesModel: ObservableObject {
    let router: LinkRouter
    @Published private(set) var configuration: LinkwayConfiguration
    @Published private(set) var pickerEntries: [Destination] = []
    @Published private(set) var ruleTargets: [Destination] = []
    @Published private(set) var availableIDs: Set<DestinationID> = []
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var loginOperationInProgress = false
    @Published var loginError: String?
    @Published var fileError: String?
    @Published private(set) var fileOperationInProgress = false

    init(router: LinkRouter) {
        self.router = router
        configuration = router.configuration
        refreshDestinations()
        router.observeConfiguration { [weak self] in self?.configuration = $0 }
        router.observeDestinations { [weak self] in self?.refreshDestinations() }
    }

    private func refreshDestinations() {
        pickerEntries = router.pickerEntries
        ruleTargets = router.ruleTargets
        availableIDs = router.availableIDs
    }

    func update(_ change: (inout LinkwayConfiguration) -> Void) {
        router.updateConfiguration(change)
    }

    func binding<Value>(to keyPath: WritableKeyPath<LinkwayConfiguration, Value>) -> Binding<Value> {
        Binding(get: { self.configuration[keyPath: keyPath] }, set: { value in
            self.update { $0[keyPath: keyPath] = value }
        })
    }

    func destinations(kind: DestinationKind) -> [Destination] {
        func rank(_ id: DestinationID) -> (Int, Int) {
            if let index = configuration.favoriteDestinations.firstIndex(of: id) { return (0, index) }
            if let index = configuration.destinationOrder.firstIndex(of: id) { return (1, index) }
            return (2, 0)
        }
        return pickerEntries.enumerated().filter { $0.element.kind == kind }.sorted {
            let left = rank($0.element.id), right = rank($1.element.id)
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }

    func moveDestinations(kind: DestinationKind, from offsets: IndexSet, to index: Int) {
        var entries = destinations(kind: kind)
        entries.move(fromOffsets: offsets, toOffset: index)
        let ids = entries.map(\.id)
        let kindIDs = Set(pickerEntries.filter { $0.kind == kind }.map(\.id))
            .union(ruleTargets.filter { $0.kind == kind }.map(\.id))
        update { config in
            config.destinationOrder.removeAll { kindIDs.contains($0) }
            config.destinationOrder.append(contentsOf: ids)
            // Favorites have their own ordering in the picker.
            let favorites = Set(config.favoriteDestinations)
            let reorderedFavorites = ids.filter { favorites.contains($0) }
            var iterator = reorderedFavorites.makeIterator()
            config.favoriteDestinations = config.favoriteDestinations.map {
                kindIDs.contains($0) ? (iterator.next() ?? $0) : $0
            }
        }
    }

    func deleteRules(_ ids: Set<UUID>) {
        update { $0.rules.removeAll { ids.contains($0.id) } }
    }

    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !loginOperationInProgress else { return }
        loginError = nil
        loginOperationInProgress = true
        Task {
            defer { loginOperationInProgress = false }
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
            } catch { loginError = error.localizedDescription }
            refreshLoginStatus()
        }
    }

    var loginStatusText: String {
        switch loginStatus {
        case .enabled: "Linkway launches when you log in."
        case .notRegistered: "Launch at login is off."
        case .requiresApproval: "Approval is required in System Settings → Login Items."
        case .notFound: "Login service unavailable. Run Linkway from its installed app bundle."
        @unknown default: "Login service status is unknown."
        }
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileOperationInProgress = true
        Task {
            defer { fileOperationInProgress = false }
            do { try await router.importConfiguration(from: url) }
            catch { fileError = error.localizedDescription }
        }
    }

    func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Linkway.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileOperationInProgress = true
        Task {
            defer { fileOperationInProgress = false }
            do { try await router.exportConfiguration(to: url) }
            catch { fileError = error.localizedDescription }
        }
    }

    func targetName(_ id: DestinationID) -> String {
        router.destination(for: id)?.displayName ?? "Unavailable: \(id.rawValue)"
    }
}
