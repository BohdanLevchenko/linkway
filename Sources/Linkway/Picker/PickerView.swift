import AppKit
import LinkwayCore
import SwiftUI

enum PickerShortcut: Equatable, Sendable {
    case group(Int)
    case member(group: Int, member: Int)

    var label: String {
        switch self {
        case .group(let number): return "\(number)"
        case .member(let group, let member): return "\(group).\(member)"
        }
    }
}

enum PickerRow: Identifiable, Sendable {
    enum ID: Hashable {
        case header(String)
        case destination(DestinationID)
    }

    case header(first: Destination, shortcut: PickerShortcut?)
    case destination(Destination, shortcut: PickerShortcut?, indented: Bool)

    var id: ID {
        switch self {
        case .header(let first, _): return .header(first.id.bundleID)
        case .destination(let destination, _, _): return .destination(destination.id)
        }
    }

    var destination: Destination? {
        if case .destination(let destination, _, _) = self { return destination }
        return nil
    }
}

/// Preserves the first appearance of each app and the incoming order of its profiles.
enum PickerLayout {
    static func rows(for destinations: [Destination]) -> [PickerRow] {
        var groups: [[Destination]] = []
        var groupIndices: [String: Int] = [:]
        for destination in destinations {
            if let index = groupIndices[destination.id.bundleID] {
                groups[index].append(destination)
            } else {
                groupIndices[destination.id.bundleID] = groups.count
                groups.append([destination])
            }
        }
        return groups.enumerated().flatMap { index, members -> [PickerRow] in
            let number = index + 1
            let shortcut: PickerShortcut? = number <= 9 ? .group(number) : nil
            guard let first = members.first else { return [] }
            if members.count == 1 {
                return [.destination(first, shortcut: shortcut, indented: false)]
            }
            return [.header(first: first, shortcut: shortcut)] + members.enumerated().map { memberIndex, member in
                let memberShortcut: PickerShortcut? = number <= 9 && memberIndex < 9
                    ? .member(group: number, member: memberIndex + 1) : nil
                return .destination(member, shortcut: memberShortcut, indented: true)
            }
        }
    }
}

enum PickerPresentation { case tiles, list }

enum PickerTile: Hashable {
    case destination(Destination)
    case allOptions
}

@MainActor
final class PickerModel: ObservableObject {
    @Published private(set) var presentation: PickerPresentation
    @Published var selectedTile = 0
    var onPresentationChange: (() -> Void)?
    var sharing = false
    var tiles: [PickerTile] {
        let count = destinations.count > TileMetrics.capacity ? TileMetrics.capacity - 1 : destinations.count
        return destinations.prefix(count).map(PickerTile.destination)
            + (destinations.count > TileMetrics.capacity ? [.allOptions] : [])
    }

    func showAllOptions() {
        guard tiles.contains(.allOptions) else { return }
        clearPrefix()
        presentation = .list
        onPresentationChange?()
    }

    func openTile(_ index: Int) {
        guard tiles.indices.contains(index) else { return }
        switch tiles[index] {
        case .destination(let destination): open(destination)
        case .allOptions: showAllOptions()
        }
    }

    var tileTitle: String {
        switch link.kind {
        case .mail: return "mailto: " + (link.url.path.removingPercentEncoding ?? link.url.path)
        case .localFile: return link.url.lastPathComponent
        case .web: return (link.url.host ?? "") + link.url.path
        case .custom: return link.url.absoluteString
        }
    }

    let link: IncomingLink
    @Published private(set) var destinations: [Destination]
    @Published private(set) var rows: [PickerRow]
    let rememberTargets: [RememberTarget]
    @Published var rememberIndex: Int? = nil
    @Published private(set) var prefix: PickerShortcut?
    private var prefixTimeout: Task<Void, Never>?
    @Published var selectedID: DestinationID?
    @Published var shiftHeld = false
    var onResult: (@MainActor (PickerResult) -> Void)?

    init(link: IncomingLink, destinations: [Destination], rememberTargets: [RememberTarget] = [], style: LinkwayCore.PickerStyle = .list) {
        presentation = style == .tiles ? .tiles : .list
        self.link = link
        self.destinations = destinations
        rows = PickerLayout.rows(for: destinations)
        self.rememberTargets = rememberTargets
        selectedID = destinations.first?.id
    }

    var title: String {
        switch link.kind {
        case .mail:
            let recipient = link.url.path.removingPercentEncoding ?? link.url.path
            return recipient.isEmpty ? "Email link" : recipient
        case .localFile: return link.url.lastPathComponent
        case .web, .custom: return link.url.host ?? link.url.absoluteString
        }
    }

    func updateDestinations(_ destinations: [Destination]) {
        clearPrefix()
        selectedTile = 0
        self.destinations = destinations
        rows = PickerLayout.rows(for: destinations)
        if !destinations.contains(where: { $0.id == selectedID }) {
            selectedID = destinations.first?.id
        }
        onPresentationChange?()
    }

    private var selectableDestinations: [Destination] { rows.compactMap(\.destination) }

    func moveSelection(by offset: Int) {
        if presentation == .tiles {
            selectedTile = min(max(selectedTile + offset, 0), max(tiles.count - 1, 0))
            return
        }
        let destinations = selectableDestinations
        guard !destinations.isEmpty else { return }
        let index = destinations.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = destinations[min(max(index + offset, 0), destinations.count - 1)].id
    }

    func openSelected() {
        if presentation == .tiles { openTile(selectedTile); return }
        guard let destination = destinations.first(where: { $0.id == selectedID }) else { return }
        open(destination)
    }

    var currentTarget: RememberTarget? {
        rememberIndex.map { rememberTargets[$0] }
    }

