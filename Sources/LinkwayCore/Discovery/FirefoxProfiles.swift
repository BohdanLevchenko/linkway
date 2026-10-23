import Foundation

public struct FirefoxProfile: Sendable, Hashable {
    public let name: String
    public let path: URL
    /// `Default=1` in the profile section (legacy default, pre-dedicated-profiles).
    public let isDefault: Bool
    /// Referenced as `Default=` by an `[Install...]` section.
    public let isInstallDefault: Bool

    public let avatar: String?
    public let highlightColorARGB: Int?
    public let foregroundColorARGB: Int?

    public init(
        name: String, path: URL, isDefault: Bool, isInstallDefault: Bool,
        avatar: String? = nil, highlightColorARGB: Int? = nil, foregroundColorARGB: Int? = nil
    ) {
        self.avatar = avatar
        self.highlightColorARGB = highlightColorARGB
        self.foregroundColorARGB = foregroundColorARGB
        self.name = name
        self.path = path
        self.isDefault = isDefault
        self.isInstallDefault = isInstallDefault
    }
}

public enum FirefoxProfiles {
    public static let fileName = "profiles.ini"

    /// Keep keys independent of display names and INI section order. External profiles keep absolute paths.
    public static func profileKey(for path: URL, supportDirectory: URL) -> String {
        let base = supportDirectory.standardizedFileURL.pathComponents
        let components = path.standardizedFileURL.pathComponents
        if components.starts(with: base), components.count > base.count {
            return components.dropFirst(base.count).joined(separator: "/")
        }
        return path.standardizedFileURL.path
    }

    public static func profilePath(forKey key: String, supportDirectory: URL) -> URL {
        (key.hasPrefix("/") ? URL(filePath: key, directoryHint: .isDirectory)
            : supportDirectory.appending(path: key, directoryHint: .isDirectory)).standardizedFileURL
    }

    /// The caller supplies filesystem access so discovery filtering stays testable without disk reads.
    public static func availableProfiles(
        fromINI contents: String, supportDirectory: URL, directoryExists: (URL) -> Bool
    ) -> [FirefoxProfile] {
        var seen: Set<String> = []
        return profiles(fromINI: contents, supportDirectory: supportDirectory).filter { profile in
            directoryExists(profile.path)
                && seen.insert(profileKey(for: profile.path, supportDirectory: supportDirectory)).inserted
        }
    }

    public static func groupDatabaseURLs(fromINI contents: String, supportDirectory: URL) -> [URL] {
        let stores = Set(INISection.parse(contents).compactMap { $0.values["StoreID"] })
        return stores.sorted().filter { !$0.isEmpty && !$0.contains("/") && $0 != ".." }.map {
            supportDirectory.appending(path: "Profile Groups/\($0).sqlite")
        }
    }

    /// Single-install fallback: StoreID anchors identify the owning install's locked defaults.
    public static func selectableProfiles(
        fromINI contents: String, supportDirectory: URL, installedBrowserCount: Int,
        directoryExists: (URL) -> Bool
    ) -> [FirefoxProfile] {
        let sections = INISection.parse(contents)
        let anchors = Set(sections.filter { $0.values["StoreID"] != nil }.compactMap { $0.values["Path"] })
        let installs = sections.filter { $0.name.hasPrefix("Install") && $0.values["Locked"] == "1" }
        let owners = Set(installs.filter { anchors.contains($0.values["Default"] ?? "") }.map(\.name))
        let excluded = Set(installs.filter { !owners.contains($0.name) }.compactMap { $0.values["Default"] }.map {
            profileKey(for: profilePath(forKey: $0, supportDirectory: supportDirectory), supportDirectory: supportDirectory)
        })
        let legacy = profiles(fromINI: contents, supportDirectory: supportDirectory)
        var result: [FirefoxProfile] = []
        var seenStores: Set<String> = []
        for profile in legacy {
            let key = profileKey(for: profile.path, supportDirectory: supportDirectory)
            if installedBrowserCount == 1 && !owners.isEmpty && excluded.contains(key) { continue }
            let section = sections.first { section in
                guard let raw = section.values["Path"] else { return false }
                return profilePath(forKey: raw, supportDirectory: supportDirectory).standardizedFileURL == profile.path.standardizedFileURL
            }
            if let store = section?.values["StoreID"],
               let database = groupDatabaseURLs(fromINI: "[Profile0]\nStoreID=\(store)", supportDirectory: supportDirectory).first {
                guard !seenStores.contains(store) else { continue }
                if let rows = FirefoxProfileGroup.read(database: database, supportDirectory: supportDirectory) {
                    seenStores.insert(store)
                    result += rows
                    continue
                }
            }
            result.append(profile)
        }
        var seen: Set<String> = []
        return result.filter {
            let key = profileKey(for: $0.path, supportDirectory: supportDirectory)
            return !(installedBrowserCount == 1 && !owners.isEmpty && excluded.contains(key))
                && directoryExists($0.path) && seen.insert(key).inserted
        }
    }

    /// Parses `profiles.ini`. Relative paths resolve against `supportDirectory`
    /// (normally `~/Library/Application Support/Firefox`). Unparseable input yields no profiles.
    public static func profiles(fromINI contents: String, supportDirectory: URL) -> [FirefoxProfile] {
        let sections = INISection.parse(contents)

        let installDefaults = Set(
            sections.filter { $0.name.hasPrefix("Install") }.compactMap { $0.values["Default"] }
        )

        return sections
            .compactMap { section -> (index: Int, rawPath: String, profile: FirefoxProfile)? in
                guard section.name.hasPrefix("Profile"),
                      let index = Int(section.name.dropFirst("Profile".count)),
                      let rawPath = section.values["Path"], !rawPath.isEmpty
                else { return nil }
                let isRelative = section.values["IsRelative"] == "1"
                let path = isRelative
                    ? supportDirectory.appending(path: rawPath, directoryHint: .isDirectory)
                    : URL(filePath: rawPath, directoryHint: .isDirectory)
                let name = section.values["Name"].flatMap { $0.isEmpty ? nil : $0 }
                    ?? path.lastPathComponent
                return (index, rawPath, FirefoxProfile(
                    name: name,
                    path: path,
                    isDefault: section.values["Default"] == "1",
                    isInstallDefault: installDefaults.contains(rawPath)
                ))
            }
            .sorted { $0.index < $1.index }
            .map(\.profile)
    }
}

struct INISection {
    let name: String
    var values: [String: String]

    static func parse(_ contents: String) -> [INISection] {
        var sections: [INISection] = []
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append(INISection(name: String(line.dropFirst().dropLast()), values: [:]))
                continue
            }
            guard let separator = line.firstIndex(of: "="), !sections.isEmpty else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            sections[sections.count - 1].values[key] = value
        }
        return sections
    }
}
