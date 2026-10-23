import Foundation
import SQLite3
import Testing
@testable import LinkwayCore

private let groupINI = """
[Profile0]
Name=Default
Path=Profiles/DxWDw19H.Profile 1
Default=1
StoreID=7ebc1523
ShowSelector=1
IsRelative=1
[Profile1]
Name=default-nightly
Path=Profiles/9b7uuset.default-nightly
IsRelative=1
[Install31210A081F86E80E]
Default=Profiles/9b7uuset.default-nightly
Locked=1
[Install2656FF1E876E9973]
Default=Profiles/DxWDw19H.Profile 1
Locked=1
"""

private func fixture() throws -> (URL, URL, OpaquePointer) {
    let support = FileManager.default.temporaryDirectory.appending(path: "firefox-" + UUID().uuidString)
    let database = support.appending(path: "Profile Groups/7ebc1523.sqlite")
    try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
    for path in ["Profiles/rkuc4h6b.Default", "Profiles/DxWDw19H.Profile 1", "Profiles/9b7uuset.default-nightly"] {
        try FileManager.default.createDirectory(at: support.appending(path: path), withIntermediateDirectories: true)
    }
    var db: OpaquePointer?
    #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
    let connection = try #require(db)
    try execute(connection, """
        PRAGMA journal_mode=WAL;
        CREATE TABLE Profiles(id INTEGER, path TEXT, name TEXT, avatar TEXT, themeId TEXT, themeFg TEXT, themeBg TEXT);
        INSERT INTO Profiles VALUES(1,'Profiles/rkuc4h6b.Default','Original profile','book','default-theme@mozilla.org','rgb(21,20,26)','rgb(240,240,244)');
        INSERT INTO Profiles VALUES(2,'Profiles/DxWDw19H.Profile 1','Work','flower','default-theme@mozilla.org','rgba(252, 251, 255, 1)','rgba(62, 41, 118, 1)');
        """)
    return (support, database, connection)
}

private func execute(_ db: OpaquePointer, _ sql: String) throws {
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
}

@Test func firefoxGroupReplacesAnchorReadsWALAndAttributesSingleInstall() throws {
    let (support, database, db) = try fixture()
    defer { sqlite3_close(db); try? FileManager.default.removeItem(at: support) }
    #expect(FileManager.default.fileExists(atPath: database.path + "-wal"))
    let before = try Data(contentsOf: database)
    let rows = FirefoxProfiles.selectableProfiles(fromINI: groupINI, supportDirectory: support, installedBrowserCount: 1) {
        FileManager.default.fileExists(atPath: $0.path)
    }
    #expect(rows.map(\.name) == ["Original profile", "Work"])
    #expect(rows.map { FirefoxProfiles.profileKey(for: $0.path, supportDirectory: support) }
            == ["Profiles/rkuc4h6b.Default", "Profiles/DxWDw19H.Profile 1"])
    #expect(rows.map(\.avatar) == ["book", "flower"])
    #expect(rows.map(\.highlightColorARGB) == [0xfff0f0f4, 0xff3e2976])
    #expect(rows.map(\.foregroundColorARGB) == [0xff15141a, 0xfffcfbff])
    #expect(try Data(contentsOf: database) == before)
    #expect(FirefoxProfiles.groupDatabaseURLs(fromINI: groupINI, supportDirectory: support) == [database])
    let multiple = FirefoxProfiles.selectableProfiles(fromINI: groupINI, supportDirectory: support, installedBrowserCount: 2) { _ in true }
    #expect(multiple.map(\.name) == ["Original profile", "Work", "default-nightly"])
    try execute(db, "UPDATE Profiles SET name='Renamed' WHERE id=2")
    #expect(FirefoxProfileGroup.read(database: database, supportDirectory: support)?.last?.name == "Renamed")
}

@Test func firefoxGroupFailureFallsBackAndLegacyProfilesRemainAvailable() throws {
    let (support, database, db) = try fixture()
    defer { sqlite3_close(db); try? FileManager.default.removeItem(at: support) }
    try execute(db, "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE; BEGIN EXCLUSIVE;")
    let locked = FirefoxProfiles.selectableProfiles(fromINI: groupINI, supportDirectory: support, installedBrowserCount: 1) { _ in true }
    #expect(locked.map(\.name) == ["Default"])
    try execute(db, "ROLLBACK; DROP TABLE Profiles;")
    #expect(FirefoxProfileGroup.read(database: database, supportDirectory: support) == nil)
    let legacyINI = groupINI.replacingOccurrences(of: "StoreID=7ebc1523\n", with: "")
    #expect(FirefoxProfiles.selectableProfiles(fromINI: legacyINI, supportDirectory: support, installedBrowserCount: 1) { _ in true }.count == 2)
    #expect(FirefoxProfiles.groupDatabaseURLs(fromINI: "[Profile0]\nStoreID=../escape", supportDirectory: support).isEmpty)
}

