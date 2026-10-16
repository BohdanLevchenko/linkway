import AppKit

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let ingress: LinkIngress
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let defaultBrowserItem = NSMenuItem()
    private var isSettingDefault = false

    init(ingress: LinkIngress) {
        self.ingress = ingress
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
        menu.addItem(item("Quit Linkway", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshDefaultBrowser()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshDefaultBrowser()
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
            do {
                for scheme in ["http", "https"] {
                    try await NSWorkspace.shared.setDefaultApplication(
                        at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme
                    )
                }
            } catch {
                showAlert(title: "Could Not Set Default Browser", message: error.localizedDescription)
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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
