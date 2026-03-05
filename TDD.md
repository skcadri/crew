# Crew — Technical Design Document

**Version:** 1.0
**Date:** 2026-03-02
**Project:** Conductor clone — Run a team of coding agents on your Mac

---

## 1. Overview

Crew is a native macOS application that lets you run multiple coding agents (Claude Code, Codex, local LM Studio models) in parallel, each in isolated git worktrees. It provides a GUI to manage workspaces, chat with agents, view diffs, and merge changes.

### 1.1 Goals
- Match Conductor's core functionality
- Native local model support (LM Studio — zero API cost)
- Direct distribution + Setapp

### 1.2 Tech Stack
- **UI:** SwiftUI + AppKit (NSViewRepresentable for terminal/streaming)
- **Agent SDKs:** Anthropic Agent SDK (Claude Code), OpenAI (Codex), OpenAI-compatible (LM Studio)
- **Data:** SQLite (via SQLite.swift SPM)
- **Secrets:** macOS Keychain
- **Syntax Highlighting:** Highlightr SPM
- **Min Target:** macOS 14 (Sonoma)

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Crew.app (SwiftUI)                       │
├──────────┬─────────────────────────────┬───────────────────┤
│ Sidebar  │     Agent Chat Panels       │   Inspector       │
│ - Repos  │     (NSTextView wrapped)    │   Model/Branch    │
│ - Agents │                             │   Git Panel       │
└────┬─────┴──────────────┬──────────────┴─────────┬─────────┘
     │                    │                        │
     ▼                    ▼                        ▼
┌─────────────────────────────────────────────────────────────┐
│                   AgentManager (Service)                     │
├──────────────────┬───────────────────┬─────────────────────┤
│ ClaudeCodeAgent  │   CodexAgent      │   LMStudioAgent     │
│ (Agent SDK)      │   (OpenAI SDK)    │   (REST API)        │
└──────────────────┴───────────────────┴─────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│              WorkspaceManager (Git Worktrees)                │
└─────────────────────────────────────────────────────────────┘
```

### Key Modules

| Module | Responsibility |
|--------|----------------|
| `WorkspaceManager` | Git clone, worktree CRUD, diff, merge |
| `AgentManager` | Spawn/manage agent subprocesses |
| `ChatStore` | Persist chat history (SQLite) |
| `SettingsStore` | Preferences + API keys (Keychain) |
| `AppState` | Observable global state |

---

## 3. UI Layout

```
┌──────────────────────────────────────────────────────────────┐
│  Crew                                              ─ □ ✕    │
├─────────┬────────────────────────────────────┬───────────────┤
│ Sidebar │        Agent Workspace              │   Inspector   │
│         │                                     │               │
│ Repos   │  ┌─────────────────────────────┐    │  Model: ...   │
│ ├─proj1 │  │ Tab Bar (chat tabs)         │    │  Branch: ...  │
│ ├─proj2 │  ├─────────────────────────────┤    │               │
│         │  │   Chat Messages (streaming) │    │  [Git Panel]  │
│ Spaces  │  │                             │    │  Changed files │
│ ├─ws1 🟢│  │                             │    │  Diff viewer  │
│ ├─ws2 🔵│  ├─────────────────────────────┤    │               │
│         │  │   Input Field    [Send]     │    │  [Commit]     │
│ [+ New] │  └─────────────────────────────┘    │  [Push]       │
│         ├────────────────────────────────────┤               │
│ ⚙ Prefs │  │   Terminal Output               │               │
│         │  └─────────────────────────────┘    │               │
└─────────┴────────────────────────────────────┴───────────────┘
```

- Min window: 1200×800, default 1400×900
- Dark/light mode support
- SF Pro + SF Mono typography

---

## 4. Tickets

Each ticket is fully self-contained. A single agent can implement it with no dependencies on unfinished work (unless noted).

---

### TICKET-001: Xcode Project + App Shell

**Goal:** Create the Xcode project and three-column SwiftUI layout.

**Files to create:**
```
Crew.xcodeproj (via swift package init or Xcode template)
Crew/
  CrewApp.swift          — @main App entry, WindowGroup
  ContentView.swift      — NavigationSplitView (sidebar | detail | inspector)
  Views/
    SidebarView.swift    — List with sections: Repositories, Workspaces
    DetailPlaceholder.swift — "Select a workspace" placeholder
    InspectorView.swift  — Right column placeholder
