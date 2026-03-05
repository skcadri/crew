// Crew — entry point placeholder.
// The real app entry point will be CrewApp.swift (SwiftUI @main) added in TICKET-001.
// This file exists solely to satisfy the Swift package executable target requirement
// during headless (non-Xcode) builds.

import Foundation

// Smoke-test: verify DB singleton can be created and tables initialised.
let db = Database.shared
print("Crew database ready at ~/Library/Application Support/Crew/crew.db")
