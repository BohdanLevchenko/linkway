import Foundation
import JavaScriptCore
import LinkwayCore
import Testing

private var chromiumExtensionURL: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Extensions/chromium", isDirectory: true)
}

private let browserLinks = [
    "https://example.com/a?one=1&two=2#fragment?three=3",
    "https://example.com/%2F?q=a%26b&v=2#part%20two",
    "https://example.com/привіт?q=世界#café",
    "https://bücher.de/é?q=✓#片",
    "https://example.com/a!'()*?q=100%25#%23",
    "mailto:hello@example.com?subject=Hello%20世界&body=a%26b#fragment",
]

@Test(arguments: browserLinks)
func extensionJavaScriptRoundTrip(link: String) throws {
    let context = try #require(JSContext())
    let source = try String(contentsOf: chromiumExtensionURL.appendingPathComponent("linkway.js"), encoding: .utf8)
    context.evaluateScript(source.replacingOccurrences(of: "export function", with: "function"))
    #expect(context.exception == nil)
    let builder = try #require(context.objectForKeyedSubscript("buildLinkwayURL"))
    for mode in ["prompt", "open"] {
        let result = try #require(builder.call(withArguments: [link, mode])?.toString())
        #expect(context.exception == nil)
        #expect(result.hasPrefix("linkway://\(mode)?url="))
        let command = try SchemeCommand.parse(#require(URL(string: result))).get()
        #expect(command.link == URL(string: link))
        #expect(command.link.absoluteString == URL(string: link)?.absoluteString)
        #expect(command.mode == (mode == "open" ? .route : .prompt(scope: .all)))
    }
}

@Test func extensionJavaScriptRejectsUnsafeInput() throws {
    let context = try #require(JSContext())
    let source = try String(contentsOf: chromiumExtensionURL.appendingPathComponent("linkway.js"), encoding: .utf8)
    context.evaluateScript(source.replacingOccurrences(of: "export function", with: "function"))
    let builder = try #require(context.objectForKeyedSubscript("buildLinkwayURL"))
    for input in ["javascript:alert(1)", "file:///tmp/a", "chrome://settings", "linkway://prompt?url=x", "", "https://", "https://?q=x",
                  "https://example.com/\n", String(repeating: "a", count: 32769), "https://example.com/" + String(repeating: "a", count: 32768)] {
        for mode in ["prompt", "open"] {
            #expect(builder.call(withArguments: [input, mode])?.isNull == true)
        }
    }
    #expect(builder.call(withArguments: ["https://example.com", "invalid"])?.isNull == true)
    #expect(builder.call(withArguments: [NSNull(), "prompt"])?.isNull == true)
    let atLimit = "https://example.com/" + String(repeating: "a", count: 32768 - "https://example.com/".count)
    #expect(builder.call(withArguments: [atLimit, "prompt"])?.isString == true)
    #expect(context.exception == nil)
}

@Test(arguments: browserLinks)
func bookmarkletJavaScriptRoundTrip(link: String) throws {
    let context = try #require(JSContext())
    context.setObject(["href": link], forKeyedSubscript: "location" as NSString)
    let code = try #require(BrowserIntegration.bookmarklet.range(of: "javascript:"))
    let result = context.evaluateScript(String(BrowserIntegration.bookmarklet[code.upperBound...]))
    #expect(result?.isUndefined == true)
    #expect(context.exception == nil)
    let assigned = try #require(context.evaluateScript("location.href")?.toString())
    let command = try SchemeCommand.parse(#require(URL(string: assigned))).get()
    #expect(command.link.absoluteString == URL(string: link)?.absoluteString)
    #expect(command.mode == .prompt(scope: .all))
}

@Test func chromiumManifestIsMinimalAndHasIcons() throws {
    let data = try Data(contentsOf: chromiumExtensionURL.appendingPathComponent("manifest.json"))
    let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(manifest["manifest_version"] as? Int == 3)
    #expect(manifest["name"] as? String == "Linkway")
    #expect(manifest["version"] as? String == "1.0.0")
    #expect(manifest["minimum_chrome_version"] as? String == "116")
    let permissions = try #require(manifest["permissions"] as? [String])
    #expect(permissions.count == 2)
    #expect(Set(permissions) == ["contextMenus", "activeTab"])
    for key in ["host_permissions", "optional_permissions", "optional_host_permissions", "content_scripts"] {
        #expect(manifest[key] == nil)
    }
    let background = try #require(manifest["background"] as? [String: String])
    #expect(background == ["service_worker": "background.js", "type": "module"])
    let icons = try #require(manifest["icons"] as? [String: String])
    #expect(Set(icons.keys) == ["16", "32", "48", "128"])
    for (size, path) in icons {
        let icon = try Data(contentsOf: chromiumExtensionURL.appendingPathComponent(path))
        #expect(Array(icon.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        let expected = try #require(UInt32(size))
        #expect(icon.count > 24)
        let width = icon[16..<20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let height = icon[20..<24].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        #expect(width == expected)
        #expect(height == expected)
    }
}

@Test func extensionEventsUseInvokingTabAndExpectedModes() throws {
    let context = try #require(JSContext())
    context.evaluateScript("""
        const listeners = {};
        const updates = [];
        const menus = [];
        const chrome = {
          runtime: { onInstalled: { addListener: fn => listeners.install = fn } },
          contextMenus: {
            removeAll: fn => fn(), create: menu => menus.push(menu),
            onClicked: { addListener: fn => listeners.menu = fn }
          },
          action: { onClicked: { addListener: fn => listeners.action = fn } },
          commands: { onCommand: { addListener: fn => listeners.command = fn } },
          tabs: { update: (id, options) => { updates.push({ id, url: options.url }); return Promise.resolve(); } }
        };
        """)
    let builder = try String(contentsOf: chromiumExtensionURL.appendingPathComponent("linkway.js"), encoding: .utf8)
    let background = try String(contentsOf: chromiumExtensionURL.appendingPathComponent("background.js"), encoding: .utf8)
    context.evaluateScript(builder.replacingOccurrences(of: "export function", with: "function"))
    context.evaluateScript(background.replacingOccurrences(of: "import { buildLinkwayURL } from \"./linkway.js\";", with: ""))
    context.evaluateScript("""
        listeners.install();
        listeners.action({ id: 42, url: 'https://example.com/?q=1#f' });
        listeners.command('open-page', { id: 42, url: 'https://example.com/?q=1#f' });
        listeners.menu({ menuItemId: 'prompt-page', pageUrl: 'https://example.com/?q=1#f' }, { id: 42 });
        listeners.menu({ menuItemId: 'prompt-link', linkUrl: 'mailto:a@example.com?subject=Hi%20there' }, { id: 42 });
        listeners.menu({ menuItemId: 'route-link', linkUrl: 'https://example.com/?q=1#f' }, { id: 42 });
        listeners.action({ id: 42, url: 'chrome://settings' });
        listeners.menu({ menuItemId: 'route-link', linkUrl: 'javascript:alert(1)' }, { id: 42 });
        listeners.command('unknown', { id: 42, url: 'https://example.com' });
        listeners.command('open-page');
        listeners.action({ url: 'https://example.com' });
        """)
    #expect(context.exception == nil)
    let menus = try #require(context.evaluateScript("menus")?.toArray() as? [[String: Any]])
    #expect(menus.compactMap { $0["id"] as? String } == ["prompt-link", "prompt-page", "route-link"])
    let updates = try #require(context.evaluateScript("updates")?.toArray() as? [[String: Any]])
    #expect(updates.count == 5)
    for (index, update) in updates.enumerated() {
        #expect(update["id"] as? Int == 42)
        let value = try #require(update["url"] as? String)
        let url = try #require(URL(string: value))
        let command = try SchemeCommand.parse(url).get()
        #expect(command.mode == (index == 4 ? .route : .prompt(scope: .all)))
        #expect(command.link.absoluteString == (index == 3 ? "mailto:a@example.com?subject=Hi%20there" : "https://example.com/?q=1#f"))
    }
}