```

**Requirements:**
- macOS 14+ deployment target
- NavigationSplitView with three columns
- Window min size 1200×800
- App icon placeholder
- SPM dependencies in Package.swift: SQLite.swift, Highlightr

**Verification:** App launches, shows three-column layout, resizable.

---

### TICKET-002: Data Layer (Models + SQLite)

**Goal:** Domain models and SQLite persistence.

**Files:**
```
Crew/Models/
  Repository.swift       — id, name, url, localPath, createdAt
  Worktree.swift         — id, repoId, branch, path, status, selectedModel, createdAt
  ChatMessage.swift      — id, worktreeId, role (user|assistant), content, timestamp
  AgentType.swift        — enum: claudeCode, codex, lmStudio

Crew/Services/
  Database.swift         — SQLite connection, schema creation, migrations
```

**Schema:**
```sql
CREATE TABLE repos (id TEXT PK, name TEXT, url TEXT, local_path TEXT, created_at INTEGER);
CREATE TABLE worktrees (id TEXT PK, repo_id TEXT FK, branch TEXT, path TEXT, status TEXT DEFAULT 'idle', selected_model TEXT, created_at INTEGER);
CREATE TABLE messages (id TEXT PK, worktree_id TEXT FK, role TEXT, content TEXT, timestamp INTEGER);
```

**Requirements:**
- All models Identifiable, Codable, Hashable
- Database singleton with create/read/update/delete for each table
- DB file at ~/Library/Application Support/Crew/crew.db
- Auto-create tables on first launch

**Verification:** Unit tests pass for CRUD operations.

---

### TICKET-003: Repository Management

**Goal:** Clone repos, list them in sidebar, delete them.

**Files:**
```
Crew/Services/
  GitService.swift       — shell out to git CLI for all git operations
  RepoManager.swift      — clone, list, remove repos

Crew/Views/
  AddRepoSheet.swift     — Sheet with URL field + Clone button
  SidebarView.swift      — UPDATE: show real repos from DB
  RepoRow.swift          — Single repo row with name + icon
```

**Requirements:**
- `GitService.cloneRepo(url:) async throws -> String` — clones to ~/Library/Application Support/Crew/repos/<name>/
- Runs `git clone` via Process
- Progress indicator while cloning
- Repos persist in SQLite
- Delete removes from DB + disk (with confirmation)
- Sidebar shows repos with disclosure groups

**Verification:** Can add a GitHub repo URL, see it clone, appears in sidebar, can delete.

---

### TICKET-004: Worktree Management

**Goal:** Create/delete git worktrees as isolated workspaces.

**Files:**
```
Crew/Services/
  GitService.swift       — UPDATE: add worktree operations
  WorktreeManager.swift  — create, list, delete worktrees

Crew/Views/
  CreateWorkspaceSheet.swift — Sheet: branch name + model picker
  WorkspaceRow.swift     — Status indicator (🟢 idle, 🔵 running, 🟡 review, ✅ done)
  SidebarView.swift      — UPDATE: show worktrees under repos
