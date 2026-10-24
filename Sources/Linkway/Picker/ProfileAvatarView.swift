import AppKit
import LinkwayCore
import SwiftUI

struct ProfileAvatarView: View {
    let destination: Destination
    let size: CGFloat
    let avatarProvider: @MainActor (Destination) -> NSImage?
    @State private var firefoxImage: NSImage?

    private var name: String { destination.profileName ?? destination.appName }
    private var glyph: Bool { destination.firefoxAvatar.map(FirefoxAvatar.isGlyph) ?? false }

    var body: some View {
        ZStack {
            Circle().fill(background)
            if let image = firefoxImage ?? (destination.firefoxAvatar == nil ? avatarProvider(destination) : nil) {
                if glyph {
                    Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
                        .foregroundStyle(color(destination.foregroundColorARGB) ?? .primary)
                        .padding(size * 0.18)
                } else {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            } else {
                Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(color(destination.foregroundColorARGB) ?? .white)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: destination) {
            firefoxImage = nil
            guard let avatar = destination.firefoxAvatar else { return }
            let app = destination.appURL
            let customURL = destination.avatarURL
            let data = await Task.detached(priority: .utility) {
                if !FirefoxAvatar.isGlyph(avatar), let customURL { return try? Data(contentsOf: customURL) }
                return FirefoxAvatar.data(for: avatar, appURL: app)
            }.value
            guard !Task.isCancelled else { return }
            firefoxImage = data.flatMap(NSImage.init(data:)).flatMap { $0.drawsVisiblePixels ? $0 : nil }
        }
        .accessibilityHidden(true)
    }

    private var background: Color {
        if let color = color(destination.highlightColorARGB) { return color }
        let hash = name.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.65)
    }

    private func color(_ argb: Int?) -> Color? {
        guard let argb else { return nil }
        let bits = UInt32(truncatingIfNeeded: argb)
        return Color(red: Double((bits >> 16) & 255) / 255, green: Double((bits >> 8) & 255) / 255,
                     blue: Double(bits & 255) / 255, opacity: Double(bits >> 24) / 255)
    }
}

private extension NSImage {
    private static let probeSide = 32

    var drawsVisiblePixels: Bool {
        let side = Self.probeSide
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<side).contains { x in (0..<side).contains { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 } }
    }
}
