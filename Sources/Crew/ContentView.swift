import SwiftUI

struct ContentView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedWorkspaceID: String? = nil

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left column: Sidebar
            SidebarView(selectedWorkspaceID: $selectedWorkspaceID)
        } content: {
            // Center column: Agent workspace / detail
            DetailPlaceholder(selectedWorkspaceID: selectedWorkspaceID)
        } detail: {
            // Right column: Inspector
            InspectorView(selectedWorkspaceID: selectedWorkspaceID)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    ContentView()
        .frame(width: 1400, height: 900)
}
