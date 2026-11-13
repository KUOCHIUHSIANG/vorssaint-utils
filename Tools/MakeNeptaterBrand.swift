// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

// Draws Neptater's brand masters, which Tools/MakeIcon.swift then turns into
// the app icon, the menu bar glyph and the in-app mark:
// - Resources/Brand/AppIcon-Default.png: Neptune on a starry squircle, with its
//   trident (♆) laid over the planet, macOS icon grid margins baked in
// - Resources/Brand/logo.png: Neptune as a silhouette whose cloud bands are cut
//   out, the way the original mark cut its ring out of the planet
// Run from the repository root: swift Tools/MakeNeptaterBrand.swift
import AppKit

let canvas = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func bitmapContext() -> CGContext {
    CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map { color($0.0, $0.1) } as CFArray,
               locations: stops.map { $0.2 })!
}

func write(_ image: CGImage, to path: String) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// MARK: - Trident

/// The trident in a unit space: x in -0.5...0.5, y in 0...1 (bottom-up).
func tridentShapes() -> [CGPath] {
    let stroke: CGFloat = 0.1
    var shapes: [CGPath] = []
    // Shaft, from the butt up into the notch of the central spearhead.
    shapes.append(CGPath(rect: CGRect(x: -stroke / 2, y: 0, width: stroke, height: 0.91), transform: nil))
    // Cross guard on the handle, as in the astronomical symbol.
    shapes.append(CGPath(roundedRect: CGRect(x: -0.17, y: 0.15, width: 0.34, height: stroke),
                         cornerWidth: stroke / 2, cornerHeight: stroke / 2, transform: nil))
    // The U that carries the outer prongs, vertical where it meets them.
    let arms = CGMutablePath()
    arms.move(to: CGPoint(x: -0.33, y: 0.78))
    arms.addLine(to: CGPoint(x: -0.33, y: 0.74))
    arms.addQuadCurve(to: CGPoint(x: 0, y: 0.38), control: CGPoint(x: -0.33, y: 0.38))
    arms.addQuadCurve(to: CGPoint(x: 0.33, y: 0.74), control: CGPoint(x: 0.33, y: 0.38))
    arms.addLine(to: CGPoint(x: 0.33, y: 0.78))
    shapes.append(arms.copy(strokingWithWidth: stroke, lineCap: .butt, lineJoin: .round, miterLimit: 4))
    // Barbed spearheads on the three tips.
    func spearhead(x: CGFloat, base: CGFloat, height: CGFloat) -> CGPath {
        let head = CGMutablePath()
        head.move(to: CGPoint(x: x, y: base + height))
        head.addLine(to: CGPoint(x: x + 0.105, y: base - 0.02))
        head.addLine(to: CGPoint(x: x, y: base + 0.035))
        head.addLine(to: CGPoint(x: x - 0.105, y: base - 0.02))
        head.closeSubpath()
        return head
    }
    shapes.append(spearhead(x: 0, base: 0.82, height: 0.18))
    shapes.append(spearhead(x: -0.33, base: 0.76, height: 0.16))
    shapes.append(spearhead(x: 0.33, base: 0.76, height: 0.16))
    return shapes
}

func fillTrident(_ ctx: CGContext, height: CGFloat, center: CGPoint, fill: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y - height / 2)
    ctx.scaleBy(x: height, y: height)
    ctx.setFillColor(fill)
    for shape in tridentShapes() {
        ctx.addPath(shape)
        ctx.fillPath()
    }
    ctx.restoreGState()
}

/// Halfway between the trident's box center and its mass center, in its own
/// 0...1 units: the U and the spearheads weigh more than the thin handle, so
/// centering the box alone leaves it reading high.
func tridentOpticalCenter() -> CGFloat {
    let probe = bitmapContext()
    fillTrident(probe, height: CGFloat(canvas), center: CGPoint(x: canvas / 2, y: canvas / 2), fill: color(0x000000))
    let rep = NSBitmapImageRep(cgImage: probe.makeImage()!)
    var mass = 0.0, moment = 0.0
    for y in 0..<canvas {
        for x in stride(from: 0, to: canvas, by: 2) {
            let alpha = Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            mass += alpha
            moment += alpha * Double(canvas - 1 - y) / Double(canvas - 1)
        }
    }
    return (0.5 + CGFloat(moment / mass)) / 2
}

