import AppKit
import SwiftUI

// Renders the Token Counter app icon: a flat yellow squircle carrying a two-tone
// progress ring. Same language as the Medstock icon, one bold glyph on a solid
// saturated ground, no gradients and no text.

let canvas: CGFloat = 1024
let plateInset: CGFloat = 100          // macOS Big Sur icon grid
let plateCorner: CGFloat = 185
let ringDiameter: CGFloat = 470
let ringStroke: CGFloat = 92
let filled: CGFloat = 0.72             // how much of the ring reads as used

let yellow = Color(red: 0.961, green: 0.702, blue: 0.004)   // #F5B301

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                .fill(yellow)
                .frame(width: canvas - plateInset * 2, height: canvas - plateInset * 2)

            Circle()
                .stroke(Color.white.opacity(0.30), lineWidth: ringStroke)
                .frame(width: ringDiameter, height: ringDiameter)

            Circle()
                .trim(from: 0, to: filled)
                .stroke(Color.white, style: StrokeStyle(lineWidth: ringStroke, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .frame(width: ringDiameter, height: ringDiameter)
        }
        .frame(width: canvas, height: canvas)
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("icon render failed\n".utf8))
        exit(1)
    }
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    do {
        try png.write(to: out)
        print("rendered \(out.lastPathComponent) at \(Int(canvas))px")
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
}
