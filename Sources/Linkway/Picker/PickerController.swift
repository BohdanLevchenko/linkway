import AppKit
import LinkwayCore
import SwiftUI
import os

@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    private struct Request {
        let link: IncomingLink
        let processing: CleanResult?
        let expanded: Bool
        var destinations: [Destination]
        let destinationProvider: (@MainActor (IncomingLink) -> [Destination])?
        let rememberTargets: [RememberTarget]
        let style: LinkwayCore.PickerStyle
        let avatarProvider: @MainActor (Destination) -> NSImage?
        let onOpenPreferences: @MainActor () -> Void
        let iconProvider: @MainActor (Destination) -> NSImage
        let completion: @MainActor (PickerResult) -> Void
    }

    private var queue: [Request] = []
    private var current: Request?
    private var model: PickerModel?
    private var panel: PickerPanel?
    private var eventMonitor: Any?
    private var previousApplication: NSRunningApplication?
    private var transitioning = false
    private var activationWaitID: UUID?
    private var activationTimeout: Task<Void, Never>?
    private var shownAt: TimeInterval = 0
    private var retriedKey = false
    /// Longer after an activation wait timed out: the launched app may still steal focus late.
    private var focusGrace: TimeInterval = 0.3
    private let logger = Logger(subsystem: "io.github.bohdanlevchenko.linkway", category: "picker")

    func present(
        link: IncomingLink,
        processing: CleanResult? = nil, expanded: Bool = false,
        destinations: [Destination],
        destinationProvider: (@MainActor (IncomingLink) -> [Destination])? = nil,
        rememberTargets: [RememberTarget],
        style: LinkwayCore.PickerStyle = .tiles,
        avatarProvider: @escaping @MainActor (Destination) -> NSImage? = { _ in nil },
        onOpenPreferences: @escaping @MainActor () -> Void = {},
        iconProvider: @escaping @MainActor (Destination) -> NSImage,
        completion: @escaping @MainActor (PickerResult) -> Void
    ) {
        queue.append(Request(link: link, processing: processing, expanded: expanded, destinations: destinations, destinationProvider: destinationProvider, rememberTargets: rememberTargets,
                             style: style, avatarProvider: avatarProvider, onOpenPreferences: onOpenPreferences,
                             iconProvider: iconProvider, completion: completion))
        showNext()
    }

    func updateDestinations(_ destinations: (IncomingLink) -> [Destination]) {
        if let link = model?.link {
            let updated = destinations(link)
            model?.updateDestinations(updated)
            current?.destinations = updated
        }
        for index in queue.indices {
            let request = queue[index]
            let link = IncomingLink(url: request.processing?.url ?? request.link.url, receivedAt: request.link.receivedAt,
                                    senderBundleID: request.link.senderBundleID, forcePicker: request.link.forcePicker,
                                    mode: request.link.mode)
            queue[index].destinations = destinations(link)
        }
    }

    private func showNext() {
        guard current == nil, !transitioning, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        current = request
        previousApplication = NSWorkspace.shared.frontmostApplication
        let model = PickerModel(link: request.link, destinations: request.destinations, rememberTargets: request.rememberTargets, style: request.style, processing: request.processing, expanded: request.expanded)
        model.onResult = { [weak self] result in self?.finish(result) }
        model.onActiveLinkChange = { [weak model] link in
            if let provider = request.destinationProvider { model?.updateDestinations(provider(link)) }
        }
        self.model = model
        let panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.title = "Open Link"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = TileMetrics.cornerRadius
        material.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: PickerRootView(
            model: model, iconProvider: request.iconProvider, avatarProvider: request.avatarProvider,
            onOpenPreferences: { [weak self] in
                self?.finish(.dismissed)
                request.onOpenPreferences()
            }
        ))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: material.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        panel.contentView = material
        model.onPresentationChange = { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.place(panel)
        }
        self.panel = panel
        place(panel)
        installEventMonitor()
        model.shiftHeld = NSEvent.modifierFlags.contains(.shift)
        shownAt = ProcessInfo.processInfo.systemUptime
        retriedKey = false
        panel.makeKeyAndOrderFront(nil)
        logger.info("Shown with \(request.destinations.count, privacy: .public) destinations; key=\(panel.isKeyWindow, privacy: .public)")
    }

    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let desired = model?.presentation == .tiles
            ? TileMetrics.panelSize(tileCount: model?.tiles.count ?? 0) : NSSize(width: 420, height: 480)
        let size = NSSize(width: min(desired.width, visible.width), height: min(desired.height, visible.height))
        let origin = NSPoint(
            x: min(max(visible.midX - size.width / 2, visible.minX), visible.maxX - size.width),
            y: min(max(visible.midY - size.height / 2 + 55, visible.minY), visible.maxY - size.height)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isKeyWindow,
                      let model = self.model else { return false }
                model.shiftHeld = event.modifierFlags.contains(.shift)
                guard event.type == .keyDown, event.window === panel else { return false }
                return self.handleKey(event, model: model)
            }
            return handled ? nil : event
        }
    }

    func handleKey(_ event: NSEvent, model: PickerModel) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains([.command, .shift]), event.charactersIgnoringModifiers?.lowercased() == "o" {
            model.toggleOriginal()
            return true
        }
        if model.presentation == .tiles {
            guard modifiers.intersection([.control, .option]).isEmpty else { return false }
            if let characters = event.characters(byApplyingModifiers: []),
               let number = Int(characters), (1...9).contains(number) {
                model.openTile(number - 1)
                return true
            }
            if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a",
               model.tiles.contains(.allOptions) {
                model.showAllOptions()
                return true
            }
            if !modifiers.contains(.command) {
                switch event.keyCode {
                case 123, 126: model.moveSelection(by: -1); return true
                case 124, 125: model.moveSelection(by: 1); return true
                default: break
                }
            }
        }
        if model.presentation == .list, modifiers.intersection([.command, .control, .option]).isEmpty,
           let characters = event.characters(byApplyingModifiers: []),
           characters.count == 1, let number = Int(characters),
           (1...9).contains(number) || (number == 0 && model.prefix != nil) {
            return model.pickDigit(number)
        }
        model.clearPrefix()
        if modifiers.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": model.copyLink()
            case "r" where !model.rememberTargets.isEmpty: model.cycleRememberScope()
            default: return false
            }
            return true
        }
        guard modifiers.intersection([.control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 53: finish(.dismissed)
        case 125: model.moveSelection(by: 1)
        case 126: model.moveSelection(by: -1)
        case 36, 76: model.openSelected()
        default: return false
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        if model?.sharing == true { return }
        if ProcessInfo.processInfo.systemUptime - shownAt < focusGrace {
            if !retriedKey {
                retriedKey = true
                Task { @MainActor [weak self, weak window] in
                    await Task.yield()
                    guard let self, let window, window === self.panel else { return }
                    window.makeKeyAndOrderFront(nil)
                }
            }
            return
        }
        finish(.dismissed, explicitUserResult: false)
    }

    private func finish(_ result: PickerResult, explicitUserResult: Bool = true) {
        guard let request = current else { return }
        if !explicitUserResult {
            logger.debug("Completing request without explicit picker result: click-away after focus grace period")
        }
        logger.info("Picker finished")
        transitioning = true
        current = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        model?.clearPrefix()
        model = nil
        if case .open = result {
            waitForActivation(timeout: 1.5)
        } else {
            waitForActivation(timeout: 0.5)
            previousApplication?.activate(options: [])
        }
        previousApplication = nil
        request.completion(result)
    }

    private func waitForActivation(timeout: Double) {
        let id = UUID()
        activationWaitID = id
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        activationTimeout = Task { @MainActor [self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
            } catch {
                return
            }
            endActivationWait(id, timedOut: true)
        }
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let id = activationWaitID else { return }
        endActivationWait(id, timedOut: false)
    }

    private func endActivationWait(_ id: UUID, timedOut: Bool) {
        guard activationWaitID == id else { return }
        focusGrace = timedOut ? 3 : 0.3
        activationWaitID = nil
        NSWorkspace.shared.notificationCenter.removeObserver(
            self, name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        activationTimeout?.cancel()
        activationTimeout = nil
        Task { @MainActor [self] in
            await Task.yield()
            transitioning = false
            showNext()
        }
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
