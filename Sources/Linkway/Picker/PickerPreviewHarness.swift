#if DEBUG
import AppKit
import LinkwayCore

extension PickerController {
    private static let sampleController = PickerController()

    static func debugPresentSample() {
        let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
            ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        let destinations = [
            Destination(id: DestinationID(bundleID: "sample.safari"), kind: .browser,
                        appName: "Safari", profileName: nil, appURL: safari,
                        supportsPrivateWindow: false),
            Destination(id: DestinationID(bundleID: "sample.browser", profileKey: "personal"), kind: .browser,
                        appName: "Sample Browser", profileName: "Personal", appURL: safari,
                        supportsPrivateWindow: true),
            Destination(id: DestinationID(bundleID: "sample.browser", profileKey: "work"), kind: .browser,
                        appName: "Sample Browser", profileName: "Work", appURL: safari,
                        supportsPrivateWindow: true),
        ]
        guard let url = URL(string: "https://example.com/articles/a-link-to-preview?source=picker") else { return }
        sampleController.present(
            link: IncomingLink(url: url, receivedAt: Date(), senderBundleID: nil, forcePicker: true),
            destinations: destinations,
            rememberTarget: "example.com",
            iconProvider: { NSWorkspace.shared.icon(forFile: $0.appURL.path) },
            completion: { _ in }
        )
    }
}
#endif
