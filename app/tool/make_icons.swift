// Draws the IQ2020 Spa icon (a steaming hot tub in the app's night-spa palette) with
// CoreGraphics and writes every size the apps need. No dependencies beyond macOS.
//
//   swift app/tool/make_icons.swift        (run from the repo root)
//
// Outputs: iOS AppIcon set, watchOS AppIcon, Android phone + Wear launcher icons (legacy, round
// and adaptive foreground), and a 512 px Play Store icon in app/tool/icon/.
import AppKit
import CoreGraphics
import Foundation

enum Style {
  case square // full-bleed background (iOS / watchOS: the OS applies the mask)
  case round // background clipped to a circle (Android legacy round, Wear)
  case legacy // rounded square with margin (pre-adaptive Android launchers)
  case foreground // transparent, art inside the adaptive-icon safe zone (Android 8+)
}

let deepTeal = CGColor(srgbRed: 0x0E / 255, green: 0x3A / 255, blue: 0x45 / 255, alpha: 1)
let ink = CGColor(srgbRed: 0x06 / 255, green: 0x14 / 255, blue: 0x19 / 255, alpha: 1)
let aqua = CGColor(srgbRed: 0x4F / 255, green: 0xE3 / 255, blue: 0xEA / 255, alpha: 1)
let aquaDeep = CGColor(srgbRed: 0x16 / 255, green: 0x8E / 255, blue: 0xA0 / 255, alpha: 1)
let steam = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)

func draw(_ ctx: CGContext, size s: CGFloat, style: Style) {
  // Work in a 0..1 square with y pointing down, like the design notes.
  ctx.translateBy(x: 0, y: s)
  ctx.scaleBy(x: s, y: -s)
  let space = CGColorSpace(name: CGColorSpace.sRGB)!

  func background(_ clip: CGPath?) {
    ctx.saveGState()
    if let clip { ctx.addPath(clip); ctx.clip() }
    let g = CGGradient(colorsSpace: space, colors: [deepTeal, ink] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1), options: [])
    // Soft aqua glow behind the water.
    let glow = CGGradient(colorsSpace: space, colors: [aqua.copy(alpha: 0.28)!, aqua.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 0.5, y: 0.66), startRadius: 0,
                           endCenter: CGPoint(x: 0.5, y: 0.66), endRadius: 0.45, options: [])
    ctx.restoreGState()
  }

  switch style {
  case .square: background(nil)
  case .round: background(CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1), transform: nil))
  case .legacy:
    background(CGPath(roundedRect: CGRect(x: 0.06, y: 0.06, width: 0.88, height: 0.88), cornerWidth: 0.2, cornerHeight: 0.2, transform: nil))
  case .foreground: break
  }

  // Art is laid out for the full square; shrink it into the adaptive safe zone (66 of 108 dp)
  // or a little for the circular/legacy shapes.
  let scale: CGFloat = switch style {
  case .square: 1
  case .round, .legacy: 0.86
  case .foreground: 0.62
  }
  ctx.translateBy(x: 0.5, y: 0.5)
  ctx.scaleBy(x: scale, y: scale)
  ctx.translateBy(x: -0.5, y: -0.47)

  // Tub: a square-sided shell with rounded corners and a wide lip, filled with water.
  let left: CGFloat = 0.17, right: CGFloat = 0.83, rim: CGFloat = 0.53, bottom: CGFloat = 0.83
  let bowl = CGMutablePath()
  let r: CGFloat = 0.1
  bowl.move(to: CGPoint(x: left, y: rim))
  bowl.addLine(to: CGPoint(x: right, y: rim))
  bowl.addLine(to: CGPoint(x: right, y: bottom - r))
  bowl.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
  bowl.addLine(to: CGPoint(x: left + r, y: bottom))
  bowl.addQuadCurve(to: CGPoint(x: left, y: bottom - r), control: CGPoint(x: left, y: bottom))
  bowl.closeSubpath()

  // Water below a wavy surface.
  let water = CGMutablePath()
  let surface: CGFloat = 0.585
  water.move(to: CGPoint(x: left, y: surface))
  let waves = 3
  let w = (right - left) / CGFloat(waves)
  for i in 0..<waves {
    let x0 = left + CGFloat(i) * w
    water.addCurve(to: CGPoint(x: x0 + w, y: surface),
                   control1: CGPoint(x: x0 + w * 0.3, y: surface - 0.035),
                   control2: CGPoint(x: x0 + w * 0.7, y: surface + 0.035))
  }
  water.addLine(to: CGPoint(x: right, y: 1))
  water.addLine(to: CGPoint(x: left, y: 1))
  water.closeSubpath()

  ctx.saveGState()
  ctx.addPath(bowl)
  ctx.clip()
  ctx.addPath(water)
  ctx.clip()
  let wg = CGGradient(colorsSpace: space, colors: [aqua, aquaDeep] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(wg, start: CGPoint(x: 0.5, y: surface - 0.04), end: CGPoint(x: 0.5, y: bottom), options: [])
  ctx.restoreGState()

  // Bubbles rising in the water.
  ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
  for (x, y, rad) in [(0.32, 0.72, 0.028), (0.42, 0.67, 0.018), (0.6, 0.74, 0.024), (0.7, 0.66, 0.016), (0.5, 0.77, 0.014)] {
    ctx.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2))
  }

  // Tub outline and lip.
  ctx.setLineJoin(.round)
  ctx.setLineCap(.round)
  ctx.setStrokeColor(aqua)
  ctx.setLineWidth(0.035)
  ctx.addPath(bowl)
  ctx.strokePath()
  ctx.setLineWidth(0.05)
  ctx.move(to: CGPoint(x: left - 0.04, y: rim))
  ctx.addLine(to: CGPoint(x: right + 0.04, y: rim))
  ctx.strokePath()

  // Three steam wisps.
  ctx.setStrokeColor(steam)
  ctx.setLineWidth(0.036)
  for (i, x) in [0.34, 0.5, 0.66].enumerated() {
    let top: CGFloat = i == 1 ? 0.2 : 0.26
    let base: CGFloat = 0.45
    let x = CGFloat(x)
    ctx.move(to: CGPoint(x: x, y: base))
    ctx.addCurve(to: CGPoint(x: x, y: (base + top) / 2), control1: CGPoint(x: x - 0.045, y: base - 0.04), control2: CGPoint(x: x + 0.045, y: (base + top) / 2 + 0.04))
    ctx.addCurve(to: CGPoint(x: x, y: top), control1: CGPoint(x: x - 0.045, y: (base + top) / 2 - 0.04), control2: CGPoint(x: x + 0.04, y: top + 0.03))
    ctx.strokePath()
  }
}

