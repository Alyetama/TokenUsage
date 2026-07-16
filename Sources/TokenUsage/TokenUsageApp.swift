import SwiftUI

@main
struct TokenUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.dashboard)
                // A fixed height is required: a menu-bar window sizes itself to
                // its content, and the inner ScrollView has no intrinsic height,
                // so without this the agent list collapses to nothing.
                .frame(width: 380, height: 500)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the shared store and the dashboard window, and drives periodic refreshes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    lazy var dashboard = DashboardWindowManager(store: store)
    private var timer: Timer?
    private var watcher: UsageWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless self-check: `TOKENUSAGE_DUMP=1 ./.build/release/TokenUsage`
        // prints a usage summary and exits, without showing any UI.
        if ProcessInfo.processInfo.environment["TOKENUSAGE_DUMP"] != nil {
            DebugDump.run()
            exit(0)
        }
        // Headless parser self-test: `TOKENUSAGE_SELFTEST=1 ./TokenUsage`.
        if ProcessInfo.processInfo.environment["TOKENUSAGE_SELFTEST"] != nil {
            DebugDump.selfTest()
            exit(0)
        }

        // A regular app: Dock icon + a real window, plus the menu-bar item.
        NSApp.setActivationPolicy(.regular)
        store.refresh()
        dashboard.show()

        // Refresh the moment any agent writes to its logs…
        let home = FileManager.default.homeDirectoryForCurrentUser
        watcher = UsageWatcher(
            paths: [".claude/projects", ".codex/sessions", ".kimi-code/sessions",
                    ".minimax", ".local/share/opencode"]
                .map { home.appendingPathComponent($0).path },
            onChange: { [weak store] in store?.refresh() }
        )
        // …with a relaxed fallback poll for missed events and agents installed
        // after launch. Tolerance lets the system batch the wakeup (energy).
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak store] _ in
            Task { @MainActor in store?.refresh() }
        }
        timer?.tolerance = 20
    }

    /// Clicking the Dock icon re-opens the dashboard window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboard.show()
        return true
    }
}

/// The compact content shown in the macOS menu bar: a gauge and the running
/// total token count.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(Fmt.tokens(store.totalCounts.total))
                .monospacedDigit()
        }
    }
}
