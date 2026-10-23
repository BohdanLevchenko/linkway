import Foundation

public enum FirefoxAvatar {
    /// Called lazily on a utility task; only bundled glyphs are cached across launches.
    public static func data(for avatar: String, appURL: URL, supportDirectory: URL? = nil) -> Data? {
        if avatar.hasPrefix("/") { return try? Data(contentsOf: URL(filePath: avatar)) }
        if let url = URL(string: avatar), ["file", "https", "http"].contains(url.scheme?.lowercased() ?? "") {
            return try? Data(contentsOf: url)
        }
        if !isGlyph(avatar), let supportDirectory {
            return try? Data(contentsOf: supportDirectory.appending(path: avatar))
        }
        guard !avatar.isEmpty, avatar.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let archive = appURL.appending(path: "Contents/Resources/browser/omni.ja")
        let bundle = Bundle(url: appURL)
        let version = (bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
            + (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        let stamp = (try? archive.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = (appURL.path + version + String(stamp)).utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "io.github.bohdanlevchenko.linkway/firefox-avatars/\(key)")
        let cached = cache?.appending(path: avatar + ".svg")
        if let cached, let data = try? Data(contentsOf: cached) { return templateGlyph(data) }
        guard let data = extract(avatar: avatar, archive: archive) else { return nil }
        if let cache, let cached {
            try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try? data.write(to: cached, options: .atomic)
        }
        return templateGlyph(data)
    }

    /// Firefox paints its avatar SVGs with `context-fill` (circle) and `context-stroke` (glyph), which only Gecko resolves.
    public static func templateGlyph(_ svg: Data) -> Data {
        guard let text = String(data: svg, encoding: .utf8) else { return svg }
        let resolved = text
            .replacingOccurrences(of: #"fill="context-fill""#, with: #"fill="none""#)
            .replacingOccurrences(of: #"fill="context-stroke""#, with: ##"fill="#000000""##)
            .replacingOccurrences(of: #"stroke="context-stroke""#, with: ##"stroke="#000000""##)
        return Data(resolved.utf8)
    }

    public static func isGlyph(_ avatar: String) -> Bool {
        !avatar.isEmpty && avatar.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    public static func extract(avatar: String, archive: URL) -> Data? {
        guard !avatar.isEmpty, avatar.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, "chrome/browser/content/browser/profiles/assets/80_\(avatar).svg"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // Firefox optimizes omni.ja with a relocated central directory; unzip returns 2 with valid output.
        guard (0...2).contains(process.terminationStatus), !data.isEmpty else { return nil }
        let parser = XMLParser(data: data)
        let validator = SVGValidator()
        parser.delegate = validator
        parser.shouldResolveExternalEntities = false
        return parser.parse() && validator.isSVG ? data : nil
    }
}

private final class SVGValidator: NSObject, XMLParserDelegate {
    private var sawRoot = false
    var isSVG = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard !sawRoot else { return }
        sawRoot = true
        isSVG = elementName == "svg"
    }
}
