import Foundation
import LinkwayCore
import Testing

private func parse(_ json: String) throws(ChromiumLocalStateError) -> [ChromiumProfile] {
    try ChromiumLocalState.profiles(from: Data(json.utf8))
}

@Test func ordersByProfilesOrderThenDirectory() throws {
    let profiles = try parse("""
    {
      "browser": {"enabled_labs_experiments": []},
      "profile": {
        "info_cache": {
          "Default": {"name": "Personal", "user_name": "me@example.com", "avatar_icon": "x"},
          "Profile 10": {"name": "Ten"},
          "Profile 2": {"name": "Two"},
          "Profile 1": {"name": "Work", "user_name": ""},
          "Profile 3": {"name": "Three"}
        },
        "profiles_order": ["Profile 1", "Default", "Missing"],
        "last_used": "Default"
      }
    }
    """)
    #expect(profiles.map(\.directory) == ["Profile 1", "Default", "Profile 2", "Profile 3", "Profile 10"])
    #expect(profiles[0] == ChromiumProfile(directory: "Profile 1", displayName: "Work", email: nil))
    #expect(profiles[1] == ChromiumProfile(directory: "Default", displayName: "Personal", email: "me@example.com"))
}

@Test func fallsBackForMissingOrMistypedNames() throws {
    let profiles = try parse("""
    {"profile": {"info_cache": {
      "Default": {},
      "Profile 1": {"name": 42, "gaia_name": "Account Name"},
      "Profile 2": {"name": "Person 2", "gaia_name": "Jane", "is_using_default_name": true},
      "Profile 3": {"name": "   ", "is_ephemeral": "yes"}
    }}}
    """)
    #expect(profiles.map(\.displayName) == ["Default", "Account Name", "Jane", "Profile 3"])
}

@Test func skipsEphemeralAndGuestProfiles() throws {
    let profiles = try parse("""
    {"profile": {"info_cache": {
      "Default": {"name": "Main"},
      "Profile 4": {"name": "Temp", "is_ephemeral": true},
      "Profile 5": {"name": "Guest", "is_guest": true},
      "Guest Profile": {"name": "Guest"},
      "System Profile": {"name": "System"}
    }}}
    """)
    #expect(profiles.map(\.directory) == ["Default"])
}

@Test func toleratesMissingProfileSection() throws {
    #expect(try parse("{}").isEmpty)
    #expect(try parse(#"{"profile": {"info_cache": []}}"#).isEmpty)
    #expect(try parse(#"{"profile": "nonsense"}"#).isEmpty)
}

@Test(arguments: ["", "not json", "[1, 2]", "{\"profile\": ", "null"])
func rejectsGarbage(input: String) {
    #expect(throws: ChromiumLocalStateError.invalidJSON) { try parse(input) }
}
