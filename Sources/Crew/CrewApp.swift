import SwiftUI

@main
struct CrewApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1200, minHeight: 800)
        }
        .defaultSize(width: 1400, height: 900)
        .commands {
            CrewCommands()
        }

        // MARK: Settings window (⌘,)
        Settings {
            SettingsPlaceholderView()
        }
    }
}

// MARK: - Settings placeholder

/// Lightweight settings view until TICKET-010 is fully wired up.
private struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gear")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Settings")
                .font(.title2)
                .fontWeight(.medium)
            Text("API keys and preferences coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(width: 480, height: 320)
        .padding()
    }
}
