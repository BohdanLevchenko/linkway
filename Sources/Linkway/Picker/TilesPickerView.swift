import AppKit
import LinkwayCore
import SwiftUI

enum TileMetrics {
    static let capacity = 6
    static let width: CGFloat = 120
    static let icon: CGFloat = 72
    static let badge: CGFloat = 28
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 20
    static let cornerRadius: CGFloat = 16
    static let headerHeight: CGFloat = 42
    static let tileHeight: CGFloat = 154
    static let footerHeight: CGFloat = 58
    static let dividerHeight: CGFloat = 1

    static func panelSize(tileCount: Int) -> NSSize {
        NSSize(width: max(560, CGFloat(tileCount) * width + CGFloat(max(0, tileCount - 1)) * spacing + padding * 2),
               height: headerHeight + tileHeight + padding * 2 + footerHeight + dividerHeight)
    }
}

struct PickerRootView: View {
    @ObservedObject var model: PickerModel
    let iconProvider: @MainActor (Destination) -> NSImage
    let avatarProvider: @MainActor (Destination) -> NSImage?
    let onOpenPreferences: @MainActor () -> Void

    var body: some View {
        switch model.presentation {
        case .list: PickerView(model: model, iconProvider: iconProvider)
        case .tiles:
            TilesPickerView(model: model, iconProvider: iconProvider, avatarProvider: avatarProvider,
                            onOpenPreferences: onOpenPreferences)
        }
    }
}

private struct TilesPickerView: View {
    @ObservedObject var model: PickerModel
    let iconProvider: @MainActor (Destination) -> NSImage
    let avatarProvider: @MainActor (Destination) -> NSImage?
    let onOpenPreferences: @MainActor () -> Void
    @State private var hoveredTile: Int?