// MARK: - App icon

func drawNeptune(_ ctx: CGContext, center p: CGPoint, radius r: CGFloat) {
    let disc = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
    // Atmosphere glow.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: r * 0.18, color: color(0x5d9bff, 0.55))
    ctx.setFillColor(color(0x1d48b8))
    ctx.fillEllipse(in: disc)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: disc)
    ctx.clip()
    let lit = CGPoint(x: p.x - r * 0.38, y: p.y + r * 0.42)
    ctx.drawRadialGradient(gradient([(0x8cc0ff, 1, 0), (0x3d74e6, 1, 0.38), (0x1c45b5, 1, 0.72), (0x0b1f6b, 1, 1)]),
                           startCenter: lit, startRadius: 0, endCenter: p, endRadius: r * 1.05,
                           options: [.drawsAfterEndLocation])
    // Soft light and dark cloud bands, slightly tilted.
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: -0.12)
    let bands: [(CGFloat, CGFloat, UInt32, CGFloat)] = [
        (0.62, 0.07, 0xd8ecff, 0.22), (0.40, 0.05, 0x0a2a7a, 0.25), (0.18, 0.06, 0xbfe0ff, 0.16),
        (-0.12, 0.08, 0x0b2370, 0.22), (-0.36, 0.05, 0xc9e6ff, 0.18), (-0.58, 0.07, 0x08195a, 0.25),
    ]
    for (y, h, tint, alpha) in bands {
        ctx.drawLinearGradient(gradient([(tint, 0, 0), (tint, alpha, 0.5), (tint, 0, 1)]),
                               start: CGPoint(x: 0, y: (y - h) * r), end: CGPoint(x: 0, y: (y + h) * r), options: [])
    }
    // The Great Dark Spot and its bright companion cloud, low on the right.
    ctx.saveGState()
    ctx.translateBy(x: r * 0.5, y: -r * 0.47)
    ctx.scaleBy(x: 1, y: 0.42)
    ctx.drawRadialGradient(gradient([(0x061a55, 0.75, 0), (0x061a55, 0, 1)]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r * 0.2, options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: r * 0.62, y: -r * 0.58)
    ctx.scaleBy(x: 1, y: 0.18)
    ctx.drawRadialGradient(gradient([(0xffffff, 0.85, 0), (0xffffff, 0, 1)]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r * 0.16, options: [])
    ctx.restoreGState()
    ctx.restoreGState()
    // Limb darkening and a soft highlight.
    ctx.drawRadialGradient(gradient([(0x020a2e, 0, 0.62), (0x020a2e, 0.62, 1)]),
                           startCenter: CGPoint(x: p.x - r * 0.12, y: p.y + r * 0.12), startRadius: 0,
                           endCenter: p, endRadius: r, options: [])
    ctx.drawRadialGradient(gradient([(0xffffff, 0.3, 0), (0xffffff, 0, 1)]),
                           startCenter: lit, startRadius: 0, endCenter: lit, endRadius: r * 0.55, options: [])
    ctx.restoreGState()
}

func renderAppIcon() -> CGImage {
    let icon = bitmapContext()
    // macOS icon grid: an 824 pt squircle inside the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    icon.saveGState()
    icon.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.4))
    icon.addPath(squircle)
    icon.setFillColor(color(0x070d24))
    icon.fillPath()
    icon.restoreGState()

    icon.saveGState()
    icon.addPath(squircle)
    icon.clip()
    icon.drawLinearGradient(gradient([(0x16245a, 1, 0), (0x0a1236, 1, 0.55), (0x03061a, 1, 1)]),
                            start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (190, 820, 3, 0.8), (300, 860, 2, 0.5), (820, 800, 3, 0.7), (760, 880, 2, 0.5), (860, 610, 2, 0.6),
        (170, 560, 2, 0.5), (220, 230, 3, 0.6), (840, 250, 2, 0.6), (690, 170, 2, 0.4), (420, 880, 2, 0.4),
        (140, 380, 2, 0.4), (880, 420, 3, 0.5),
    ]
    for (x, y, size, alpha) in stars {
        icon.setFillColor(color(0xdfe9ff, alpha))
        icon.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
    }
    icon.restoreGState()

    drawNeptune(icon, center: CGPoint(x: 512, y: 512), radius: 318)

    // One transparency layer, so the trident casts a single shadow.
    let height: CGFloat = 330
    let centerY = 512 + (0.5 - tridentOpticalCenter()) * height
    icon.saveGState()
    icon.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: color(0x020a2e, 0.5))
    icon.beginTransparencyLayer(auxiliaryInfo: nil)
    fillTrident(icon, height: height, center: CGPoint(x: 512, y: centerY), fill: color(0xb4c8ee, 0.82))
    icon.endTransparencyLayer()
    icon.restoreGState()
    return icon.makeImage()!
}

