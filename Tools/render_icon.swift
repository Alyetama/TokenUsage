import AppKit

// Renders a 1024×1024 PNG app-icon glyph: a macOS squircle tile with a rich
// violet→cyan gradient, a glassy top-left highlight, and a gradient-stroked
// speedometer gauge with a glowing needle — "measuring token usage".
// Usage: swift render_icon.swift <out.png>

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S = 1024.0

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}
func rad(_ deg: Double) -> CGFloat { CGFloat(deg * .pi / 180) }

// Apple-style squircle (superellipse, n≈5) filling the standard 824/1024 grid.
func squircle(_ rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = pow(abs(ct), 2 / n) * a * (ct < 0 ? -1 : 1)
        let y = pow(abs(st), 2 / n) * b * (st < 0 ? -1 : 1)
        let pt = CGPoint(x: cx + x, y: cy + y)
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.closeSubpath()
    return path
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(tile)

// --- Soft drop shadow beneath the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 70, color: rgb(0.05, 0.05, 0.18, 0.55))
ctx.addPath(shape); ctx.setFillColor(rgb(0.20, 0.18, 0.55)); ctx.fillPath()
ctx.restoreGState()

// --- Background: diagonal violet → cyan gradient with a glassy top-left sheen.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
if let grad = CGGradient(colorsSpace: space,
                         colors: [rgb(0.44, 0.36, 0.98),
                                  rgb(0.36, 0.44, 0.97),
                                  rgb(0.13, 0.75, 0.86)] as CFArray,
                         locations: [0, 0.45, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 180, y: S - 150),
                           end: CGPoint(x: S - 150, y: 150), options: [])
}
if let sheen = CGGradient(colorsSpace: space,
                          colors: [rgb(1, 1, 1, 0.35), rgb(1, 1, 1, 0)] as CFArray,
                          locations: [0, 1]) {
    ctx.drawRadialGradient(sheen,
                           startCenter: CGPoint(x: 320, y: S - 300), startRadius: 0,
                           endCenter: CGPoint(x: 320, y: S - 300), endRadius: 620,
                           options: [])
}
ctx.restoreGState()

// --- Glass rim.
ctx.saveGState()
ctx.addPath(shape); ctx.setLineWidth(3); ctx.setStrokeColor(rgb(1, 1, 1, 0.18)); ctx.strokePath()
ctx.restoreGState()

let white = rgb(1, 1, 1)
let cx = 512.0, cy = 476.0, R = 270.0
let startDeg = 208.0, endDeg = -28.0        // sweep across the top, clockwise
let valueDeg = 48.0                          // needle / fill target (~72%)

func arcPath(_ from: Double, _ to: Double) -> CGPath {
    let p = CGMutablePath()
    p.addArc(center: CGPoint(x: cx, y: cy), radius: R,
             startAngle: rad(from), endAngle: rad(to), clockwise: true)
    return p
}

// --- Track (faint) behind the value arc.
ctx.saveGState()
ctx.setLineCap(.round); ctx.setLineWidth(78)
ctx.setStrokeColor(rgb(1, 1, 1, 0.22))
ctx.addPath(arcPath(startDeg, endDeg)); ctx.strokePath()
ctx.restoreGState()

// --- Value arc: a gradient-filled thick arc (white → soft cyan) with a glow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 26, color: rgb(1, 1, 1, 0.45))
ctx.setLineCap(.round); ctx.setLineWidth(78)
ctx.addPath(arcPath(startDeg, valueDeg))
ctx.replacePathWithStrokedPath()
ctx.clip()
if let g = CGGradient(colorsSpace: space,
                      colors: [rgb(0.80, 0.98, 1.0), white] as CFArray,
                      locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: cx - R, y: cy),
                           end: CGPoint(x: cx + R, y: cy + R), options: [])
}
ctx.restoreGState()

// --- Tick marks just outside the band.
ctx.saveGState()
ctx.setStrokeColor(rgb(1, 1, 1, 0.9)); ctx.setLineWidth(13); ctx.setLineCap(.round)
for i in 0...6 {
    let a = rad(startDeg - (startDeg - endDeg) * Double(i) / 6)
    let inner = R + 58, outer = R + 88
    ctx.move(to: CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
    ctx.addLine(to: CGPoint(x: cx + cos(a) * outer, y: cy + sin(a) * outer))
}
ctx.strokePath()
ctx.restoreGState()

// --- Needle with a soft glow, plus a hub.
let na = rad(valueDeg)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0.06, 0.10, 0.34, 0.5))
ctx.setStrokeColor(white); ctx.setLineCap(.round); ctx.setLineWidth(32)
ctx.move(to: CGPoint(x: cx - cos(na) * 62, y: cy - sin(na) * 62))
ctx.addLine(to: CGPoint(x: cx + cos(na) * (R - 6), y: cy + sin(na) * (R - 6)))
ctx.strokePath()
ctx.restoreGState()

// Hub: white disc with a violet core.
ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: cx - 58, y: cy - 58, width: 116, height: 116))
ctx.setFillColor(rgb(0.42, 0.36, 0.98))
ctx.fillEllipse(in: CGRect(x: cx - 27, y: cy - 27, width: 54, height: 54))

// --- Write out the PNG.
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: out))
print("✓ wrote \(out)")
