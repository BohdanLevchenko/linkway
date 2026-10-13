import AppKit
import Carbon
import LinkwayCore
import os

@MainActor
final class LinkIngress: NSObject {
    var onLink: ((IncomingLink) -> Void)? {
        didSet { drain() }
    }

    var forcePickerModifier: NSEvent.ModifierFlags? = .option

    /// Modifiers are kept raw so the configured force-picker key applies even to links that
    /// arrive before the configuration has loaded.
    private struct Arrival {
        let url: URL
        let receivedAt: Date
        let senderBundleID: String?
        let modifiers: NSEvent.ModifierFlags
    }

    private var pending: [Arrival] = []
    private var isDraining = false
    private let logger = Logger(subsystem: "io.github.bohdanlevchenko.linkway", category: "ingress")

    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value), url.scheme != nil else {
            logger.error("Received an invalid URL event")
            return
        }
        let senderBundleID = event.attributeDescriptor(forKeyword: keySenderPIDAttr)
            .flatMap { NSRunningApplication(processIdentifier: $0.int32Value)?.bundleIdentifier }
        receive(url, senderBundleID: senderBundleID)
    }

    func receive(_ url: URL, senderBundleID: String? = nil) {
        pending.append(Arrival(
            url: resolveWebLocation(url),
            receivedAt: Date(),
            senderBundleID: senderBundleID,
            modifiers: NSEvent.modifierFlags
        ))
        drain()
    }

    private func resolveWebLocation(_ url: URL) -> URL {
        guard url.isFileURL, url.pathExtension.lowercased() == "webloc" else { return url }
        do {
            let data = try Data(contentsOf: url)
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard let dictionary = plist as? [String: Any],
                  let value = dictionary["URL"] as? String,
                  let target = URL(string: value), target.scheme != nil else {
                logger.error("Web location has no valid URL; keeping the original file")
                return url
            }
            return target
        } catch {
            logger.error("Cannot read web location: \(error.localizedDescription, privacy: .public)")
            return url
        }
    }

    private func drain() {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while let onLink, !pending.isEmpty {
            let arrival = pending.removeFirst()
            onLink(IncomingLink(
                url: arrival.url,
                receivedAt: arrival.receivedAt,
                senderBundleID: arrival.senderBundleID,
                forcePicker: forcePickerModifier.map { arrival.modifiers.contains($0) } ?? false
            ))
        }
    }
}
