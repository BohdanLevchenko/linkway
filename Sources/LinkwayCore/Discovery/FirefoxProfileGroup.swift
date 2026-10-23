import Foundation
import SQLite3

public enum FirefoxProfileGroup {
    public static func colorARGB(_ value: String?) -> Int? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let rgba = text.hasPrefix("rgba(")
        guard rgba || text.hasPrefix("rgb("), text.hasSuffix(")") else { return nil }
        let parts = text.dropFirst(rgba ? 5 : 4).dropLast().split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == (rgba ? 4 : 3) else { return nil }
        let numbers = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == parts.count, numbers.allSatisfy(\.isFinite),
              numbers.prefix(3).allSatisfy({ (0...255).contains($0) }),
              !rgba || (0...1).contains(numbers[3]) else { return nil }
        let alpha = rgba ? Int((numbers[3] * 255).rounded()) : 255
        return (alpha << 24) | (Int(numbers[0].rounded()) << 16) | (Int(numbers[1].rounded()) << 8) | Int(numbers[2].rounded())
    }

    public static func read(database: URL, supportDirectory: URL) -> [FirefoxProfile]? {
        for attempt in 0..<3 {
            let (profiles, status) = readOnce(database: database, supportDirectory: supportDirectory)
            if status == SQLITE_OK { return profiles }
            guard status == SQLITE_BUSY || status == SQLITE_LOCKED else { return nil }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.025) }
        }
        return nil
    }

    private static func readOnce(database: URL, supportDirectory: URL) -> ([FirefoxProfile], Int32) {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(database.absoluteString + "?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        defer { sqlite3_close(db) }
        guard status == SQLITE_OK else { return ([], status) }
        sqlite3_busy_timeout(db, 50)
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, "SELECT path, name, avatar, themeFg, themeBg FROM Profiles ORDER BY id", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard prepared == SQLITE_OK else { return ([], prepared) }
        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        var profiles: [FirefoxProfile] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return (profiles, SQLITE_OK) }
            guard step == SQLITE_ROW else { return ([], step) }
            guard let path = text(0), !path.isEmpty else { continue }
            profiles.append(FirefoxProfile(
                name: text(1).flatMap { $0.isEmpty ? nil : $0 } ?? URL(filePath: path).lastPathComponent,
                path: FirefoxProfiles.profilePath(forKey: path, supportDirectory: supportDirectory),
                isDefault: false, isInstallDefault: false, avatar: text(2),
                highlightColorARGB: colorARGB(text(4)), foregroundColorARGB: colorARGB(text(3))
            ))
        }
    }
}
