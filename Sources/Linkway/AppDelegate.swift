import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NSLog("Linkway received %@", url.absoluteString)
        }
    }
}
