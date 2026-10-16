import AppKit
import Foundation

// Renders a 1024×1024 macOS app icon: a gradient squircle with a white bolt.
// Usage: swift scripts/make_icon.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let side: CGFloat = 1024

let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// Tile geometry (leave a margin like standard macOS icons).
let inset: CGFloat = 86
let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let radius = rect.width * 0.235
let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Soft drop shadow for the tile.
NSGraphicsContext.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
tileShadow.shadowBlurRadius = 36
tileShadow.shadowOffset = NSSize(width: 0, height: -16)
tileShadow.set()
NSColor.black.setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()

// Gradient fill (clipped to the tile).
NSGraphicsContext.saveGraphicsState()
tile.addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.20, green: 0.92, blue: 0.52, alpha: 1.0),
    NSColor(srgbRed: 0.05, green: 0.66, blue: 0.62, alpha: 1.0),
    NSColor(srgbRed: 0.02, green: 0.46, blue: 0.66, alpha: 1.0),
])!
gradient.draw(in: rect, angle: -60)

// Bright sheen radiating from the top-left corner.
let sheen = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.28),
    NSColor.white.withAlphaComponent(0.0),
])!
sheen.draw(
    fromCenter: NSPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY - rect.height * 0.20),
    radius: 0,
    toCenter: NSPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY - rect.height * 0.20),
    radius: rect.width * 0.85,
    options: []
)

// Gentle vignette in the bottom-right for depth.
let vignette = NSGradient(colors: [
    NSColor.black.withAlphaComponent(0.0),
    NSColor.black.withAlphaComponent(0.18),
])!
vignette.draw(in: rect, angle: -60)
NSGraphicsContext.restoreGraphicsState()

// White bolt, recolored from the SF Symbol glyph.
let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .heavy)
if let base = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil),
   let glyph = base.withSymbolConfiguration(config) {
    let size = glyph.size
    let boltRect = NSRect(
        x: (side - size.width) / 2,
        y: (side - size.height) / 2,
        width: size.width,
        height: size.height
    )
    let whiteBolt = NSImage(size: size, flipped: false) { rect in
        glyph.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }

    // Soft white glow so the bolt reads as energetic.
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor.white.withAlphaComponent(0.65)
    glow.shadowBlurRadius = 44
    glow.shadowOffset = .zero
    glow.set()
    whiteBolt.draw(in: boltRect)
    NSGraphicsContext.restoreGraphicsState()

    // Crisp bolt with a subtle contact shadow.
    NSGraphicsContext.saveGraphicsState()
    let boltShadow = NSShadow()
    boltShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
    boltShadow.shadowBlurRadius = 22
    boltShadow.shadowOffset = NSSize(width: 0, height: -8)
    boltShadow.set()
    whiteBolt.draw(in: boltRect)
    NSGraphicsContext.restoreGraphicsState()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