    var body: some View {
        VStack(spacing: 0) {
            Text(model.tileTitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 48)
                .frame(maxWidth: .infinity)
                .frame(height: TileMetrics.headerHeight)
                .overlay(alignment: .leading) {
                    Button { model.onResult?(.dismissed) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss picker")
                    .padding(.leading, TileMetrics.padding)
                }
                .overlay(alignment: .trailing) {
                    ProcessingIndicator(model: model).padding(.trailing, TileMetrics.padding)
                }
            HStack(spacing: TileMetrics.spacing) {
                ForEach(Array(model.tiles.enumerated()), id: \.offset) { index, tile in
                    tileButton(tile, index: index)
                }
                if model.tiles.isEmpty {
                    Text("No destinations found").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: TileMetrics.tileHeight)
            .padding(TileMetrics.padding)
            Divider().frame(height: TileMetrics.dividerHeight)
            footer.frame(height: TileMetrics.footerHeight)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TileMetrics.cornerRadius).strokeBorder(.separator, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func tileButton(_ tile: PickerTile, index: Int) -> some View {
        let name: String
        let label: String
        let shortcut: String
        let dimmed: Bool
        switch tile {
        case .destination(let destination):
            name = destination.profileName ?? destination.appName
            label = destination.profileName.map { "\($0), \(destination.appName) profile" } ?? destination.appName
            shortcut = "⌘\(index + 1)"
            dimmed = model.shiftHeld && !destination.supportsPrivateWindow
        case .allOptions:
            name = "All Options"
            label = name
            shortcut = "⌘A"
            dimmed = false
        }
        return Button { model.openTile(index) } label: {
            VStack(spacing: 7) {
                tileIcon(tile)
                    .frame(width: TileMetrics.icon, height: TileMetrics.icon)
                    .padding(.bottom, 5)
                Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    .truncationMode(.tail)
                Text(shortcut).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: TileMetrics.width, height: TileMetrics.tileHeight)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(model.selectedTile == index || hoveredTile == index
                        ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .opacity(dimmed ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hoveredTile = $0 ? index : nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Open with \(shortcut)")
        .accessibilityValue(model.selectedTile == index ? "Selected" : "")
    }

    @ViewBuilder private func tileIcon(_ tile: PickerTile) -> some View {
        switch tile {
        case .allOptions:
            RoundedRectangle(cornerRadius: 17).fill(.quaternary)
                .overlay { Image(systemName: "ellipsis").font(.system(size: 30, weight: .medium)) }
        case .destination(let destination):
            Group {
                if let name = destination.profileName {
                    ZStack {
                        Circle().fill(avatarColor(destination, name: name))
                        if let avatar = avatarProvider(destination) {
                            Image(nsImage: avatar).resizable().scaledToFill()
                        } else {
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 30, weight: .medium)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: TileMetrics.icon, height: TileMetrics.icon)
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(nsImage: iconProvider(destination)).resizable().scaledToFit()
                            .frame(width: TileMetrics.badge, height: TileMetrics.badge)
                            .offset(x: 5, y: 5)
                    }
                } else {
                    Image(nsImage: iconProvider(destination)).resizable().scaledToFit()
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.shiftHeld && destination.supportsPrivateWindow {
                    Image(systemName: "eye.slash.fill").font(.caption)
                        .padding(5).background(.regularMaterial, in: Capsule())
                        .help("Private window")
                }
            }
        }
    }

    private func avatarColor(_ destination: Destination, name: String) -> Color {
        if let argb = destination.highlightColorARGB {
            let bits = UInt32(truncatingIfNeeded: argb)
            return Color(red: Double((bits >> 16) & 255) / 255,
                         green: Double((bits >> 8) & 255) / 255, blue: Double(bits & 255) / 255)
        }
        let hash = name.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.65)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if let first = model.rememberTargets.first {
                HStack(spacing: 4) {
                    Toggle("Remember this choice for", isOn: Binding(
                        get: { model.rememberIndex != nil },
                        set: { model.rememberIndex = $0 ? 0 : nil }
                    )).toggleStyle(.checkbox).fixedSize()
                    if model.rememberTargets.count > 1 {
                        Menu {
                            ForEach(model.rememberTargets.indices, id: \.self) { index in
                                Button(model.rememberTargets[index].label) { model.rememberIndex = index }
                            }
                        } label: {
                            Text(model.currentTarget?.label ?? first.label)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Remember scope")
                    } else {
                        Text(first.label).lineLimit(1).truncationMode(.middle)
                    }
                }.font(.system(size: 12))
            }
            Spacer(minLength: 8)
            footerButton("Copy link", symbol: "doc.on.doc", action: model.copyLink)
            ShareLinkButton(model: model).frame(width: 24, height: 28)
            footerButton("Settings", symbol: "gearshape", action: onOpenPreferences)
        }
        .padding(.horizontal, TileMetrics.padding)
    }

    private func footerButton(_ label: String, symbol: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 18)).frame(width: 24, height: 28) }
            .buttonStyle(.plain).focusable(false).help(label).accessibilityLabel(label)
    }
}

private struct ShareLinkButton: NSViewRepresentable {
    let model: PickerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSButton {
        let symbol = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share link")?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular)) ?? NSImage()
        let button = NSButton(image: symbol, target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.isBordered = false
        button.refusesFirstResponder = true
        button.contentTintColor = .labelColor
        button.toolTip = "Share link"
        button.setAccessibilityLabel("Share link")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}

    @MainActor final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        let model: PickerModel
        private var picker: NSSharingServicePicker?
        private weak var window: NSWindow?
        init(model: PickerModel) { self.model = model }

        @objc func share(_ sender: NSButton) {
            window = sender.window
            model.sharing = true
            let picker = NSSharingServicePicker(items: [model.link.url])
            self.picker = picker
            picker.delegate = self
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }

        nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            let chosen = service != nil
            MainActor.assumeIsolated {
                model.sharing = false
                if chosen { model.onResult?(.dismissed) }
                else { window?.makeKeyAndOrderFront(nil) }
                picker = nil
            }
        }
    }
}
