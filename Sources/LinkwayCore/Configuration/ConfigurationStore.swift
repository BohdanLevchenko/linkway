import Foundation

public enum ConfigurationStoreError: Error, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
}

public actor ConfigurationStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/io.github.bohdanlevchenko.linkway", isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    public func load() throws -> LinkwayConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return .default
        }
        return try Self.migrate(from: data)
    }

    public func save(_ configuration: LinkwayConfiguration) throws {
        // Refuse to replace an existing configuration from a newer app, even when save is called directly.
        _ = try load()
        let data = try Self.encode(configuration)
        try Self.write(data, to: fileURL)
    }

    public static func migrate(from rawJSON: Data) throws -> LinkwayConfiguration {
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: rawJSON)
        switch header.schemaVersion {
        case 1: return try decoder.decode(LinkwayConfiguration.self, from: rawJSON)
        default: throw ConfigurationStoreError.unsupportedSchemaVersion(header.schemaVersion)
        }
    }

    public func export(to url: URL) throws {
        let configuration = try load()
        let data = try Self.encode(configuration)
        try Self.write(data, to: url)
    }

    public func `import`(from url: URL) throws {
        let configuration = try Self.migrate(from: Data(contentsOf: url))
        try save(configuration)
    }

    private static func encode(_ configuration: LinkwayConfiguration) throws -> Data {
        guard configuration.schemaVersion == LinkwayConfiguration.currentSchemaVersion else {
            throw ConfigurationStoreError.unsupportedSchemaVersion(configuration.schemaVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        _ = try migrate(from: data)
        return data
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
