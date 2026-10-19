import AppKit
import LinkwayCore
import Testing
@testable import Linkway

@MainActor private func samplePicker(count: Int) -> PickerModel {
    let destinations = (0..<count).map { index in
        Destination(id: DestinationID(bundleID: "browser.\(index % 2)", profileKey: "\(index)"),
                    kind: .browser, appName: "Browser", profileName: "Profile \(index)",
                    appURL: URL(fileURLWithPath: "/Applications/Sample.app"), supportsPrivateWindow: index == 0)
    }
    return PickerModel(link: IncomingLink(url: URL(string: "https://example.com/a/path")!,
                                             receivedAt: Date(), senderBundleID: nil, forcePicker: true),
                       destinations: destinations,
                       rememberTargets: [RememberTarget(label: "example.com", condition: .hostExact("example.com"))],
                       style: .tiles)
}

@Test @MainActor func tilesKeepIncomingOrderAndReserveOverflowSlot() {
    let picker = samplePicker(count: 7)
    #expect(picker.tiles == picker.destinations.prefix(5).map(PickerTile.destination) + [.allOptions])
    let six = samplePicker(count: 6)
    #expect(six.tiles == six.destinations.map(PickerTile.destination))
    #expect(samplePicker(count: 0).tiles.isEmpty)
}

@Test @MainActor func overflowSelectionSwitchesToListAndKeepsRememberScope() {
    let picker = samplePicker(count: 7)
    picker.cycleRememberScope()
    picker.moveSelection(by: 5)
    picker.openSelected()
    #expect(picker.presentation == .list)
    #expect(picker.rememberIndex == 0)
    var opened: LaunchRequest?
    picker.onResult = { if case .open(let request, _) = $0 { opened = request } }
    #expect(picker.pickDigit(1))
    #expect(opened == nil)
    #expect(picker.pickDigit(2))
    #expect(opened?.destination == picker.destinations[2].id)
}

@Test @MainActor func tileSelectionOpensIncomingDestinationWithPrivateAndRememberState() {
    let picker = samplePicker(count: 7)
    picker.shiftHeld = true
    picker.cycleRememberScope()
    var opened: LaunchRequest?
    var remembered: RememberTarget?
    picker.onResult = { if case .open(let request, let target) = $0 { opened = request; remembered = target } }
    picker.openTile(0)
    #expect(opened?.destination == picker.destinations[0].id)
    #expect(opened?.privateWindow == true)
    #expect(remembered == picker.rememberTargets[0])
    picker.openTile(1)
    #expect(opened?.destination == picker.destinations[1].id)
    #expect(opened?.privateWindow == false)
    picker.openTile(8)
    #expect(opened?.destination == picker.destinations[1].id)
    #expect(picker.prefix == nil)
}

@Test @MainActor func destinationRefreshClampsTileSelectionAndKeepsListPresentation() {
    let picker = samplePicker(count: 7)
    picker.moveSelection(by: 5)
    picker.updateDestinations(Array(picker.destinations.prefix(1)))
    #expect(picker.selectedTile == 0)
    #expect(picker.tiles.count == 1)
    #expect(picker.tileTitle == "example.com/a/path")
    picker.showAllOptions()
    #expect(picker.presentation == .tiles)
    let overflow = samplePicker(count: 7)
    overflow.showAllOptions()
    overflow.updateDestinations(Array(overflow.destinations.prefix(1)))
    #expect(overflow.presentation == .list)
}

@Test @MainActor func tilesHandleDigitsArrowsAndCommandAWithoutListPrefix() throws {
    let picker = samplePicker(count: 7)
    let controller = PickerController()
    var opened: DestinationID?
    picker.onResult = { if case .open(let request, _) = $0 { opened = request.destination } }
    func key(_ characters: String, code: UInt16 = 0, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let digitCodes: [String: UInt16] = ["1": 18, "2": 19, "3": 20]
        return try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                     timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: digitCodes[characters] ?? code))
    }
    #expect(controller.handleKey(try key("2"), model: picker))
    #expect(opened == picker.destinations[1].id)
    #expect(picker.prefix == nil)
    #expect(controller.handleKey(try key("3", modifiers: .command), model: picker))
    #expect(opened == picker.destinations[2].id)
    #expect(!controller.handleKey(try key("1", modifiers: .control), model: picker))
    #expect(controller.handleKey(try key("", code: 124), model: picker))
    #expect(picker.selectedTile == 1)
    #expect(controller.handleKey(try key("", code: 125), model: picker))
    #expect(picker.selectedTile == 2)
    #expect(controller.handleKey(try key("", code: 123), model: picker))
    #expect(picker.selectedTile == 1)
    #expect(controller.handleKey(try key("", code: 126), model: picker))
    #expect(picker.selectedTile == 0)
    #expect(controller.handleKey(try key("a", modifiers: .command), model: picker))
    #expect(picker.presentation == .list)
    opened = nil
    #expect(controller.handleKey(try key("1"), model: picker))
    #expect(opened == nil)
    #expect(picker.prefix == .group(1))
    #expect(controller.handleKey(try key("2"), model: picker))
    #expect(opened == picker.destinations[2].id)
    picker.clearPrefix()
}
