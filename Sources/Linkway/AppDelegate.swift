import AppKit
import LinkwayCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ingress = LinkIngress()

    func applicationWillFinishLaunching(_ notification: Notification) {
        ingress.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ingress.onLink = { link in
            NSLog("Linkway received %@", link.url.absoluteString)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            ingress.receive(url)
        }
    }
}
