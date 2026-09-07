import AppKit

// Top-level code is not main-actor isolated, but it does run on the main thread.
// `app.run()` blocks here for the process lifetime, so the local reference keeps
// the delegate alive (NSApplication holds its delegate weakly).
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
    app.run()
}
