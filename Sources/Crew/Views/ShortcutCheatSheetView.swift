import SwiftUI

struct ShortcutCheatSheetView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("⌘N", "New workspace"),
        ("⇧⌘N", "New workspace from branch"),
        ("⌘W", "Close current workspace tab"),
        ("⌘1…⌘9", "Switch to workspace tab 1 through 9"),
        ("⇧⌘Y", "Commit and push"),
        ("⌘R", "Refresh workspace"),
        ("⌘/", "Open keyboard shortcut cheat sheet"),
        ("Return", "Send chat message / submit answer"),
        ("Shift+Return", "Insert newline in chat input")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Keyboard Shortcuts", systemImage: "command")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Quick reference for frequently-used Crew actions.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(shortcuts, id: \.0) { shortcut, action in
                HStack {
                    Text(shortcut)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .frame(width: 90, alignment: .leading)
                    Text(action)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(shortcut): \(action)")
            }
            .listStyle(.inset)
        }
        .padding(18)
        .frame(minWidth: 480, minHeight: 360)
    }
}

#Preview {
    ShortcutCheatSheetView()
}
