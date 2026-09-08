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

/// The dial's orange, sampled from the panel screenshot in the README: it is the
/// `high` progress band. White on that measures 2.34:1, and at 32px the ring blurs
/// into the plate, so the plate takes the same hue two steps deeper at 4.51:1 and the
/// sampled orange stays in the icon as the remainder arc. Both were rendered and
/// compared at 32px before choosing. This mirrors Medstock, which puts a white glyph
/// and a light cyan fill on a deep teal plate at 6.16:1.
let dialOrange = Color(red: 0.988, green: 0.549, blue: 0.239)   // #FC8C3D
let plateOrange = Color(red: 0.761, green: 0.341, blue: 0.031)  // #C25708

let plate = plateOrange
let remainder = dialOrange

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                .fill(plate)
                .frame(width: canvas - plateInset * 2, height: canvas - plateInset * 2)

            Circle()
                .stroke(remainder, lineWidth: ringStroke)
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