```

**Requirements:**
- `GitService.createWorktree(repoPath:branch:) async throws -> String`
- Worktrees stored at ~/Library/Application Support/Crew/workspaces/<uuid>/
- New branch created automatically from main/master
- Status enum: idle, running, completed, error
- Sidebar shows worktrees nested under their repo
- Click worktree to select it (updates detail + inspector)

**Verification:** Create workspace from repo, see it in sidebar with status, delete cleans up.

---

### TICKET-005: Agent Protocol + Claude Code

**Goal:** Define agent interface and implement Claude Code agent.

**Files:**
```
Crew/Agents/
  AgentProtocol.swift    — Protocol with spawn/send/cancel
  AgentFactory.swift     — Creates agent by AgentType
  ClaudeCodeAgent.swift  — Spawns `claude` CLI subprocess

Crew/Services/
  AgentManager.swift     — Manages active agent instances per worktree
```

**AgentProtocol:**
```swift
protocol CodingAgent {
    var id: UUID { get }
    var type: AgentType { get }
    var isRunning: Bool { get }
    func start(workdir: String, prompt: String) async throws -> AsyncStream<AgentEvent>
    func send(message: String) async throws -> AsyncStream<AgentEvent>
    func cancel() async
}

enum AgentEvent {
    case text(String)           // Chat text
    case toolUse(String)        // Tool execution info
    case error(String)
    case done
}
```

**Claude Code Integration:**
- Spawn `/usr/local/bin/claude` (or configured path) as Process
- Pass `--print` flag for non-interactive JSON output
- Set `cwd` to worktree path
- Stream stdout line by line → parse → emit AgentEvent
- Cancel kills the process

**Verification:** Can spawn Claude Code in a worktree directory, send prompt, receive streaming output.

---

### TICKET-006: Codex + LM Studio Agents

**Goal:** Implement Codex and LM Studio agents.

**Files:**
```
Crew/Agents/
  CodexAgent.swift       — OpenAI Codex via API
  LMStudioAgent.swift    — Local model via OpenAI-compatible API
```

**Codex:**
- Use URLSession for OpenAI chat completions API
- Stream via SSE (text/event-stream)
- Model: configurable (default gpt-5.3-codex)
- API key from SettingsStore/Keychain

**LM Studio:**
- Same OpenAI-compatible endpoint: http://127.0.0.1:1234/v1/chat/completions
- GET /v1/models to list available models
- Stream via SSE
- No API key needed
- Auto-detect if LM Studio is running (health check on launch)

**Verification:** Both agents can send prompts and receive streaming responses.

---

### TICKET-007: Chat UI

**Goal:** Real-time streaming chat interface.

**Files:**
```
Crew/Views/Chat/
  ChatView.swift         — Main chat container (message list + input)
  MessageBubble.swift    — Individual message (user vs assistant styling)
  ChatInputView.swift    — Text field + Send button + model indicator
  StreamingTextView.swift — NSViewRepresentable wrapping NSTextView for streaming
```

**Requirements:**
- Messages scroll automatically as they stream in
- User messages: right-aligned, blue bubble
- Agent messages: left-aligned, gray bubble with monospace for code
- Markdown rendering in messages (bold, code blocks, lists)
- Enter to send, Shift+Enter for newline
- Loading indicator while agent is thinking
- Chat history loaded from SQLite on workspace open
- New messages saved to SQLite as they complete

**Verification:** Can type message, see streaming response, scroll works, persists across restarts.

---

### TICKET-008: Terminal View

**Goal:** Terminal pane showing agent tool execution output.

**Files:**
```
Crew/Views/Terminal/
  TerminalView.swift     — NSViewRepresentable wrapping NSTextView
  TerminalStore.swift    — Observable buffer for terminal output
```

**Requirements:**
- Monospace font (SF Mono 11pt), dark background
- Append-only text view (no editing)
- Auto-scroll to bottom, manual scroll disengages auto-scroll
- Receives output from AgentEvent.toolUse events
- Clear button in toolbar
- Copy selection support
- Resizable via drag divider between chat and terminal
- ANSI color code support (basic: red/green/yellow/blue)

**Verification:** Agent tool output streams into terminal, auto-scrolls, can clear.

---

### TICKET-009: Git Panel (Diff + Commit + Push)

**Goal:** Show changed files, diffs, and allow commit/push.

**Files:**
```
Crew/Views/Git/
  GitPanelView.swift     — File list + diff viewer in inspector
  DiffView.swift         — Syntax-highlighted unified diff
  FileChangeRow.swift    — File with status icon (M/A/D)
  CommitSheet.swift      — Commit message + file selection + push toggle

