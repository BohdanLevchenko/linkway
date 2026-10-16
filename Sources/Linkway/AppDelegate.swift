import AppKit
import LinkwayCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ingress = LinkIngress()
    private let router = LinkRouter(
        registry: DestinationRegistry(),
        store: ConfigurationStore(fileURL: ConfigurationStore.defaultFileURL)
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        ingress.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        router.onConfigurationLoaded = { [ingress, router] configuration in
            ingress.forcePickerModifier = configuration.forcePickerModifier.eventFlag
            ingress.onLink = { link in router.handle(link) }
        }
        router.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            ingress.receive(url)
        }
    }
}

private extension ModifierKey {
    var eventFlag: NSEvent.ModifierFlags? {
        switch self {
        case .option: .option
        case .command: .command
        case .control: .control
        case .shift: .shift
        case .none: nil
        }
    }
}
