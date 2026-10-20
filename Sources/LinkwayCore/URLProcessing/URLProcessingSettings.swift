import Foundation

public struct URLProcessingSettings: Codable, Sendable, Hashable {
    public static let defaultShortenerHosts = [
        "bit.ly", "bitly.com", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "buff.ly", "is.gd",
        "rebrand.ly", "cutt.ly", "shorturl.at", "lnkd.in", "t.ly", "tiny.cc", "rb.gy", "s.id",
        "trib.al", "dlvr.it", "amzn.to",
    ]
    public var cleanTracking: Bool
    public var unwrapRedirectLinks: Bool
    public var extraTrackingParameters: [String]
    public var keptParameters: [String]
    public var cleanerExcludedHosts: [String]
    public var expandShortLinks: Bool
    public var shortenerHosts: [String]
    public init(
        cleanTracking: Bool = true, unwrapRedirectLinks: Bool = true,
        extraTrackingParameters: [String] = [], keptParameters: [String] = [],
        cleanerExcludedHosts: [String] = [], expandShortLinks: Bool = false,
        shortenerHosts: [String] = Self.defaultShortenerHosts
    ) {
        self.cleanTracking = cleanTracking
        self.unwrapRedirectLinks = unwrapRedirectLinks
        self.extraTrackingParameters = extraTrackingParameters
        self.keptParameters = keptParameters
        self.cleanerExcludedHosts = cleanerExcludedHosts
        self.expandShortLinks = expandShortLinks
        self.shortenerHosts = shortenerHosts
    }
    enum CodingKeys: String, CodingKey {
        case cleanTracking, unwrapRedirectLinks, extraTrackingParameters, keptParameters
        case cleanerExcludedHosts, expandShortLinks, shortenerHosts
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cleanTracking = try values.decodeIfPresent(Bool.self, forKey: .cleanTracking) ?? true
        unwrapRedirectLinks = try values.decodeIfPresent(Bool.self, forKey: .unwrapRedirectLinks) ?? true
        extraTrackingParameters = try values.decodeIfPresent([String].self, forKey: .extraTrackingParameters) ?? []
        keptParameters = try values.decodeIfPresent([String].self, forKey: .keptParameters) ?? []
        cleanerExcludedHosts = try values.decodeIfPresent([String].self, forKey: .cleanerExcludedHosts) ?? []
        expandShortLinks = try values.decodeIfPresent(Bool.self, forKey: .expandShortLinks) ?? false
        shortenerHosts = try values.decodeIfPresent([String].self, forKey: .shortenerHosts) ?? Self.defaultShortenerHosts
    }
}

func hostMatches(_ host: String, suffix: String) -> Bool {
    let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let suffix = suffix.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return !suffix.isEmpty && (host == suffix || host.hasSuffix("." + suffix))
}
