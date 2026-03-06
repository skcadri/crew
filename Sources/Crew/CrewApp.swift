import SwiftUI

@main
struct CrewApp: App {
    var body: some Scene {
        // ── Main Window ──────────────────────────────────────────
        WindowGroup {
            ContentView()
                .frame(minWidth: 1200, minHeight: 800)
        }
        .defaultSize(width: 1400, height: 900)
        .commands {
            CrewCommands()
        }

        // ── Settings Window (⌘,) ─────────────────────────────────
        Settings {
            SettingsView()
        }
    }
}