func png(_ px: Int, _ style: Style, opaque: Bool) -> Data {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
  let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
  ctx.setShouldAntialias(true)
  ctx.interpolationQuality = .high
  draw(ctx, size: CGFloat(px), style: style)
  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  return rep.representation(using: .png, properties: [:])!
}

func write(_ path: String, _ px: Int, _ style: Style, opaque: Bool = false) {
  let url = URL(fileURLWithPath: path)
  try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try! png(px, style, opaque: opaque).write(to: url)
}

let root = FileManager.default.currentDirectoryPath

// iOS (App Store rejects alpha in the 1024 icon, so all are opaque).
let ios = "\(root)/app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
for (pt, scales) in [(20.0, [1, 2, 3]), (29.0, [1, 2, 3]), (40.0, [1, 2, 3]), (60.0, [2, 3]), (76.0, [1, 2]), (83.5, [2]), (1024.0, [1])] {
  for sc in scales {
    let name = pt == 83.5 ? "83.5x83.5" : "\(Int(pt))x\(Int(pt))"
    write("\(ios)/Icon-App-\(name)@\(sc)x.png", Int((pt * Double(sc)).rounded()), .square, opaque: true)
  }
}
// watchOS: one 1024 icon, the system makes it round.
write("\(root)/app/ios/IQ2020Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png", 1024, .square, opaque: true)

// Android phone + Wear: legacy (48 dp), round (48 dp) and adaptive foreground (108 dp).
let densities: [(String, Double)] = [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]
for project in ["app", "wear"] {
  let res = "\(root)/\(project)/android/app/src/main/res"
  for (d, f) in densities {
    write("\(res)/mipmap-\(d)/ic_launcher.png", Int(48 * f), project == "wear" ? .round : .legacy)
    write("\(res)/mipmap-\(d)/ic_launcher_round.png", Int(48 * f), .round)
    // Adaptive foreground for the phone (mipmap-anydpi-v26); Wear uses the round icon.
    if project == "app" { write("\(res)/mipmap-\(d)/ic_launcher_foreground.png", Int(108 * f), .foreground) }
  }
}
// Play Store listing icon.
write("\(root)/app/tool/icon/play-store-512.png", 512, .square, opaque: true)
write("\(root)/app/tool/icon/preview-1024.png", 1024, .square, opaque: true)
print("icons written")
