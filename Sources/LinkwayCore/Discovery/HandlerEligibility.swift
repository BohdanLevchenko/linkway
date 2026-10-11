import Foundation

/// The parts of an app's Info.plist that tell a web browser apart from an app that merely accepts links.
public struct AppInfoPlist: Sendable, Hashable, Decodable {
    public struct URLType: Sendable, Hashable, Decodable {
        public let schemes: [String]
        public let handlerRank: String?

        public init(schemes: [String], handlerRank: String? = nil) {
            self.schemes = schemes
            self.handlerRank = handlerRank
        }

        enum CodingKeys: String, CodingKey {
            case schemes = "CFBundleURLSchemes"
            case handlerRank = "LSHandlerRank"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemes = (try? container.decodeIfPresent([String].self, forKey: .schemes)) ?? []
            handlerRank = try? container.decodeIfPresent(String.self, forKey: .handlerRank)
        }
    }

    public struct DocumentType: Sendable, Hashable, Decodable {
        public let contentTypes: [String]
        public let extensions: [String]

        public init(contentTypes: [String] = [], extensions: [String] = []) {
            self.contentTypes = contentTypes
            self.extensions = extensions
        }

        enum CodingKeys: String, CodingKey {
            case contentTypes = "LSItemContentTypes"
            case extensions = "CFBundleTypeExtensions"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            contentTypes = (try? container.decodeIfPresent([String].self, forKey: .contentTypes)) ?? []
            extensions = (try? container.decodeIfPresent([String].self, forKey: .extensions)) ?? []
        }
    }

    public let urlTypes: [URLType]
    public let documentTypes: [DocumentType]

    public init(urlTypes: [URLType], documentTypes: [DocumentType]) {
        self.urlTypes = urlTypes
        self.documentTypes = documentTypes
    }

    /// Accepts XML and binary plists; malformed entries are dropped rather than failing the whole plist.
    public init(data: Data) throws {
        self = try PropertyListDecoder().decode(AppInfoPlist.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case urlTypes = "CFBundleURLTypes"
        case documentTypes = "CFBundleDocumentTypes"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urlTypes = (try? container.decodeIfPresent([URLType].self, forKey: .urlTypes)) ?? []
        documentTypes = (try? container.decodeIfPresent([DocumentType].self, forKey: .documentTypes)) ?? []
    }
}

/// Separates real browsers and mail clients from apps that merely accept a scheme:
/// an app must claim the scheme as a primary handler AND open the matching document type.
/// `LSHandlerRank` Alternate or None marks a secondary handler (iTerm does this for http/https).
public enum HandlerEligibility {
    public static func isBrowser(_ info: AppInfoPlist) -> Bool {
        claimsPrimary(info, anyOf: webSchemes)
            && opens(info, contentTypes: htmlContentTypes, extensions: htmlExtensions)
    }

    public static func isMailClient(_ info: AppInfoPlist) -> Bool {
        claimsPrimary(info, anyOf: mailSchemes)
            && opens(info, contentTypes: emailContentTypes, extensions: emailExtensions)
    }

    private static func claimsPrimary(_ info: AppInfoPlist, anyOf schemes: Set<String>) -> Bool {
        info.urlTypes.contains { type in
            !secondaryRanks.contains(type.handlerRank?.lowercased() ?? "")
                && type.schemes.contains { schemes.contains($0.lowercased()) }
        }
    }

    private static func opens(_ info: AppInfoPlist, contentTypes: Set<String>, extensions: Set<String>) -> Bool {
        info.documentTypes.contains { type in
            type.contentTypes.contains { contentTypes.contains($0.lowercased()) }
                || type.extensions.contains { extensions.contains($0.lowercased()) }
        }
    }

    private static let secondaryRanks: Set<String> = ["alternate", "none"]
    private static let webSchemes: Set<String> = ["http", "https"]
    private static let htmlContentTypes: Set<String> = ["public.html"]
    private static let htmlExtensions: Set<String> = ["html", "htm"]
    private static let mailSchemes: Set<String> = ["mailto"]
    private static let emailContentTypes: Set<String> = [
        "public.email-message", "com.apple.mail.email", "com.apple.mail.emlx",
    ]
    private static let emailExtensions: Set<String> = ["eml", "emlx", "msg"]
}
