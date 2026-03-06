import SwiftUI

// MARK: - CrewCommands

/// Keyboard shortcuts and menu commands for Crew.
struct CrewCommands: Commands {

    var body: some Commands {

        // MARK: File Menu — replace default New Item

        CommandGroup(replacing: .newItem) {
            Button("New Workspace") {
                NotificationCenter.default.post(name: .crewNewWorkspace, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Workspace from Branch…") {
                NotificationCenter.default.post(name: .crewNewWorkspaceFromBranch, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Close Tab") {
                NotificationCenter.default.post(name: .crewCloseTab, object: nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        // MARK: Workspace Menu — switching and git actions

        CommandMenu("Workspace") {
            Button("Command Palette…") {
                NotificationCenter.default.post(name: .crewOpenCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            // ⌘1–⌘9 to switch workspace tabs
            ForEach(1..<10, id: \.self) { index in
                Button("Switch to Tab \(index)") {
                    NotificationCenter.default.post(
                        name: .crewSwitchWorkspaceTab,
                        object: nil,
                        userInfo: ["index": index]
                    )
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }

            Divider()

            Button("Commit and Push") {
                NotificationCenter.default.post(name: .crewCommitAndPush, object: nil)
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])

            Button("Refresh Workspace") {
                NotificationCenter.default.post(name: .crewRefreshWorkspace, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") {
                NotificationCenter.default.post(name: .crewShowShortcutCheatSheet, object: nil)
            }
            .keyboardShortcut("/", modifiers: .command)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let crewNewWorkspace           = Notification.Name("crew.newWorkspace")
    static let crewNewWorkspaceFromBranch = Notification.Name("crew.newWorkspaceFromBranch")
    static let crewCloseTab               = Notification.Name("crew.closeTab")
    static let crewSwitchWorkspaceTab     = Notification.Name("crew.switchWorkspaceTab")
    static let crewCommitAndPush          = Notification.Name("crew.commitAndPush")
    static let crewOpenCommandPalette     = Notification.Name("crew.openCommandPalette")
    static let crewRefreshWorkspace       = Notification.Name("crew.refreshWorkspace")
    static let crewShowShortcutCheatSheet = Notification.Name("crew.showShortcutCheatSheet")
}
