import AppKit
import LinkwayCore
import SwiftUI

@MainActor
final class PickerModel: ObservableObject {
    let link: IncomingLink
    @Published private(set) var destinations: [Destination]
    @Published var selectedID: DestinationID?
    @Published var shiftHeld = false
    var onResult: (@MainActor (PickerResult) -> Void)?

    init(link: IncomingLink, destinations: [Destination]) {
        self.link = link
        self.destinations = destinations
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
        self.destinations = destinations
        if !destinations.contains(where: { $0.id == selectedID }) {
            selectedID = destinations.first?.id
        }
    }

    func moveSelection(by offset: Int) {
        guard !destinations.isEmpty else { return }
        let index = destinations.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = destinations[min(max(index + offset, 0), destinations.count - 1)].id
    }

    func openSelected() {
        guard let destination = destinations.first(where: { $0.id == selectedID }) else { return }
        open(destination)
    }

    func open(_ destination: Destination, privateWindow: Bool? = nil) {
        onResult?(.open(LaunchRequest(
            url: link.url, destination: destination.id,
            privateWindow: (privateWindow ?? shiftHeld) && destination.supportsPrivateWindow
        )))
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
            HStack {
                Text("↑↓ select · ↩ open · esc dismiss")
                Spacer()
                Button(action: model.copyLink) {
                    Text("Copy Link ⌘C")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy Link")
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
                    ForEach(Array(model.destinations.enumerated()), id: \.element.id) { index, destination in
                        row(destination, shortcut: index < 9 ? index + 1 : nil)
                            .id(destination.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func row(_ destination: Destination, shortcut: Int?) -> some View {
        let selected = destination.id == model.selectedID
        return Button {
            model.open(destination, privateWindow: NSEvent.modifierFlags.contains(.shift))
        } label: {
            HStack(spacing: 12) {
                Image(nsImage: iconProvider(destination))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.appName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let profile = destination.profileName {
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
                if let shortcut {
                    Text("\(shortcut)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.horizontal, 12)
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
        .accessibilityLabel(destination.displayName + (shortcut.map { ", shortcut \($0)" } ?? ""))
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityHint(destination.supportsPrivateWindow ? "Hold Shift to open in a private window" : "Open link")
    }
}
