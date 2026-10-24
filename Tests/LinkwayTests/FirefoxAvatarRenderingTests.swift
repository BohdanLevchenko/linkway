import AppKit
import LinkwayCore
import Testing

private let contextPaintSVG = """
<svg width="80" height="80" viewBox="0 0 80 80" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M0 40C0 62 18 80 40 80C62 80 80 62 80 40C80 18 62 0 40 0C18 0 0 18 0 40Z" fill="context-fill"/>
<rect x="30" y="30" width="20" height="20" fill="context-stroke"/>
</svg>
"""

@MainActor
private func opaqueCoverage(_ data: Data) throws -> (center: Bool, corner: Bool) {
    let image = try #require(NSImage(data: data))
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80, bitsPerSample: 8,
                                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: 80, height: 80))
    NSGraphicsContext.restoreGraphicsState()
    let alpha = { (x: Int, y: Int) in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
    return (alpha(40, 40) > 0.5, alpha(12, 40) > 0.5)
}

@MainActor @Test func resolvedFirefoxGlyphDrawsOnlyTheGlyph() throws {
    let coverage = try opaqueCoverage(FirefoxAvatar.templateGlyph(Data(contextPaintSVG.utf8)))
    #expect(coverage.center)
    #expect(!coverage.corner)
}
