# Phase B Tickets (Codex Wave)

## B1 Plan Mode + Approval Loop
- Add explicit plan stage before execution in chat workflows.
- Add plan approval UI: Approve, Approve with feedback, Reject.
- Persist plan status per workspace/chat.

## B2 Ask-User Question UX
- Add structured question prompt card in chat.
- Keyboard-first response UX.
- Pause/resume agent flow around pending question.

## B3 Workspace .context System
- Create .context dir per workspace.
- Attachment and shared-context indexing.
- Expose APIs for agents to include .context files.

## B4 Notes / Scratchpad Tab
- Add Notes tab per workspace (markdown editor + preview).
- Persist notes on disk in .context/notes.md.

## B5 Chat Summaries + TOC
- Auto summarize long chats.
- TOC navigation by headings/sections.
- Persist summary snapshots.

## B6 Integration & Migration Pass
- Add shared models/migrations for B1–B5.
- Ensure layout routing for Notes/Plan/Questions/Summary.
- Add docs + tests.
