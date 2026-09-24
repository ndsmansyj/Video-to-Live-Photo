import AppKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else {
    fputs("usage: make_ui_overview.swift OUTPUT.png INPUT.png...\n", stderr)
    exit(2)
}

let output = args[0]
let inputs = Array(args.dropFirst())

let columns: Int
switch inputs.count {
case 0...4:
    columns = 2
case 5...9:
    columns = 3
default:
    columns = 4
}

let cellWidth: CGFloat = 1200
let imageHeight: CGFloat = 780
let labelHeight: CGFloat = 84
let cellHeight = imageHeight + labelHeight
let rows = Int(ceil(Double(inputs.count) / Double(columns)))
let canvasSize = NSSize(
    width: cellWidth * CGFloat(columns),
    height: cellHeight * CGFloat(rows)
)

let canvas = NSImage(size: canvasSize)
canvas.lockFocus()

let canvasBackground = NSColor(calibratedWhite: 0.94, alpha: 1)
let cardFill = NSColor(calibratedWhite: 0.995, alpha: 1)
let cardBorder = NSColor(calibratedWhite: 0.78, alpha: 0.85)
let dividerColor = NSColor(calibratedWhite: 0.84, alpha: 0.75)

canvasBackground.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
    .foregroundColor: NSColor.labelColor
]

for (index, path) in inputs.enumerated() {
    let col = index % columns
    let row = index / columns
    let x = CGFloat(col) * cellWidth
    let y = canvasSize.height - CGFloat(row + 1) * cellHeight

    let cardRect = NSRect(
        x: x + 18,
        y: y + 18,
        width: cellWidth - 36,
        height: cellHeight - 36
    )
    let card = NSBezierPath(
        roundedRect: cardRect,
        xRadius: 22,
        yRadius: 22
    )

    cardFill.setFill()
    card.fill()

    cardBorder.setStroke()
    card.lineWidth = 2
    card.stroke()

    dividerColor.setStroke()
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: cardRect.minX + 20, y: y + labelHeight + 12))
    divider.line(to: NSPoint(x: cardRect.maxX - 20, y: y + labelHeight + 12))
    divider.lineWidth = 1.5
    divider.stroke()

    if let image = NSImage(contentsOfFile: path) {
        let source = image.size
        let available = NSSize(width: cellWidth - 72, height: imageHeight - 54)
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
        at: NSPoint(x: x + 42, y: y + 28),
        withAttributes: attributes
    )
}

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to encode overview\n", stderr)
    exit(3)
}

try png.write(to: URL(fileURLWithPath: output), options: .atomic)
print(output)
