import Foundation
import LinkwayCore
import Testing

private let supportDirectory = URL(filePath: "/Users/test/Library/Application Support/Firefox", directoryHint: .isDirectory)

@Test func parsesRelativeAbsoluteAndInstallDefaults() {
    let profiles = FirefoxProfiles.profiles(fromINI: """
    [Install31210A081F86E80E]
    Default=Profiles/abcd.default-release
    Locked=1

    [Profile1]
    Name=Work
    IsRelative=0
    Path=/Volumes/Data/Firefox/work

    [Profile0]
    Name=default-release
    IsRelative=1
    Path=Profiles/abcd.default-release
    Default=1

    [General]
    StartWithLastProfile=1
    Version=2
    """, supportDirectory: supportDirectory)

    #expect(profiles == [
        FirefoxProfile(
            name: "default-release",
            path: supportDirectory.appending(path: "Profiles/abcd.default-release", directoryHint: .isDirectory),
            isDefault: true,
            isInstallDefault: true
        ),
        FirefoxProfile(
            name: "Work",
            path: URL(filePath: "/Volumes/Data/Firefox/work", directoryHint: .isDirectory),
            isDefault: false,
            isInstallDefault: false
        ),
    ])
    #expect(profiles[0].path.path(percentEncoded: false)
        == "/Users/test/Library/Application Support/Firefox/Profiles/abcd.default-release/")
}

@Test func toleratesMissingFieldsCommentsAndCRLF() {
    let ini = "; comment\r\n[Profile0]\r\nPath = Profiles/xyz.nameless\r\nIsRelative=1\r\n[Profile1]\r\nName=No path\r\n[ProfileX]\r\nPath=bad\r\n"
    let profiles = FirefoxProfiles.profiles(fromINI: ini, supportDirectory: supportDirectory)
    #expect(profiles.map(\.name) == ["xyz.nameless"])
    #expect(profiles.first?.isDefault == false)
}

@Test(arguments: ["", "garbage\nmore garbage", "Path=orphan\nName=x", "[Profile0"])
func garbageYieldsNoProfiles(input: String) {
    #expect(FirefoxProfiles.profiles(fromINI: input, supportDirectory: supportDirectory).isEmpty)
}
