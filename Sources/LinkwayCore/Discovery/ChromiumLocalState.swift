import Foundation

public struct ChromiumProfile: Sendable, Hashable {
    /// Directory name inside the user-data dir, e.g. "Default" or "Profile 1".
    public let directory: String
    public let displayName: String
    public let email: String?

    public init(directory: String, displayName: String, email: String?) {
        self.directory = directory
        self.displayName = displayName
        self.email = email
    }
}

public enum ChromiumLocalStateError: Error, Equatable {
    case invalidJSON
}

public enum ChromiumLocalState {
    public static let fileName = "Local State"

    public static func profiles(from data: Data) throws(ChromiumLocalStateError) -> [ChromiumProfile] {
        let state: LocalState
        do {
            state = try JSONDecoder().decode(LocalState.self, from: data)
        } catch {
            throw .invalidJSON
        }
        guard let section = state.profile else { return [] }

        let profiles = section.infoCache.compactMap { directory, entry -> ChromiumProfile? in
            guard !entry.isEphemeral, !entry.isGuest, !ignoredDirectories.contains(directory) else {
                return nil
            }
            return ChromiumProfile(
                directory: directory,
                displayName: entry.displayName ?? directory,
                email: entry.userName
            )
        }

        let order = Dictionary(
            section.profilesOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return profiles.sorted { lhs, rhs in
            switch (order[lhs.directory], order[rhs.directory]) {
            case let (l?, r?): l < r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.directory.compare(rhs.directory, options: .numeric) == .orderedAscending
            }
        }
    }

    private static let ignoredDirectories: Set<String> = ["Guest Profile", "System Profile"]
}

private struct LocalState: Decodable {
    let profile: ProfileSection?

    enum CodingKeys: String, CodingKey { case profile }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try? container.decodeIfPresent(ProfileSection.self, forKey: .profile)
    }
}

private struct ProfileSection: Decodable {
    let infoCache: [String: ProfileEntry]
    let profilesOrder: [String]

    enum CodingKeys: String, CodingKey {
        case infoCache = "info_cache"
        case profilesOrder = "profiles_order"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        infoCache = (try? container.decodeIfPresent([String: ProfileEntry].self, forKey: .infoCache)) ?? [:]
        profilesOrder = (try? container.decodeIfPresent([String].self, forKey: .profilesOrder)) ?? []
    }
}

/// Every field is optional and type-tolerant: one odd entry must not hide the other profiles.
private struct ProfileEntry: Decodable {
    let name: String?
    let gaiaName: String?
    let userName: String?
    let isUsingDefaultName: Bool
    let isEphemeral: Bool
    let isGuest: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case gaiaName = "gaia_name"
        case userName = "user_name"
        case isUsingDefaultName = "is_using_default_name"
        case isEphemeral = "is_ephemeral"
        case isGuest = "is_guest"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func flag(_ key: CodingKeys) -> Bool {
            (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? false
        }
        name = string(.name)
        gaiaName = string(.gaiaName)
        userName = string(.userName)
        isUsingDefaultName = flag(.isUsingDefaultName)
        isEphemeral = flag(.isEphemeral)
        isGuest = flag(.isGuest)
    }

    /// Chromium shows the account name instead of a generated "Person 1" style name.
    var displayName: String? {
        if isUsingDefaultName, let gaiaName { return gaiaName }
        return name ?? gaiaName
    }
}
