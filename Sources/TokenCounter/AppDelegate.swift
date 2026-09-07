import AppKit
import SwiftUI
import Combine

/// Borderless, draggable panel that behaves like a desktop widget.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private let store = UsageStore.shared
    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        buildStatusItem()
        buildPanel()

        // Redraw the menu bar readout whenever the tally or settings change.
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.refitPanel()
            }
            .store(in: &cancellables)

        // A sleeping Mac misses timer fires; catch up on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        store.start()
        updateStatusItem()

        if !Prefs.shared.panelVisible { panel?.orderOut(nil) }
    }

    @objc private func handleWake() {
        store.refresh()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "circle.lefthalf.filled",
            accessibilityDescription: "Token usage"
        )
        item.button?.imagePosition = .imageLeading
        item.menu = buildMenu()
        statusItem = item
    }

    /// Internal rather than private so the test target can assert its structure.
    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.tag = 100
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self

        let toggle = NSMenuItem(
            title: "Show Panel",
            action: #selector(togglePanel),
            keyEquivalent: "p"
        )
        toggle.target = self
        toggle.tag = 101
        menu.addItem(toggle)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Display"))

        // Title case here matches the rest of this menu and the platform's own menus.
        // std-24 cl-16 allows it for navigation labels, which is what a menu is.
        let combined = NSMenuItem(title: "Combined", action: #selector(showCombined), keyEquivalent: "")
        combined.target = self
        combined.tag = 110
        menu.addItem(combined)

        let separate = NSMenuItem(title: "Per Provider", action: #selector(showPerProvider), keyEquivalent: "")
        separate.target = self
        separate.tag = 111
        menu.addItem(separate)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
            .target = self

        return menu
    }

    private func updateStatusItem() {
        let color = NSColor(store.level.color)
        statusItem?.button?.attributedTitle = NSAttributedString(
            string: " " + store.percentText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: color,
            ]
        )

        if let header = statusItem?.menu?.item(withTag: 100) {
            header.title = "\(Fmt.compact(store.combinedUsed)) of \(Fmt.compactTight(store.combinedTarget)) today · \(store.percentText)"
        }
        if let toggle = statusItem?.menu?.item(withTag: 101) {
            toggle.state = (panel?.isVisible ?? false) ? .on : .off
        }
        if let item = statusItem?.menu?.item(withTag: 110) {
            item.state = store.mode == .combined ? .on : .off
        }
        if let item = statusItem?.menu?.item(withTag: 111) {
            item.state = store.mode == .separate ? .on : .off
        }
    }

    @objc private func showCombined() { store.mode = .combined }

    @objc private func showPerProvider() { store.mode = .separate }

    /// Re-fits the panel to its content, anchoring the top edge.
    ///
    /// The two modes are different heights, and a window whose content view controller
    /// changes intrinsic size does not always shrink on its own, which would leave the
    /// shorter mode clipped inside the taller frame.
    private func refitPanel() {
        guard let panel, let controller = panel.contentViewController else { return }
        let size = controller.view.fittingSize
        guard size.width > 50, size.height > 50 else { return }
        guard abs(panel.frame.height - size.height) > 0.5
            || abs(panel.frame.width - size.width) > 0.5 else { return }

        let topEdge = panel.frame.maxY
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x, y: topEdge - panel.frame.height))
    }

    // MARK: - Panel

    private func buildPanel() {
        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 216, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.animationBehavior = .utilityWindow

        // A hosting *controller* lets AppKit size the window from SwiftUI's intrinsic
        // layout. A bare NSHostingView reports a zero fittingSize before first layout,
        // which collapses the panel to 0x0 and it never reaches the window server.
        let controller = NSHostingController(rootView: PanelView().environmentObject(store))
        p.contentViewController = controller
        p.layoutIfNeeded()

        var size = controller.view.fittingSize
        if size.width < 50 || size.height < 50 { size = NSSize(width: 216, height: 340) }
        p.setContentSize(size)

        panel = p
        applyPanelLevel()

        // Enable position persistence, restore it, then re-assert the content size in
        // case a stale saved frame disagrees with the current layout.
        p.setFrameAutosaveName("TokenCounterPanelFrame")
        p.setFrameUsingName("TokenCounterPanelFrame")
        p.setContentSize(size)

        if !isOnAnyScreen(p.frame), let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.maxX - p.frame.width - 24, y: v.maxY - p.frame.height - 24))
        }

        p.orderFrontRegardless()
    }

    /// Guards against a saved position on a monitor that is no longer attached.
    private func isOnAnyScreen(_ frame: NSRect) -> Bool {
        guard frame.width > 0, frame.height > 0, frame.origin != .zero else { return false }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    /// Above everything, or pinned to the desktop layer behind normal windows.
    func applyPanelLevel() {
        guard let panel else { return }
        if Prefs.shared.alwaysOnTop {
            panel.level = .floating
        } else {
            panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            Prefs.shared.panelVisible = false
        } else {
            panel.orderFrontRegardless()
            Prefs.shared.panelVisible = true
        }
        updateStatusItem()
    }

    @objc private func refreshNow() {
        store.refresh()
    }

    // MARK: - Settings

    @objc private func showSettings() { openSettings() }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Token Counter"
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(store))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func closeSettings() {
        settingsWindow?.orderOut(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

/// `addItem(withTitle:...)` returns a discardable item; this makes `.target = self` chains legal.
private extension NSMenu {
    @discardableResult
    func addItem(withTitle title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        addItem(item)
        return item
    }
}
