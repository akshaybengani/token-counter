import AppKit
import SwiftUI
import XCTest
@testable import TokenCounter

/// The palette's real checks are colorimetric and live in the `dataviz` validator,
/// which is run by hand when a value changes. What is guarded here is the property
/// that validator exists to protect: two providers must never resolve to the same
/// colour, in either appearance. Cursor and Gemini were once ΔE 2.1 apart under
/// deuteranopia, and nothing in the build would have noticed.
@MainActor
final class PaletteTests: XCTestCase {

    /// Resolves a SwiftUI colour the way it will actually be drawn in one appearance.
    private func rgb(_ color: Color, dark: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var out: (CGFloat, CGFloat, CGFloat)?
        appearance.performAsCurrentDrawingAppearance {
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            out = (c.redComponent, c.greenComponent, c.blueComponent)
        }
        return out
    }

    private func distance(_ a: (r: CGFloat, g: CGFloat, b: CGFloat),
                          _ b: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return sqrt(dr * dr + dg * dg + db * db)
    }

    func testEveryProviderIsADistinctColourInBothAppearances() throws {
        tagAc("akshay/personal/specs/spec-26/acs/ac-25")

        for dark in [false, true] {
            var seen: [(ProviderID, (r: CGFloat, g: CGFloat, b: CGFloat))] = []
            for id in ProviderID.allCases {
                let value = try XCTUnwrap(rgb(id.tint, dark: dark), "\(id.rawValue) did not resolve")
                for (other, otherValue) in seen {
                    let d = distance(value, otherValue)
                    XCTAssertGreaterThan(
                        d, 0.15,
                        "\(id.rawValue) and \(other.rawValue) are too close in \(dark ? "dark" : "light") mode (rgb distance \(d))"
                    )
                }
                seen.append((id, value))
            }
        }
    }

    /// A colour that resolves the same in both appearances is not theme-aware, which
    /// was the drift that started this.
    func testEveryColourResolvesDifferentlyPerAppearance() throws {
        tagAc("akshay/personal/specs/spec-26/acs/ac-25")

        var checked = 0
        for id in ProviderID.allCases {
            let light = try XCTUnwrap(rgb(id.tint, dark: false))
            let dark = try XCTUnwrap(rgb(id.tint, dark: true))
            XCTAssertGreaterThan(distance(light, dark), 0.02, "\(id.rawValue) is the same in both themes")
            checked += 1
        }
        for level in [UsageLevel.low, .medium, .high, .over] {
            let light = try XCTUnwrap(rgb(level.color, dark: false))
            let dark = try XCTUnwrap(rgb(level.color, dark: true))
            XCTAssertGreaterThan(distance(light, dark), 0.02, "a progress band is the same in both themes")
            checked += 1
        }
        XCTAssertEqual(checked, 9, "every provider and every band was checked")
    }

    /// Red is the failure hue. A provider must not wear it, or a legend dot would
    /// read as an alarm.
    func testNoProviderWearsTheFailureHue() throws {
        tagAc("akshay/personal/specs/spec-26/acs/ac-25")

        let over = try XCTUnwrap(rgb(UsageLevel.over.color, dark: true))
        for id in ProviderID.allCases {
            let tint = try XCTUnwrap(rgb(id.tint, dark: true))
            XCTAssertGreaterThan(distance(tint, over), 0.25,
                                 "\(id.rawValue) is too close to the over-target red")
        }
    }
}
