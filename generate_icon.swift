import AppKit
import CoreGraphics

let iconsetPath = "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(size: Int) -> NSImage {
    let cgSize = CGSize(width: size, height: size)
    let image = NSImage(size: cgSize)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let s = CGFloat(size)
    let padding = s * 0.08
    let rect = CGRect(x: padding, y: padding, width: s - padding * 2, height: s - padding * 2)
    let cornerRadius = rect.width * 0.225
    
    // Outer shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.22, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Clip to squircle
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    
    // Rich gradient background (Deep Indigo -> Electric Blue -> Cyan)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.22, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.08, green: 0.28, blue: 0.68, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.0, green: 0.72, blue: 0.95, alpha: 1.0).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
    }
    
    // Subtle radar / pulse rings in the center
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    for (idx, mult) in [0.24, 0.33, 0.41].enumerated() {
        let r = s * CGFloat(mult)
        let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.strokeEllipse(in: ringRect)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18 - CGFloat(idx) * 0.05).cgColor)
        ctx.setLineWidth(max(1.5, s * 0.012))
        ctx.strokeEllipse(in: ringRect)
    }
    
    // Inner glass border highlight
    ctx.addPath(bgPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    ctx.setLineWidth(max(1.5, s * 0.018))
    ctx.strokePath()
    
    // Draw sleek wireless mouse body in the center (tilted slightly at -20 degrees like the classic Mac utility icon)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: -0.32)
    
    let mouseW = s * 0.30
    let mouseH = s * 0.44
    let mouseRect = CGRect(x: -mouseW / 2, y: -mouseH / 2, width: mouseW, height: mouseH)
    let mousePath = CGPath(roundedRect: mouseRect, cornerWidth: mouseW * 0.48, cornerHeight: mouseW * 0.48, transform: nil)
    
    // Drop shadow for mouse
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.04, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.addPath(mousePath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    
    // Reset shadow for mouse details
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    
    // Scroll wheel / division line in deep blue
    let wheelW = mouseW * 0.14
    let wheelH = mouseH * 0.20
    let wheelRect = CGRect(x: -wheelW / 2, y: mouseH * 0.10, width: wheelW, height: wheelH)
    let wheelPath = CGPath(roundedRect: wheelRect, cornerWidth: wheelW / 2, cornerHeight: wheelW / 2, transform: nil)
    ctx.addPath(wheelPath)
    ctx.setFillColor(NSColor(calibratedRed: 0.06, green: 0.22, blue: 0.55, alpha: 1.0).cgColor)
    ctx.fillPath()
    
    // Subtle glowing green "Active" LED dot at the bottom of the mouse
    let ledSize = mouseW * 0.14
    let ledRect = CGRect(x: -ledSize / 2, y: -mouseH * 0.30, width: ledSize, height: ledSize)
    ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.88, blue: 0.45, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: ledRect)
    
    // Motion waves on the left and right of the mouse
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(max(2.0, s * 0.022))
    
    for side in [-1.0, 1.0] {
        let xOffset = CGFloat(side) * (mouseW * 0.68)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: xOffset, y: -mouseH * 0.14))
        ctx.addQuadCurve(to: CGPoint(x: xOffset, y: mouseH * 0.14), control: CGPoint(x: xOffset + CGFloat(side) * s * 0.045, y: 0))
        ctx.strokePath()
    }
    
    ctx.restoreGState()
    ctx.restoreGState()
    
    image.unlockFocus()
    return image
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let img = renderIcon(size: px)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try! png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
    }
}
print("Generated iconset successfully.")
