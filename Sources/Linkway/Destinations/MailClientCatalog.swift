import Foundation

/// Mail clients listed without checking their Info.plist.
enum MailClientCatalog {
    static let bundleIDs: Set<String> = [
        "com.apple.mail",
        "com.microsoft.outlook",
        "com.readdle.smartemail-mac",
        "com.readdle.sparkdesktop",
        "it.bloop.airmail2",
        "com.mimestream.mimestream",
        "org.mozilla.thunderbird",
        "io.canarymail.mac",
    ]

    static func contains(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID.lowercased())
    }
}