    func cycleRememberScope() {
        guard !rememberTargets.isEmpty else { return }
        let next = rememberIndex.map { $0 + 1 } ?? 0
        rememberIndex = next < rememberTargets.count ? next : nil
    }

    func open(_ destination: Destination, privateWindow: Bool? = nil) {
        onResult?(.open(LaunchRequest(
            url: link.url, destination: destination.id,
            privateWindow: (privateWindow ?? shiftHeld) && destination.supportsPrivateWindow
        ), remember: currentTarget))
    }

    func clearPrefix() {
        prefixTimeout?.cancel()
        prefixTimeout = nil
        prefix = nil
    }

    func selectGroup(_ first: Destination) {
        clearPrefix()
        selectedID = first.id
    }

    /// Returns true for a recognized group or any second digit, including an invalid member.
    func pickDigit(_ number: Int) -> Bool {
        if case .group(let group) = prefix {
            clearPrefix()
            if let destination = rows.first(where: {
                if case .destination(_, .member(let rowGroup, let member), _) = $0 {
                    return rowGroup == group && member == number
                }
                return false
            })?.destination {
                open(destination)
            }
            return true
        }
        for row in rows {
            switch row {
            case .destination(let destination, .group(let group), _) where group == number:
                open(destination)
                return true
            case .header(let first, .group(let group)) where group == number:
                selectedID = first.id
                prefix = .group(number)
                prefixTimeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(1.5)) }
                    catch { return }
                    self?.clearPrefix()
                }
                return true
            default: continue
            }
        }
        return false
    }

    func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
        onResult?(.copied(link.url))
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel
    let iconProvider: @MainActor (Destination) -> NSImage
    @State private var showsFullURL = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)
            Divider()
            if model.destinations.isEmpty {
                VStack(spacing: 14) {
                    Text("No destinations found")
                        .font(.headline)
                    Button("Copy Link", action: model.copyLink)
                        .accessibilityLabel("Copy Link")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                destinationList
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let firstTarget = model.rememberTargets.first {
                    HStack(spacing: 6) {
                        Toggle("Remember for", isOn: Binding(
                            get: { model.rememberIndex != nil },
                            set: { model.rememberIndex = $0 ? 0 : nil }
                        ))
                            .toggleStyle(.checkbox)
                            .fixedSize()
                        if model.rememberTargets.count > 1 {
                            Picker("Remember scope", selection: Binding(
                                get: { model.rememberIndex ?? 0 },
                                set: { model.rememberIndex = $0 }
                            )) {
                                ForEach(model.rememberTargets.indices, id: \.self) { index in
                                    Text(model.rememberTargets[index].label).tag(index)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .controlSize(.small)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        } else {
                            Text(firstTarget.label)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text("⌘R")
                    }
                }
                HStack {
                    Text("↑↓ select · ↩ open · 1-9 pick · esc dismiss")
                    Spacer(minLength: 4)
                    Button(action: model.copyLink) {
                        Text("Copy Link ⌘C")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy Link")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open link in")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                Text(model.title)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showsFullURL.toggle()
                } label: {
                    Image(systemName: showsFullURL ? "chevron.up" : "chevron.down")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsFullURL ? "Hide full URL" : "Show full URL")
                .accessibilityValue(showsFullURL ? "Expanded" : "Collapsed")
            }
            if showsFullURL {
                ScrollView(.vertical) {
                    Text(model.link.url.absoluteString)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 8)
                }
                .frame(height: 64)
                .accessibilityLabel("Full URL")
            }
        }
    }

    private var destinationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.rows) { item in
                        switch item {
                        case .header(let first, let shortcut):
                            groupHeader(first, shortcut: shortcut)
                        case .destination(let destination, let shortcut, let indented):
                            row(destination, shortcut: shortcut, indented: indented)
                                .id(destination.id)
                        }
                    }
                }
                .padding(10)
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func shortcutBadge(_ shortcut: PickerShortcut, active: Bool = false) -> some View {
        Text(shortcut.label)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 4)
            .background(active ? Color.accentColor.opacity(0.18) : Color(nsColor: .quaternaryLabelColor).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
    }

    private func groupHeader(_ first: Destination, shortcut: PickerShortcut?) -> some View {
        Button { model.selectGroup(first) } label: {
            HStack(spacing: 12) {
                Image(nsImage: iconProvider(first))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text(first.appName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let shortcut { shortcutBadge(shortcut, active: model.prefix == shortcut) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(first.appName + (shortcut.map { ", shortcut \($0.label)" } ?? ""))
        .accessibilityValue(model.prefix == shortcut && shortcut != nil ? "Waiting for profile number" : "")
        .accessibilityHint("Select first profile")
    }

    private func row(_ destination: Destination, shortcut: PickerShortcut?, indented: Bool) -> some View {
        let selected = destination.id == model.selectedID
        return Button {
            model.open(destination, privateWindow: NSEvent.modifierFlags.contains(.shift))
        } label: {
            HStack(spacing: 12) {
                if !indented {
                    Image(nsImage: iconProvider(destination))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(indented ? (destination.profileName ?? destination.appName) : destination.appName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if !indented, let profile = destination.profileName {
                        Text(profile)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if model.shiftHeld && destination.supportsPrivateWindow {
                    Text("⇧ private")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let shortcut { shortcutBadge(shortcut) }
            }
            .padding(.leading, indented ? 56 : 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .background(selected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { model.selectedID = destination.id }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(destination.displayName + (shortcut.map { ", shortcut \($0.label)" } ?? ""))
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityHint(destination.supportsPrivateWindow ? "Hold Shift to open in a private window" : "Open link")
    }
}
