import AppKit
import SwiftUI

/// The one place colour is defined.
///
/// Every dial, legend dot and percentage reads from here, so a re-skin is an edit to
/// this file rather than a hunt through the views (std-27 cl-4). Each entry carries a
/// light and a dark value: on a dark ground the hues stay luminous, and on a light
/// ground the same hues sit a step or two deeper so they hold their contrast
/// (std-29 cl-2).
enum Palette {

    // MARK: - Progress bands

    /// Under 60% of target.
    static let low = theme(light: (0.10, 0.62, 0.45), dark: (0.25, 0.80, 0.62))
    static let lowTrailing = theme(light: (0.13, 0.63, 0.63), dark: (0.36, 0.86, 0.85))

    /// From 60%.
    static let medium = theme(light: (0.80, 0.55, 0.05), dark: (0.98, 0.75, 0.29))
    static let mediumTrailing = theme(light: (0.85, 0.45, 0.06), dark: (0.99, 0.62, 0.30))

    /// From 85%.
    static let high = theme(light: (0.85, 0.38, 0.05), dark: (0.99, 0.55, 0.24))
    static let highTrailing = theme(light: (0.82, 0.22, 0.18), dark: (0.98, 0.40, 0.35))

    /// Past the target. This is the reserved failure hue and is never used
    /// decoratively (std-29 cl-8).
    static let over = theme(light: (0.80, 0.15, 0.20), dark: (0.96, 0.35, 0.38))
    static let overTrailing = theme(light: (0.68, 0.10, 0.38), dark: (0.85, 0.25, 0.55))

    // MARK: - Provider hues

    /// Reserved per provider, so the hover split and the legend teach one vocabulary
    /// (std-29 cl-8). Deliberately clear of the red reserved for over-target.
    static let claude  = theme(light: (0.76, 0.38, 0.06), dark: (0.93, 0.55, 0.24))
    static let codex   = theme(light: (0.10, 0.58, 0.44), dark: (0.30, 0.78, 0.62))
    static let cursor  = theme(light: (0.24, 0.38, 0.80), dark: (0.45, 0.60, 0.95))
    static let gemini  = theme(light: (0.47, 0.27, 0.75), dark: (0.68, 0.48, 0.92))
    static let copilot = theme(light: (0.40, 0.43, 0.50), dark: (0.55, 0.58, 0.64))

    // MARK: - Resolution

    /// Builds a colour that resolves itself against whichever appearance it is drawn
    /// in. Doing it through NSColor rather than the SwiftUI environment means a colour
    /// is correct wherever it is used, including inside an ImageRenderer snapshot,
    /// with no environment to plumb through.
    private static func theme(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }
}
