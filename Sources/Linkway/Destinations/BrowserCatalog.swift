import Foundation

enum BrowserEngine: Sendable {
    case chromium
    case gecko
    case webkit
    case other
}

enum ProfileAdapter: Sendable, Hashable {
    /// `userDataPath` is relative to `~/Library/Application Support`.
    case chromium(userDataPath: String)
}

struct KnownBrowser: Sendable {
    let bundleID: String
    let engine: BrowserEngine
    /// Where profile metadata lives, even when the adapter is not enabled yet.
    let profileAdapter: ProfileAdapter?
    /// Profile destinations are emitted only for verified adapters.
    let profileAdapterEnabled: Bool
    let privateWindowArgument: String?

    var enabledProfileAdapter: ProfileAdapter? {
        profileAdapterEnabled ? profileAdapter : nil
    }
}

enum BrowserCatalog {
    static let all: [KnownBrowser] = [
        KnownBrowser(
            bundleID: "com.apple.Safari", engine: .webkit,
            profileAdapter: nil, profileAdapterEnabled: false, privateWindowArgument: nil
        ),
        KnownBrowser(
            bundleID: "com.google.Chrome", engine: .chromium,
            profileAdapter: .chromium(userDataPath: "Google/Chrome"), profileAdapterEnabled: true,
            privateWindowArgument: "--incognito"
        ),
        KnownBrowser(
            bundleID: "com.google.Chrome.beta", engine: .chromium,
            profileAdapter: .chromium(userDataPath: "Google/Chrome Beta"), profileAdapterEnabled: false,
            privateWindowArgument: "--incognito"
        ),
        KnownBrowser(
            bundleID: "com.google.Chrome.canary", engine: .chromium,
            profileAdapter: .chromium(userDataPath: "Google/Chrome Canary"), profileAdapterEnabled: false,
            privateWindowArgument: "--incognito"
        ),
        KnownBrowser(
            bundleID: "com.microsoft.edgemac", engine: .chromium,
            profileAdapter: .chromium(userDataPath: "Microsoft Edge"), profileAdapterEnabled: true,
            privateWindowArgument: "--inprivate"
        ),
        KnownBrowser(
            bundleID: "com.brave.Browser", engine: .chromium,
            profileAdapter: .chromium(userDataPath: "BraveSoftware/Brave-Browser"), profileAdapterEnabled: true,
            privateWindowArgument: "--incognito"
        ),
        KnownBrowser(
            bundleID: "com.vivaldi.Vivaldi", engine: .chromium,
            profileAdapter: .chromium(userDataPath: "Vivaldi"), profileAdapterEnabled: false,
            privateWindowArgument: "--incognito"
        ),
        KnownBrowser(
            bundleID: "company.thebrowser.Browser", engine: .chromium,
            profileAdapter: nil, profileAdapterEnabled: false, privateWindowArgument: nil
        ),
        KnownBrowser(
            bundleID: "com.operasoftware.Opera", engine: .chromium,
            profileAdapter: nil, profileAdapterEnabled: false, privateWindowArgument: "--private"
        ),
        KnownBrowser(
            bundleID: "org.mozilla.firefox", engine: .gecko,
            profileAdapter: nil, profileAdapterEnabled: false, privateWindowArgument: "-private-window"
        ),
    ]

    private static let byBundleID = Dictionary(
        all.map { ($0.bundleID.lowercased(), $0) }, uniquingKeysWith: { first, _ in first }
    )

    static func browser(for bundleID: String) -> KnownBrowser? {
        byBundleID[bundleID.lowercased()]
    }
}
