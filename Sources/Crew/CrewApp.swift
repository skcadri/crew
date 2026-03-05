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
            CommandGroup(replacing: .newItem) {
                Button("New Workspace") {
                    // TICKET-004: Wire up workspace creation
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
