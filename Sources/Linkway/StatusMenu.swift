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
    private var isSettingDefault = false

    init(ingress: LinkIngress, router: LinkRouter) {
        self.ingress = ingress
        self.router = router
        super.init()

        statusItem.button?.title = "Linkway"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(item("Open Link from Clipboard", action: #selector(openClipboard)))
        defaultBrowserItem.isEnabled = false
        menu.addItem(defaultBrowserItem)
        menu.addItem(item("Make Linkway Default Browser...", action: #selector(makeDefaultBrowser)))
        menu.addItem(.separator())
        rememberedItem.submenu = NSMenu()
        menu.addItem(rememberedItem)
        menu.addItem(.separator())
        menu.addItem(item("Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
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

    private func refreshDefaultBrowser() {
        let browserURL = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "https://example.com")!
        )
        let status: String
        if let browserURL {
            if browserURL.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath() {
                status = "Linkway"
            } else {
                status = FileManager.default.displayName(atPath: browserURL.path)
            }
        } else {
            status = "Unknown"
        }
        defaultBrowserItem.title = "Default Browser: \(status)"
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
        guard !isSettingDefault else { return }
        isSettingDefault = true
        Task {
            defer {
                isSettingDefault = false
                refreshDefaultBrowser()
            }
            // Confirming the system prompt for one web scheme switches both, and asking again for a scheme we
            // already own is rejected, so request only what is still missing and judge by the resulting handlers.
            var failure: Error?
            for scheme in ["http", "https"] where !Self.isDefaultHandler(forScheme: scheme) {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(
                        at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme
                    )
                } catch {
                    failure = error
                    break
                }
            }
            guard ["http", "https"].allSatisfy(Self.isDefaultHandler(forScheme:)) else {
                showAlert(title: "Default Browser Unchanged",
                          message: failure?.localizedDescription ?? "macOS kept the current default browser.")
                return
            }
        }
    }

    private static func isDefaultHandler(forScheme scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return handler.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
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
