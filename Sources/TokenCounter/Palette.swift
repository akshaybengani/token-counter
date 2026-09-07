import AppKit
import SwiftUI

/// The one place colour is defined.
///
/// Every dial, legend dot and percentage reads from here, so a re-skin is an edit to
/// this file rather than a hunt through the views (std-27 cl-4). Each entry carries a
/// light and a dark value: on a dark ground the hues stay luminous, and on a light
/// ground the same hues sit a step or two deeper so they hold their contrast
/// (std-29 cl-2). Every band measures at least 3:1 against its own surface.
///
/// The progress bands are a status ramp (good, warning, serious, critical), not a
/// categorical one, so the adjacent-hue separation test for categorical series does
/// not apply to them: a correct green-to-red ramp fails it by design. Monotonic
/// lightness was tried as the colourblind-safe ordering and rejected, because forcing
/// red to the lightness that ordering needs turns it pink and loses the alarm reading.
/// The ordering is carried by position against the target line and by labels instead,
/// which is what a status colour requires anyway: it never travels alone.
enum Palette {

    // MARK: - Progress bands

    /// Under 60% of target.
    static let low = theme(light: (0.10, 0.62, 0.45), dark: (0.25, 0.80, 0.62))
    static let lowTrailing = theme(light: (0.13, 0.63, 0.63), dark: (0.36, 0.86, 0.85))

    /// From 60%. Both steps are set by measured contrast against their surface, not
    /// by eye: the previous light value came in at 2.79:1, below the 3:1 floor for a
    /// graphical object. These measure 3.34:1 on light and 9.08:1 on dark.
    static let medium = theme(light: (0.722, 0.502, 0.039), dark: (0.910, 0.702, 0.247))
    static let mediumTrailing = theme(light: (0.85, 0.45, 0.06), dark: (0.99, 0.62, 0.30))

    /// From 85%.
    static let high = theme(light: (0.85, 0.38, 0.05), dark: (0.99, 0.55, 0.24))
    static let highTrailing = theme(light: (0.82, 0.22, 0.18), dark: (0.98, 0.40, 0.35))

    /// Past the target. This is the reserved failure hue and is never used
    /// decoratively (std-29 cl-8).
    static let over = theme(light: (0.80, 0.15, 0.20), dark: (0.96, 0.35, 0.38))
    static let overTrailing = theme(light: (0.68, 0.10, 0.38), dark: (0.85, 0.25, 0.55))

    // MARK: - Provider hues

    /// A categorical set, so unlike the progress bands it is held to the adjacent-hue
    /// separation checks. Every step below was chosen by running the palette
    /// validator in the `dataviz` skill rather than by eye, and the four that draw an
    /// arc pass all of its checks in both modes:
    ///
    ///   light  worst pair ΔE 8.9 under deuteranopia, 16.0 in normal vision
    ///   dark   worst pair ΔE 10.4 under deuteranopia, 18.7 in normal vision
    ///
    /// The earlier set failed badly: Cursor's blue and Gemini's violet were ΔE 2.1
    /// apart under deuteranopia, which made them the same colour to a deuteranope
    /// while sitting next to each other in the legend. Blue and violet cannot be
    /// separated by hue alone, so Gemini moved to a plum with a real lightness gap
    /// from both the blue and the green. The hues follow Okabe-Ito, which was designed
    /// for exactly this.
    ///
    /// Reserved per provider, so the hover split and the legend teach one vocabulary
    /// (std-29 cl-8), and clear of the red that means over-target.
    static let claude  = theme(light: (0.659, 0.373, 0.000), dark: (0.769, 0.439, 0.122))
    static let codex   = theme(light: (0.059, 0.561, 0.388), dark: (0.184, 0.678, 0.510))
    static let cursor  = theme(light: (0.000, 0.447, 0.698), dark: (0.165, 0.498, 0.753))
    static let gemini  = theme(light: (0.561, 0.271, 0.439), dark: (0.561, 0.294, 0.475))

    /// Grey on purpose: Copilot reports no token counts, so it never draws an arc and
    /// only ever appears as a legend dot beside the words "No token data". Being the
    /// one low-chroma entry also separates it from the four by saturation alone. It is
    /// excluded from the categorical checks, which require chroma the grey does not
    /// have and should not have.
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
