import AppKit
import SwiftUI

// Captures the real settings window by asking its view hierarchy to draw itself.
//
// ImageRenderer cannot draw a Form or a segmented Picker: both are backed by AppKit
// and come out as a placeholder. cacheDisplay(in:to:) renders the actual hierarchy
// instead, so the tab strip, the form rows and the segmented controls all appear, and
// it needs no Screen Recording permission. The controls are then driven through the
// AppKit objects behind them rather than by injecting SwiftUI state, so what is
// captured is what a click would produce.

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

/// Depth-first search for the first view of a given kind.
func firstView<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for subview in view.subviews {
        if let match = firstView(type, in: subview) { return match }
    }
    return nil
}

func allViews<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
    var found: [T] = []
    if let match = view as? T { found.append(match) }
    for subview in view.subviews { found += allViews(type, in: subview) }
    return found
}

/// Lets SwiftUI lay out and AppKit draw before anything is measured or captured.
func settle(_ seconds: TimeInterval = 0.6) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

@MainActor
func capture(_ window: NSWindow, _ name: String) {
    guard let view = window.contentView else { print("no content view"); return }
    window.displayIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        print("cannot make a bitmap for \(name)"); return
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("cannot encode \(name)"); return
    }
    try? png.write(to: outputDirectory.appendingPathComponent(name))
    print("wrote \(name)  \(Int(rep.size.width))x\(Int(rep.size.height))")
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let store = UsageStore.shared
    store.start()
    let deadline = Date().addingTimeInterval(90)
    while store.lastUpdated == nil && Date() < deadline { settle(0.1) }

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "Token Counter"
    window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(store))
    window.orderFrontRegardless()
    settle(1.2)

    guard let content = window.contentView else { exit(1) }

    // What is actually in the hierarchy, which is the part ImageRenderer hid.
    let tabViews = allViews(NSTabView.self, in: content)
    let segmented = allViews(NSSegmentedControl.self, in: content)
    print("NSTabView: \(tabViews.count)   NSSegmentedControl: \(segmented.count)")
    if let tabs = tabViews.first {
        print("tabs: \(tabs.tabViewItems.map { $0.label })")
        print("tab strip height: \(tabs.frame.height) in a \(Int(content.bounds.height))pt window")
    }
    for (index, control) in segmented.enumerated() {
        let labels = (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "?" }
        print("segmented[\(index)]: \(labels) selected=\(control.selectedSegment) width=\(Int(control.frame.width))")
    }

    // Dump the hierarchy: the tab strip is either here under another class or absent.
    func dump(_ view: NSView, _ depth: Int = 0) {
        let name = String(describing: type(of: view))
        let f = view.frame
        let interesting = name.contains("Tab") || name.contains("Segment") || name.contains("Scroll")
            || name.contains("Split") || depth < 4
        if interesting {
            let pad = String(repeating: "  ", count: depth)
            print("\(pad)\(name)  \(Int(f.width))x\(Int(f.height)) at \(Int(f.minX)),\(Int(f.minY))")
        }
        for sub in view.subviews { dump(sub, depth + 1) }
    }
    print("--- hierarchy ---")
    dump(content)
    print("--- end ---")

    // Known capture artifact: every NSSwitch draws in its off appearance under
    // cacheDisplay, because the on-state fill comes from a layer this does not
    // composite. Read the state rather than the pixels. If these match
    // store.enabled, the bindings are fine however the capture looks.
    let switches = allViews(NSSwitch.self, in: content)
    print("NSSwitch: \(switches.count)  states: \(switches.map { $0.state == .on ? "on" : "off" })")
    print("store.enabled: \(store.orderedProviders.filter { store.enabled.contains($0) }.map(\.rawValue))")

    capture(window, "settings-general.png")

    // Drive the pane switcher, then confirm the pane actually changed by looking for
    // a control that only exists in the Analytics pane. Trusting the call would prove
    // nothing; the observable consequence is the check.
    guard let switcher = segmented.first(where: { control in
        (0..<control.segmentCount).contains { control.label(forSegment: $0) == "Analytics" }
    }) else {
        print("FAIL: no pane switcher offering Analytics")
        exit(1)
    }

    func rangePicker() -> NSSegmentedControl? {
        allViews(NSSegmentedControl.self, in: content).first { control in
            (0..<control.segmentCount).allSatisfy { (control.label(forSegment: $0) ?? "").hasSuffix("d") }
        }
    }

    precondition(rangePicker() == nil, "the range picker is visible before switching panes")

    switcher.selectedSegment = 1
    switcher.performClick(nil)
    settle(1.2)

    guard let picker = rangePicker() else {
        print("FAIL: switching to Analytics did not reveal the range picker, so the pane did not change")
        capture(window, "settings-analytics-FAILED.png")
        exit(1)
    }
    let ranges = (0..<picker.segmentCount).map { picker.label(forSegment: $0) ?? "?" }
    print("Analytics pane reached. range picker: \(ranges) selected=\(picker.selectedSegment)")
    capture(window, "settings-analytics.png")

    // Drive the range picker to its widest span.
    picker.selectedSegment = picker.segmentCount - 1
    picker.performClick(nil)
    settle(1.0)
    print("after driving the range picker: selected=\(picker.selectedSegment)")
    capture(window, "settings-analytics-90d.png")

    // And back to General, to prove the switch works both ways.
    switcher.selectedSegment = 0
    switcher.performClick(nil)
    settle(1.0)
    print("back to General: range picker gone = \(rangePicker() == nil)")
}
