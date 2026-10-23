import Foundation
import LinkwayCore
import Testing

private let firefoxSupport = URL(filePath: "/Users/test/Library/Application Support/Firefox", directoryHint: .isDirectory)

@Test func firefoxKeysUsePathsRatherThanNames() {
    let profiles = FirefoxProfiles.profiles(fromINI: """
    [Profile4]
    Name=Renamed Work
    IsRelative=1
    Path=Profiles/abcd.default-release
    [Profile0]
    Name=External
    IsRelative=0
    Path=/Volumes/Data/Firefox/work
    [Profile2]
    Name=Absolute internal
    IsRelative=0
    Path=/Users/test/Library/Application Support/Firefox/Profiles/internal
    """, supportDirectory: firefoxSupport)
    let keys = profiles.map { FirefoxProfiles.profileKey(for: $0.path, supportDirectory: firefoxSupport) }
    #expect(keys == ["/Volumes/Data/Firefox/work", "Profiles/internal", "Profiles/abcd.default-release"])
    for (profile, key) in zip(profiles, keys) {
        #expect(FirefoxProfiles.profilePath(forKey: key, supportDirectory: firefoxSupport) == profile.path.standardizedFileURL)
    }
}

@Test func firefoxKeysRespectDirectoryBoundariesAndNormalizePaths() {
    let sibling = URL(filePath: "/Users/test/Library/Application Support/Firefox Other/work")
    #expect(FirefoxProfiles.profileKey(for: sibling, supportDirectory: firefoxSupport) == sibling.path)
    let path = firefoxSupport.appending(path: "Profiles/unused/../work")
    #expect(FirefoxProfiles.profileKey(for: path, supportDirectory: firefoxSupport) == "Profiles/work")
}

@Test func firefoxDiscoveryHidesMissingDirectoriesAndDeduplicatesPaths() {
    let profiles = FirefoxProfiles.availableProfiles(fromINI: """
    [Profile0]
    Name=Work
    IsRelative=1
    Path=Profiles/work
    [Profile1]
    Name=Deleted
    IsRelative=1
    Path=Profiles/deleted
    [Profile2]
    Name=Duplicate
    IsRelative=1
    Path=Profiles/work
    [Profile3]
    Name=File instead of directory
    IsRelative=1
    Path=Profiles/file
    """, supportDirectory: firefoxSupport) { path in
        path.lastPathComponent == "work"
    }
    #expect(profiles.map(\.name) == ["Work"])
    #expect(FirefoxProfiles.availableProfiles(
        fromINI: "", supportDirectory: firefoxSupport, directoryExists: { _ in true }
    ).isEmpty)
}

private enum FirefoxScenario: CaseIterable {
    case cold
    case sameProfile
    case otherProfile

    var runningState: BrowserRunningState { self == .cold ? .stopped : .running }
}

@Test(arguments: FirefoxScenario.allCases, [false, true])
private func firefoxLaunchMatrix(scenario: FirefoxScenario, privateWindow: Bool) {
    let url = URL(string: "https://example.com/a?q=hello%20world&next=-no-remote")!
    let profile = firefoxSupport.appending(path: "Profiles/abcd.Work Profile")
    let plan = BrowserLaunchPlan.firefox(
        url: url, profilePath: profile, privateWindow: privateWindow, runningState: scenario.runningState
    )
    #expect(plan.arguments == ["-profile", profile.path] + (privateWindow ? ["-private-window"] : []) + [url.absoluteString])
    #expect(plan.delivery == (scenario == .cold ? .launchApplication : .forward))
    #expect(!plan.arguments.contains("--new-instance"))
    #expect(!plan.arguments.contains("-no-remote"))
}

@Test(arguments: [BrowserRunningState.stopped, .running])
func firefoxBrowserLevelPrivateLaunch(state: BrowserRunningState) {
    let url = URL(string: "https://example.com")!
    let plan = BrowserLaunchPlan.firefox(url: url, profilePath: nil, privateWindow: true, runningState: state)
    #expect(plan.arguments == ["-private-window", url.absoluteString])
    #expect(plan.delivery == (state == .stopped ? .launchApplication : .forward))
}
