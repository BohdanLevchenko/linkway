import AppKit
import LinkwayCore

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    var onOpenPreferences: (() -> Void)?
    private let ingress: LinkIngress
    private let router: LinkRouter
    private let rememberedItem = NSMenuItem(title: "Remembered Choices", action: nil, keyEquivalent: "")
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let defaultBrowserItem = NSMenuItem()
    private lazy var makeDefaultItem = item("Make Linkway Default Browser…", action: #selector(makeDefaultBrowser))
    private let defaultBrowserSeparator = NSMenuItem.separator()
    private let defaultHandlers: DefaultHandlers

    init(ingress: LinkIngress, router: LinkRouter, defaultHandlers: DefaultHandlers) {
        self.defaultHandlers = defaultHandlers
        self.ingress = ingress
        self.router = router
        super.init()

        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Linkway")
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = "Linkway"
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(item("Open Link from Clipboard", action: #selector(openClipboard)))
        defaultBrowserItem.isEnabled = false
        menu.addItem(defaultBrowserItem)
        menu.addItem(makeDefaultItem)
        menu.addItem(defaultBrowserSeparator)
        rememberedItem.submenu = NSMenu()
        menu.addItem(rememberedItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(item("Quit Linkway", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshDefaultBrowser()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshDefaultBrowser()
        refreshRemembered()
    }

    private func refreshRemembered() {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let rules = router.rememberedRules
        if rules.isEmpty {
            let empty = NSMenuItem(title: "None yet. Tick \"Remember\" in the picker.", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Click to forget", action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
        }
        for rule in rules {
            let entry = item("\(rule.name) → \(router.targetName(for: rule.action))", action: #selector(forgetRemembered(_:)))
            entry.representedObject = rule.id
            submenu.addItem(entry)
        }
        rememberedItem.submenu = submenu
    }

    @objc private func forgetRemembered(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        router.forgetRule(id: id)
    }

    private func item(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    /// Only offered while another app is the default browser.
    private func refreshDefaultBrowser() {
        let isDefault = defaultHandlers.isDefault(.browser)
        defaultBrowserItem.title = "Default Browser: \(defaultHandlers.currentHandlerName(.browser))"
        defaultBrowserItem.isHidden = isDefault
        makeDefaultItem.isHidden = isDefault
        defaultBrowserSeparator.isHidden = isDefault
    }

    @objc private func openClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string),
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            showAlert(title: "No Link on Clipboard", message: "Copy a full URL and try again.")
            return
        }
        ingress.receive(url)
    }

    @objc private func makeDefaultBrowser() {
        Task {
            let outcome = await defaultHandlers.makeDefault(.browser)
            refreshDefaultBrowser()
            if case .failed(let message) = outcome {
                showAlert(title: "Could Not Set Default Browser", message: message)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openPreferences() {
        onOpenPreferences?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
