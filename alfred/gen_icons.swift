import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/alfred_eq_icons"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, String, NSColor)] = [
    ("icon.png", "headphones.circle.fill", .systemIndigo),
    ("headphones.png", "headphones", .systemCyan),
    ("speakers.png", "hifispeaker.2.fill", .systemOrange),
    ("toggle.png", "arrow.left.arrow.right.circle.fill", .systemGreen),
    ("auto.png", "cable.connector", .systemPurple)
]

for (filename, symbol, color) in specs {
    let size = NSSize(width: 256, height: 256)
    let cfg = NSImage.SymbolConfiguration(pointSize: 170, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    guard let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else {
        fputs("Missing SF Symbol: \(symbol)\n", stderr)
        continue
    }

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 256,
        pixelsHigh: 256,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let symSize = sym.size
    let rect = NSRect(
        x: (size.width - symSize.width) / 2,
        y: (size.height - symSize.height) / 2,
        width: symSize.width,
        height: symSize.height
    )
    sym.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()

    if let png = rep.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: "\(outDir)/\(filename)"))
    }
}