// MARK: - Silhouette

/// A globe seen slightly from above and turned a little, so its latitude bands
/// curve the way they would on a real planet. Every pixel is mapped back onto
/// the sphere, which keeps the cut bands clean where they meet the limb.
enum Globe {
    static let tilt = 0.35
    static let spin = 0.2
    static let degree = Double.pi / 180
    /// Latitude, half width, and where (0 at the left limb, 1 at the right)
    /// the band starts tapering and where it ends, like the original ring tails.
    static let bands: [(phi: Double, half: Double, fade: Double, end: Double)] = [
        (40 * degree, 4 * degree, 0.35, 0.8),
        (10 * degree, 5.2 * degree, 0.55, 1.05),
        (-22 * degree, 3.8 * degree, 0.2, 0.62),
    ]
    /// The Great Dark Spot: latitude, longitude and its half extents.
    static let spot = (phi: -26 * degree, lambda: 42 * degree, width: 16 * degree, height: 7 * degree)

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Whether a point of the unit disc is solid planet.
    static func isSolid(_ screenX: Double, _ screenY: Double) -> Bool {
        let x = screenX * cos(-spin) - screenY * sin(-spin)
        let y = screenX * sin(-spin) + screenY * cos(-spin)
        let r2 = x * x + y * y
        guard r2 <= 1 else { return false }
        let z = (1 - r2).squareRoot()
        let sphereY = y * cos(tilt) + z * sin(tilt)
        let sphereZ = -y * sin(tilt) + z * cos(tilt)
        let phi = asin(max(-1, min(1, sphereY)))
        let lambda = atan2(x, sphereZ)
        let across = (lambda + Double.pi / 2) / Double.pi
        for band in bands where across <= band.end {
            let half = band.half * (1 - smoothstep(band.fade, band.end, across))
            if abs(phi - band.phi) < half { return false }
        }
        let dl = (lambda - spot.lambda) * cos(spot.phi) / spot.width
        let dp = (phi - spot.phi) / spot.height
        return dl * dl + dp * dp >= 1
    }
}

func renderSilhouette() -> CGImage {
    let radius = 450.0, samples = 4
    var pixels = [UInt8](repeating: 0, count: canvas * canvas * 4)
    let center = Double(canvas) / 2
    for py in 0..<canvas {
        for px in 0..<canvas {
            var hits = 0
            for sy in 0..<samples {
                for sx in 0..<samples {
                    let x = (Double(px) + (Double(sx) + 0.5) / Double(samples) - center) / radius
                    let y = (center - Double(py) - (Double(sy) + 0.5) / Double(samples)) / radius
                    if Globe.isSolid(x, y) { hits += 1 }
                }
            }
            // Black, premultiplied: only the alpha channel carries the shape.
            pixels[(py * canvas + px) * 4 + 3] = UInt8(255 * hits / (samples * samples))
        }
    }
    return CGImage(width: canvas, height: canvas, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: canvas * 4,
                   space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                   shouldInterpolate: true, intent: .defaultIntent)!
}

write(renderAppIcon(), to: "Resources/Brand/AppIcon-Default.png")
write(renderSilhouette(), to: "Resources/Brand/logo.png")