Crew/Services/
  GitService.swift       — UPDATE: add status, diff, commit, push operations
```

**Requirements:**
- `git status --porcelain` to get changed files
- `git diff` for unstaged, `git diff --cached` for staged
- Click file to show diff in panel
- Color: additions green, deletions red
- Commit sheet: message field, select/deselect files, optional push
- `git add` → `git commit` → `git push` flow
- Toast notification on success/error
- Auto-refresh after commit

**Verification:** Shows modified files, displays diff, can commit and push.

---

### TICKET-010: Model Picker + Settings

**Goal:** Model selection per workspace and app preferences.

**Files:**
```
Crew/Views/
  ModelPickerView.swift  — Dropdown grouped by provider
  InspectorView.swift    — UPDATE: show model picker + workspace info

Crew/Views/Settings/
  SettingsView.swift     — Preferences window (⌘,)
  GeneralSettingsView.swift — Default model, theme
  APIKeysSettingsView.swift — OpenAI key, Claude Code path, LM Studio URL

Crew/Services/
  SettingsStore.swift    — UserDefaults + Keychain wrapper
```

**Requirements:**
- Model picker grouped: Claude Code (Sonnet, Opus, Haiku) | Codex (GPT-5.3, Spark) | Local (dynamic from LM Studio /v1/models)
- Selected model stored per workspace in SQLite
- Settings window with tabs: General, API Keys
- API keys stored in Keychain (SecItemAdd/SecItemCopyMatching)
- Claude Code path auto-detected or manually set
- LM Studio URL with connection test button
- Theme: System / Light / Dark (follows NSApp.effectiveAppearance)

**Verification:** Can pick model per workspace, settings persist, API keys secure.

---

### TICKET-011: Keyboard Shortcuts + Polish

**Goal:** Standard keyboard shortcuts and UI polish.

**Files:**
```
Crew/
  Commands.swift         — SwiftUI .commands modifier
  CrewApp.swift          — UPDATE: add keyboard commands
```

**Shortcuts:**
| Shortcut | Action |
|----------|--------|
| ⌘N | New workspace |
| ⌘⇧N | New workspace from branch |
| ⌘⇧Y | Commit and push |
| ⌘, | Settings |
| ⌘W | Close tab |
| ⌘1-9 | Switch workspace tabs |

**Polish:**
- Window title shows current workspace name
- Toolbar with New Workspace button
- Status bar at bottom: agent status + model name
- Empty states for all lists ("No repos yet — add one to get started")

**Verification:** All shortcuts work, empty states show, window title updates.

---

## 5. Dependency Graph

```
TICKET-001 (App Shell)
    ├── TICKET-002 (Data Layer)
    │       ├── TICKET-003 (Repo Management)
    │       │       └── TICKET-004 (Worktree Management)
    │       ├── TICKET-007 (Chat UI)
    │       └── TICKET-010 (Settings)
    ├── TICKET-005 (Agent Protocol + Claude Code)
    │       └── TICKET-006 (Codex + LM Studio)
    ├── TICKET-008 (Terminal View)
    └── TICKET-009 (Git Panel)

TICKET-011 (Shortcuts) depends on all above
```

**Parallelizable Wave 1:** TICKET-001
**Parallelizable Wave 2:** TICKET-002, TICKET-005, TICKET-008
**Parallelizable Wave 3:** TICKET-003, TICKET-006, TICKET-007, TICKET-009, TICKET-010
**Final Wave:** TICKET-004, TICKET-011
