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
            CommandGroup(replacing: .newItem) {
                Button("New Workspace") {
                    // TICKET-004: Wire up workspace creation
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // ── App Preferences shortcut ─────────────────────────
            // ⌘, is handled automatically by the Settings scene below,
            // but we keep this group for any future menu additions.
            CommandGroup(after: .appInfo) {
                EmptyView()
            }
        }

        // ── Settings Window (⌘,) ─────────────────────────────────
        Settings {
            SettingsView()
        }
    }
}
