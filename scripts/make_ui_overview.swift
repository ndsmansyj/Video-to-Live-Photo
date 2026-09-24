import AppKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else {
    fputs("usage: make_ui_overview.swift OUTPUT.jpg INPUT.png...\n", stderr)
    exit(2)
}

let output = args[0]
let inputs = Array(args.dropFirst())

let columns = 3
let cellWidth: CGFloat = 420
let imageHeight: CGFloat = 270
let labelHeight: CGFloat = 34
let cellHeight = imageHeight + labelHeight
let rows = Int(ceil(Double(inputs.count) / Double(columns)))
let canvasSize = NSSize(
    width: cellWidth * CGFloat(columns),
    height: cellHeight * CGFloat(rows)
)

let canvas = NSImage(size: canvasSize)
canvas.lockFocus()

NSColor.windowBackgroundColor.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
    .foregroundColor: NSColor.labelColor
]

for (index, path) in inputs.enumerated() {
    let col = index % columns
    let row = index / columns
    let x = CGFloat(col) * cellWidth
    let y = canvasSize.height - CGFloat(row + 1) * cellHeight

    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(
        roundedRect: NSRect(x: x + 7, y: y + 7, width: cellWidth - 14, height: cellHeight - 14),
        xRadius: 12,
        yRadius: 12
    ).fill()

    if let image = NSImage(contentsOfFile: path) {
        let source = image.size
        let available = NSSize(width: cellWidth - 28, height: imageHeight - 20)
        let scale = min(available.width / max(source.width, 1), available.height / max(source.height, 1))
        let targetSize = NSSize(width: source.width * scale, height: source.height * scale)
        let target = NSRect(
            x: x + (cellWidth - targetSize.width) / 2,
            y: y + labelHeight + (imageHeight - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        image.draw(in: target)
    }

    let label = URL(fileURLWithPath: path)
        .deletingPathExtension()
        .lastPathComponent
        .replacingOccurrences(of: "-", with: " ")
    NSString(string: label).draw(
        at: NSPoint(x: x + 18, y: y + 13),
        withAttributes: attributes
    )
}

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let jpeg = bitmap.representation(
        using: .jpeg,
        properties: [.compressionFactor: 0.68]
      ) else {
    fputs("failed to encode overview\n", stderr)
    exit(3)
}

try jpeg.write(to: URL(fileURLWithPath: output), options: .atomic)
print(output)
