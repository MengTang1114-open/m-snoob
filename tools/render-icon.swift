import AppKit
import ImageIO

/// Renders the snow ghost into macOS icon backgrounds.
///
///   swiftc -parse-as-library -O -framework Metal -framework MetalKit -framework AppKit -framework ImageIO \
///     Sources/Snowhush/GhostPortrait.swift tools/render-icon.swift -o /tmp/render-icon
///   /tmp/render-icon
///
/// Writes docs/icon/*.png and replaces Resources/AppIcon.icns. The ghost is GhostPortrait,
/// the same shader the floater uses.

@main
enum RenderIcon {
    static func main() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconDir = root.appendingPathComponent("docs/icon")
        try? FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
        guard let portrait = GhostPortraitRenderer() else {
            fputs("portrait renderer failed\n", stderr)
            exit(1)
        }
        guard let ghost = portrait.renderImage(pixels: 1024, mood: .timing, time: 0.4, bold: false, nudge: 0.30),
              let ghostSmall = portrait.renderImage(pixels: 128, mood: .timing, time: 0.4, bold: true, nudge: 0.30) else {
            fputs("ghost render failed\n", stderr)
            exit(1)
        }

        let variants: [(String, Sky)] = [
            ("01-night", .night),
            ("02-dusk", .dusk),
            ("03-blizzard", .blizzard),
        ]
        var night: CGImage?
        for (name, sky) in variants {
            guard let image = compose(ghost: ghost, sky: sky, pixels: 1024) else { exit(1) }
            write(image, to: iconDir.appendingPathComponent("\(name).png"))
            if sky == .night { night = image }
        }
        if let small = compose(ghost: ghostSmall, sky: .night, pixels: 128) {
            write(small, to: iconDir.appendingPathComponent("night-16.png"))
        }
        guard let night else { exit(1) }
        writeIconSet(master: night, small: compose(ghost: ghostSmall, sky: .night, pixels: 64), root: root)
        print(iconDir.path)
    }

    private struct Sky: Equatable {
        var top: NSColor
        var bottom: NSColor
        var flakes: Int
        var drift: CGFloat
        static let night = Sky(
            top: NSColor(srgbRed: 0.05, green: 0.09, blue: 0.18, alpha: 1),
            bottom: NSColor(srgbRed: 0.16, green: 0.34, blue: 0.58, alpha: 1),
            flakes: 18, drift: 0.16
        )
        static let dusk = Sky(
            top: NSColor(srgbRed: 0.16, green: 0.08, blue: 0.22, alpha: 1),
            bottom: NSColor(srgbRed: 0.32, green: 0.24, blue: 0.48, alpha: 1),
            flakes: 12, drift: 0.13
        )
        static let blizzard = Sky(
            top: NSColor(srgbRed: 0.22, green: 0.38, blue: 0.56, alpha: 1),
            bottom: NSColor(srgbRed: 0.62, green: 0.78, blue: 0.90, alpha: 1),
            flakes: 36, drift: 0.24
        )
    }

    private static func compose(ghost: CGImage, sky: Sky, pixels: Int) -> CGImage? {
        let size = CGSize(width: pixels, height: pixels)
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        context.addPath(squircle(in: rect))
        context.clip()
        let colors = [sky.bottom.cgColor, sky.top.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
        var random = Seed(sky.flakes &* 17 &+ pixels)
        for _ in 0..<sky.flakes {
            let x = random.next() * size.width
            let y = random.next() * size.height * 0.86 + size.height * 0.08
            let r = (0.004 + random.next() * 0.012) * size.width
            context.setFillColor(NSColor.white.withAlphaComponent(0.35 + random.next() * 0.5).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
        let ghostSide = size.width * 0.92
        let ghostRect = CGRect(
            x: (size.width - ghostSide) / 2,
            y: -size.height * 0.08,
            width: ghostSide, height: ghostSide
        )
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -size.height * 0.012), blur: size.width * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.draw(ghost, in: ghostRect)
        context.restoreGState()
        return context.makeImage()
    }

    private static func squircle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let n = 5.0
        let a = rect.width / 2
        let b = rect.height / 2
        let steps = 96
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * Double.pi
            let ct = cos(t), st = sin(t)
            let x = rect.midX + a * CGFloat(pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1))
            let y = rect.midY + b * CGFloat(pow(abs(st), 2 / n) * (st < 0 ? -1 : 1))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func writeIconSet(master: CGImage, small: CGImage?, root: URL) {
        let set = root.appendingPathComponent("build/AppIcon.iconset")
        try? FileManager.default.removeItem(at: set)
        try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        let slots: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]
        for (name, pixels) in slots {
            let image: CGImage?
            if pixels <= 64, let small {
                image = scale(small, to: pixels)
            } else {
                image = scale(master, to: pixels)
            }
            if let image { write(image, to: set.appendingPathComponent(name)) }
        }
        let icns = root.appendingPathComponent("Resources/AppIcon.icns")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        task.arguments = ["-c", "icns", set.path, "-o", icns.path]
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            fputs("iconutil failed\n", stderr)
            exit(1)
        }
    }

    private static func scale(_ image: CGImage, to pixels: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    private struct Seed {
        var state: UInt64
        init(_ seed: Int) { state = UInt64(seed) &* 0x9E3779B97F4A7C15 }
        mutating func next() -> CGFloat {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            return CGFloat(z % 10_000) / 10_000
        }
    }
}
