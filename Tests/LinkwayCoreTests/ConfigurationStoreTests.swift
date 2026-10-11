import Foundation
import Testing
import LinkwayCore

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LinkwayCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func sampleConfiguration() -> LinkwayConfiguration {
    let destination = DestinationID(bundleID: "com.example.browser", profileKey: "Profile 1")
    let conditions: [RuleCondition] = [
        .hostExact("example.com:443"), .hostIncludingSubdomains("example.com"),
        .urlPrefix("https://example.com/a"), .pathPattern(host: nil, pattern: "/a/**"),
        .sourceApp(bundleID: "com.example.sender"), .mailRecipientDomain("example.com"),
    ]
    return LinkwayConfiguration(
        rules: conditions.enumerated().map { index, condition in
            Rule(name: "rule \(index)", isEnabled: index != 0, condition: condition,
                 action: index == 0 ? .showPicker : .open(destination, privateWindow: true),
                 matchTarget: index == 0 ? .original : .processed)
        },
        fallbacks: FallbackPolicies(web: .open(destination), mail: .showPicker),
        destinationOrder: [destination], hiddenDestinations: [destination],
        favoriteDestinations: [destination], forcePickerModifier: .command
    )
}

@Test func missingConfigurationReturnsDefault() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("nested/configuration.json")
    let store = ConfigurationStore(fileURL: url)
    #expect(try await store.load() == .default)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(LinkwayConfiguration.default.forcePickerModifier == .option)
    #expect(ConfigurationStore.defaultFileURL.path.hasSuffix("Library/Application Support/io.github.bohdanlevchenko.linkway/configuration.json"))
}

@Test func configurationRoundTripAndExportImport() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("nested/configuration.json")
    let store = ConfigurationStore(fileURL: url)
    let configuration = sampleConfiguration()
    try await store.save(configuration)
    #expect(try await store.load() == configuration)
    let data = try Data(contentsOf: url)
    #expect(try ConfigurationStore.migrate(from: data) == configuration)
    #expect(String(decoding: data, as: UTF8.self).contains("\n"))
    let exportURL = directory.appendingPathComponent("export.json")
    try await store.export(to: exportURL)
    let imported = ConfigurationStore(fileURL: directory.appendingPathComponent("imported.json"))
    try await imported.import(from: exportURL)
    #expect(try await imported.load() == configuration)
}

@Test func unknownVersionNeverOverwritten() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("configuration.json")
    let data = Data(#"{"schemaVersion":99,"futureField":true}"#.utf8)
    try data.write(to: url)
    let store = ConfigurationStore(fileURL: url)
    await #expect(throws: ConfigurationStoreError.unsupportedSchemaVersion(99)) { try await store.load() }
    await #expect(throws: ConfigurationStoreError.unsupportedSchemaVersion(99)) { try await store.save(.default) }
    let validImport = directory.appendingPathComponent("valid.json")
    try JSONEncoder().encode(LinkwayConfiguration.default).write(to: validImport)
    await #expect(throws: ConfigurationStoreError.unsupportedSchemaVersion(99)) { try await store.import(from: validImport) }
    #expect(try Data(contentsOf: url) == data)
}

@Test(arguments: ["garbage", "{}", #"{"schemaVersion":1}"#, #"{"schemaVersion":2}"#])
func invalidImportPreservesExistingFile(raw: String) async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("configuration.json")
    let source = directory.appendingPathComponent("invalid.json")
    let store = ConfigurationStore(fileURL: url)
    try await store.save(sampleConfiguration())
    let previous = try Data(contentsOf: url)
    try Data(raw.utf8).write(to: source)
    await #expect(throws: (any Error).self) { try await store.import(from: source) }
    #expect(try Data(contentsOf: url) == previous)
}

@Test func invalidSavePreservesExistingFile() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("configuration.json")
    let store = ConfigurationStore(fileURL: url)
    try await store.save(.default)
    let previous = try Data(contentsOf: url)
    await #expect(throws: ConfigurationStoreError.unsupportedSchemaVersion(0)) {
        try await store.save(LinkwayConfiguration(schemaVersion: 0))
    }
    #expect(try Data(contentsOf: url) == previous)
}