@Test func firefoxGroupAbsolutePathsAndMissingDirectories() throws {
    let (support, database, db) = try fixture()
    defer { sqlite3_close(db); try? FileManager.default.removeItem(at: support) }
    try execute(db, "UPDATE Profiles SET path='/external/custom' WHERE id=1")
    #expect(FirefoxProfileGroup.read(database: database, supportDirectory: support)?.first?.path.path == "/external/custom")
    let rows = FirefoxProfiles.selectableProfiles(fromINI: groupINI, supportDirectory: support, installedBrowserCount: 1) {
        $0.path.hasSuffix("DxWDw19H.Profile 1")
    }
    #expect(rows.map(\.name) == ["Work"])
}

@Test(arguments: [
    ("rgb(21,20,26)", 0xff15141a), ("rgba(252, 251, 255, 1)", 0xfffcfbff),
    ("rgba(0, 0, 0, 0.5)", 0x80000000), (" rgb(0, 255, 3) ", 0xff00ff03)
]) func firefoxRGBParsing(value: String, expected: Int) {
    #expect(FirefoxProfileGroup.colorARGB(value) == expected)
}

@Test(arguments: ["rgb(-1,0,0)", "rgb(256,0,0)", "rgba(0,0,0,2)", "rgb(0,0)", "#ffffff", "rgb(nan,0,0)", "rgb(1,2,3,4)", "rgba(0,0,0,inf)"])
func firefoxRGBRejectsInvalid(value: String) { #expect(FirefoxProfileGroup.colorARGB(value) == nil) }

@Test func firefoxAvatarExtractsStoredAndDeflatedZipEntries() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = "chrome/browser/content/browser/profiles/assets/80_book.svg"
    let entry = root.appending(path: path)
    try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
    let svg = Data(("<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0h80v80H0z\"/>" + String(repeating: " ", count: 1024) + "</svg>").utf8)
    try svg.write(to: entry)
    for compression in ["-0", "-9"] {
        let archive = root.appending(path: compression + ".zip")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", compression, archive.path, path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(FirefoxAvatar.extract(avatar: "book", archive: archive) == svg)
        let prefixed = root.appending(path: compression + "-prefixed.zip")
        try (Data(repeating: 0, count: 4) + Data(contentsOf: archive)).write(to: prefixed)
        #expect(FirefoxAvatar.extract(avatar: "book", archive: prefixed) == svg)
        #expect(FirefoxAvatar.extract(avatar: "unknown", archive: archive) == nil)
        #expect(FirefoxAvatar.extract(avatar: "../book", archive: archive) == nil)
    }
    #expect(FirefoxAvatar.data(for: entry.path, appURL: root) == svg)
    #expect(FirefoxAvatar.data(for: entry.absoluteString, appURL: root) == svg)
    #expect(!FirefoxAvatar.isGlyph(entry.absoluteString))
    #expect(FirefoxAvatar.isGlyph("book"))
    #expect(!FirefoxAvatar.isGlyph("avatar.png"))
    #expect(FirefoxAvatar.data(for: path, appURL: root, supportDirectory: root) == svg)
}

@Test func firefoxEmptyGroupReplacesINIAndUnclaimedProfilesRemain() throws {
    let (support, _, db) = try fixture()
    defer { sqlite3_close(db); try? FileManager.default.removeItem(at: support) }
    let extra = """

    [Profile2]
    Name=Unclaimed
    Path=Profiles/unclaimed
    IsRelative=1
    """
    let ini = groupINI + "\n" + extra
    #expect(FirefoxProfiles.selectableProfiles(fromINI: ini, supportDirectory: support, installedBrowserCount: 1) { _ in true }.map(\.name)
        == ["Original profile", "Work", "Unclaimed"])
    try execute(db, "DELETE FROM Profiles")
    #expect(FirefoxProfiles.selectableProfiles(fromINI: ini, supportDirectory: support, installedBrowserCount: 1) { _ in true }.map(\.name)
        == ["Unclaimed"])
}
