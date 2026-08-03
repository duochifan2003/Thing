import AppKit
import Foundation

let outputPath = CommandLine.arguments[1]
let size = NSSize(width: 900, height: 560)
guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
  ),
  let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
else {
  fatalError("Unable to create DMG background canvas")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func text(
  _ value: String,
  in rect: NSRect,
  font: NSFont,
  color: NSColor,
  alignment: NSTextAlignment = .left
) {
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = alignment
  paragraph.lineBreakMode = .byWordWrapping
  value.draw(
    in: rect,
    withAttributes: [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ]
  )
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
  fill.setFill()
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func line(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat) {
  color.setStroke()
  let path = NSBezierPath()
  path.move(to: start)
  path.line(to: end)
  path.lineWidth = width
  path.lineCapStyle = .round
  path.stroke()
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

color(0.98, 0.99, 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

color(0.93, 0.97, 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 410, width: size.width, height: 150)).fill()

color(0.20, 0.48, 0.84).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 556, width: size.width, height: 4)).fill()

let titleFont = NSFont(name: "PingFangSC-Semibold", size: 32) ?? NSFont.systemFont(ofSize: 32, weight: .semibold)
let subtitleFont = NSFont(name: "PingFangSC-Regular", size: 17) ?? NSFont.systemFont(ofSize: 17)
let promptFont = NSFont(name: "PingFangSC-Semibold", size: 24) ?? NSFont.systemFont(ofSize: 24, weight: .semibold)
let bodyFont = NSFont(name: "PingFangSC-Regular", size: 15) ?? NSFont.systemFont(ofSize: 15)
let smallFont = NSFont(name: "PingFangSC-Regular", size: 13) ?? NSFont.systemFont(ofSize: 13)

text("Thing", in: NSRect(x: 64, y: 488, width: 260, height: 44), font: titleFont, color: color(0.08, 0.16, 0.28))
text("macOS 安装指南", in: NSRect(x: 66, y: 458, width: 300, height: 28), font: subtitleFont, color: color(0.27, 0.37, 0.49))
text("本地优先的人物与事件档案工具", in: NSRect(x: 520, y: 468, width: 310, height: 24), font: smallFont, color: color(0.27, 0.37, 0.49), alignment: .right)

text("将 Thing 拖到 Applications", in: NSRect(x: 0, y: 365, width: 900, height: 36), font: promptFont, color: color(0.08, 0.16, 0.28), alignment: .center)
text("完成后，从“应用程序”打开 Thing", in: NSRect(x: 0, y: 335, width: 900, height: 24), font: bodyFont, color: color(0.35, 0.43, 0.52), alignment: .center)

let arrowColor = color(0.20, 0.48, 0.84)
line(from: NSPoint(x: 300, y: 278), to: NSPoint(x: 600, y: 278), color: arrowColor, width: 5)
line(from: NSPoint(x: 600, y: 278), to: NSPoint(x: 574, y: 296), color: arrowColor, width: 5)
line(from: NSPoint(x: 600, y: 278), to: NSPoint(x: 574, y: 260), color: arrowColor, width: 5)
roundedRect(NSRect(x: 396, y: 291, width: 108, height: 32), radius: 16, fill: color(0.20, 0.48, 0.84))
text("拖动安装", in: NSRect(x: 396, y: 298, width: 108, height: 20), font: smallFont, color: .white, alignment: .center)

text("安装完成后推出磁盘映像，从“应用程序”打开 Thing。", in: NSRect(x: 0, y: 112, width: 900, height: 24), font: bodyFont, color: color(0.27, 0.37, 0.49), alignment: .center)
text("首次打开遇到安全提示：在 Finder 中右键 Thing，选择“打开”。", in: NSRect(x: 0, y: 80, width: 900, height: 24), font: smallFont, color: color(0.35, 0.43, 0.52), alignment: .center)

guard
  let png = bitmap.representation(using: .png, properties: [:])
else {
  fatalError("Unable to encode DMG background")
}

try png.write(to: URL(fileURLWithPath: outputPath))
