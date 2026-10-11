import Foundation

public struct FirefoxProfile: Sendable, Hashable {
    public let name: String
    public let path: URL
    /// `Default=1` in the profile section (legacy default, pre-dedicated-profiles).
    public let isDefault: Bool
    /// Referenced as `Default=` by an `[Install...]` section.
    public let isInstallDefault: Bool

    public init(name: String, path: URL, isDefault: Bool, isInstallDefault: Bool) {
        self.name = name
        self.path = path
        self.isDefault = isDefault
        self.isInstallDefault = isInstallDefault
    }
}

public enum FirefoxProfiles {
    public static let fileName = "profiles.ini"

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

private struct INISection {
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
