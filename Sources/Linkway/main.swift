import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
#if DEBUG
let previewStyle = CommandLine.arguments.first { $0.hasPrefix("--picker-preview=") }
if let previewStyle {
    application.setActivationPolicy(.accessory)
    application.finishLaunching()
    PickerController.debugPresentSample(style: previewStyle.hasSuffix("list") ? .list : .tiles)
} else {
    application.delegate = delegate
}
#else
application.delegate = delegate
#endif
application.setActivationPolicy(.accessory)
application.run()
