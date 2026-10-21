import AppKit
import SwiftUI

@MainActor
final class ResolvingLinkController {
    private var panel: NSPanel?
    private var monitor: Any?
    func show(url: URL, useOriginal: @escaping @MainActor () -> Void) {
        close()
        let panel = ResolvingPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 116),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 10) {
            HStack { ProgressView().controlSize(.small); Text("Resolving link…").font(.headline) }
            Text(url.absoluteString).font(.caption).lineLimit(1).truncationMode(.middle).help(url.absoluteString)
            Button("Use Original", action: useOriginal).keyboardShortcut(.cancelAction)
        }.padding(16).frame(width: 360, height: 116, alignment: .leading))
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 180, y: frame.midY - 58 + 55))
        }
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            let handled = MainActor.assumeIsolated {
                if event.keyCode == 53, event.window === panel { useOriginal(); return true }
                return false
            }
            return handled ? nil : event
        }
        panel.makeKeyAndOrderFront(nil)
    }
    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
private final class ResolvingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
