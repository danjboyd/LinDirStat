// Draws LinDirStat's macOS icon: a cushion treemap in WinDirStat's colours
// on Apple's rounded-square icon grid. Usage: swift make-icon.swift out.png
import AppKit

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Apple's grid: an 824-point body centred in 1024, corner radius ~185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape)
ctx.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()

func rgb(_ r: Int, _ g: Int, _ b: Int) -> (CGFloat, CGFloat, CGFloat) {
  (CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255)
}
let palette = [rgb(64, 96, 255), rgb(255, 64, 64), rgb(64, 220, 64), rgb(255, 220, 0),
               rgb(0, 210, 230), rgb(230, 0, 230), rgb(255, 150, 20), rgb(140, 140, 160)]

// A cushion: the colour with a soft highlight up and to the left, darker at
// the edges, like WinDirStat's shading.
func cushion(_ r: CGRect, _ c: (CGFloat, CGFloat, CGFloat)) {
  ctx.saveGState()
  ctx.clip(to: r)
  let light = CGColor(red: min(1, c.0 * 1.25 + 0.25), green: min(1, c.1 * 1.25 + 0.25), blue: min(1, c.2 * 1.25 + 0.25), alpha: 1)
  let mid = CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
  let dark = CGColor(red: c.0 * 0.35, green: c.1 * 0.35, blue: c.2 * 0.35, alpha: 1)
  let g = CGGradient(colorsSpace: space, colors: [light, mid, dark] as CFArray, locations: [0, 0.55, 1])!
  let centre = CGPoint(x: r.minX + r.width * 0.38, y: r.minY + r.height * 0.62)
  let radius = max(r.width, r.height) * 0.78
  ctx.drawRadialGradient(g, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius,
                         options: [.drawsAfterEndLocation])
  ctx.restoreGState()
}

// A fixed squarified-looking layout (y grows upwards).
let x0 = body.minX, y0 = body.minY, w = body.width, h = body.height
var cells: [(CGRect, Int)] = []
let leftW = w * 0.56
cells.append((CGRect(x: x0, y: y0 + h * 0.42, width: leftW, height: h * 0.58), 0))
cells.append((CGRect(x: x0, y: y0, width: leftW * 0.58, height: h * 0.42), 1))
cells.append((CGRect(x: x0 + leftW * 0.58, y: y0 + h * 0.18, width: leftW * 0.42, height: h * 0.24), 3))
cells.append((CGRect(x: x0 + leftW * 0.58, y: y0, width: leftW * 0.42, height: h * 0.18), 5))
let rx = x0 + leftW, rw = w - leftW
cells.append((CGRect(x: rx, y: y0 + h * 0.64, width: rw, height: h * 0.36), 2))
cells.append((CGRect(x: rx, y: y0 + h * 0.36, width: rw * 0.55, height: h * 0.28), 4))
cells.append((CGRect(x: rx + rw * 0.55, y: y0 + h * 0.36, width: rw * 0.45, height: h * 0.28), 6))
// Many small files, as in a real scan.
let smallTop = y0 + h * 0.36
var sx = rx
let widths: [CGFloat] = [0.30, 0.22, 0.18, 0.12, 0.10, 0.08]
for (i, f) in widths.enumerated() {
  let cw = rw * f
  let rows = i < 2 ? 2 : 3
  for j in 0..<rows {
    let ch = smallTop / 1 - y0
    let rh = ch / CGFloat(rows)
    cells.append((CGRect(x: sx, y: y0 + CGFloat(j) * rh, width: cw, height: rh), (i * 3 + j + 1) % palette.count))
  }
  sx += cw
}
for (r, c) in cells { cushion(r, palette[c]) }

// WinDirStat's thin grid between cells.
ctx.setStrokeColor(CGColor(gray: 0.05, alpha: 0.85))
ctx.setLineWidth(5)
for (r, _) in cells { ctx.stroke(r) }

// A soft top gloss so it sits with other macOS icons.
let gloss = CGGradient(colorsSpace: space,
                       colors: [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
ctx.restoreGState()

// Inner edge so the shape reads on dark Docks.
ctx.addPath(shape)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
ctx.setLineWidth(3)
ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
