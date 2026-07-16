import AppKit
import SwiftUI

/// Lazily creates and manages the resizable dashboard window. Exposed to SwiftUI
/// as an `EnvironmentObject` so the menu-bar popover's "open window" button can
/// summon it.
@MainActor
final class DashboardWindowManager: ObservableObject {
    private let store: UsageStore
    private var window: NSWindow?

    init(store: UsageStore) { self.store = store }

    func show() {
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static let defaultSize = NSSize(width: 600, height: 720)
    private static let minSize = NSSize(width: 470, height: 440)

    private func makeWindow() -> NSWindow {
        let root = DashboardView().environmentObject(store)

        // Clear NSHostingView's automatic sizing so the SwiftUI content simply
        // fills our resizable window rather than fighting it for a size.
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: Self.defaultSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Token Usage"
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minSize
        window.contentView = hosting
        window.center()
        // Restores (and persists) the user's chosen size/position across launches.
        window.setFrameAutosaveName("TokenUsageDashboard")
        return window
    }
}
