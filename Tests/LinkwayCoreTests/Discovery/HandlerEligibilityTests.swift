import Foundation
import LinkwayCore
import Testing

private func plist(_ body: String) throws -> AppInfoPlist {
    try AppInfoPlist(data: Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.example.app</string>
    \(body)
    </dict></plist>
    """.utf8))
}

private let webSchemes = """
<key>CFBundleURLTypes</key><array>
  <dict><key>CFBundleURLName</key><string>Web</string>
  <key>CFBundleURLSchemes</key><array><string>HTTP</string><string>https</string></array></dict>
</array>
"""

@Test func acceptsContentTypeAndExtensionDeclarations() throws {
    let modern = try plist(webSchemes + """
    <key>CFBundleDocumentTypes</key><array>
      <dict><key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key><array><string>public.html</string></array></dict>
    </array>
    """)
    let legacy = try plist(webSchemes + """
    <key>CFBundleDocumentTypes</key><array>
      <dict><key>CFBundleTypeExtensions</key><array><string>HTM</string></array></dict>
    </array>
    """)
    #expect(HandlerEligibility.isBrowser(modern))
    #expect(HandlerEligibility.isBrowser(legacy))
}

@Test func rejectsLinkHandlersWithoutHTMLDocuments() throws {
    let info = try plist(webSchemes + """
    <key>CFBundleDocumentTypes</key><array>
      <dict><key>LSItemContentTypes</key><array><string>public.plain-text</string></array></dict>
    </array>
    """)
    #expect(!HandlerEligibility.isBrowser(info))
}

@Test func rejectsAlternateWebHandlers() {
    let info = AppInfoPlist(
        urlTypes: [
            .init(schemes: ["http", "https"], handlerRank: "Alternate"),
            .init(schemes: ["ssh"]),
        ],
        documentTypes: [.init(contentTypes: ["public.html"])]
    )
    #expect(!HandlerEligibility.isBrowser(info))
}

@Test func rejectsHTMLViewersWithoutWebSchemes() {
    let info = AppInfoPlist(
        urlTypes: [.init(schemes: ["file", "custom"])],
        documentTypes: [.init(contentTypes: ["public.html"])]
    )
    #expect(!HandlerEligibility.isBrowser(info))
}

@Test func toleratesMalformedEntries() throws {
    let info = try plist("""
    <key>CFBundleURLTypes</key><array>
      <dict><key>CFBundleURLSchemes</key><string>http</string></dict>
      <dict><key>CFBundleURLSchemes</key><array><string>https</string></array><key>LSHandlerRank</key><integer>3</integer></dict>
    </array>
    <key>CFBundleDocumentTypes</key><array>
      <dict><key>LSItemContentTypes</key><string>public.html</string></dict>
      <dict><key>CFBundleTypeExtensions</key><array><string>html</string></array></dict>
    </array>
    """)
    #expect(HandlerEligibility.isBrowser(info))
    #expect(!HandlerEligibility.isBrowser(try plist("")))
}

@Test func rejectsNonPlistData() {
    #expect(throws: (any Error).self) { try AppInfoPlist(data: Data("not a plist".utf8)) }
}

@Test func acceptsMailClientsDeclaringEmailDocuments() throws {
    let appleMail = try plist("""
    <key>CFBundleURLTypes</key><array>
      <dict><key>CFBundleURLSchemes</key><array><string>mailto</string></array>
      <key>LSIsAppleDefaultForScheme</key><true/></dict>
    </array>
    <key>CFBundleDocumentTypes</key><array>
      <dict><key>LSItemContentTypes</key><array><string>com.apple.mail.email</string></array></dict>
    </array>
    """)
    let byExtension = AppInfoPlist(
        urlTypes: [.init(schemes: ["MAILTO"], handlerRank: "Owner")],
        documentTypes: [.init(extensions: ["EML"])]
    )
    #expect(HandlerEligibility.isMailClient(appleMail))
    #expect(HandlerEligibility.isMailClient(byExtension))
    #expect(!HandlerEligibility.isBrowser(appleMail))
}

/// Mirrors iTerm's real plist: unranked mailto among many schemes, Alternate http/https,
/// public.html but no email document types.
@Test func rejectsITermLikeHandlers() {
    let iTerm = AppInfoPlist(
        urlTypes: [
            .init(schemes: ["http", "https"], handlerRank: "Alternate"),
            .init(schemes: ["mailto"]),
            .init(schemes: ["ssh"]),
        ],
        documentTypes: [
            .init(extensions: ["command", "sh"]),
            .init(contentTypes: ["public.folder"]),
            .init(contentTypes: ["public.html"]),
        ]
    )
    #expect(!HandlerEligibility.isMailClient(iTerm))
    #expect(!HandlerEligibility.isBrowser(iTerm))
}

@Test(arguments: ["Alternate", "none"])
func rejectsSecondaryMailtoHandlers(rank: String) {
    let info = AppInfoPlist(
        urlTypes: [.init(schemes: ["mailto"], handlerRank: rank)],
        documentTypes: [.init(contentTypes: ["public.email-message"])]
    )
    #expect(!HandlerEligibility.isMailClient(info))
}
