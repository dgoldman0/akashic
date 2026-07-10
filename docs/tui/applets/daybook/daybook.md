# Daybook

Daybook is Akashic's daily planner for dated events, tasks, and notes. It runs
standalone through `DAYBOOK-RUN` or as an `APP-DESC` inside Desk through
`DAYBOOK-ENTRY`.

**Provider:** `akashic-tui-daybook`

## Current User Model

The default view combines a month calendar with the selected day's agenda.
When the app is too narrow for both panes, the agenda takes the full tile. The
agenda groups entries into Schedule, Tasks, and Notes and keeps one entry
selected for keyboard actions.

Quick capture uses the shared non-blocking prompt widget. Creating or changing
an entry synchronizes `/daybook.md` immediately, so Pad and File Explorer see
the same ordinary file.

## Durable Format

Daybook recognizes these UTF-8 Markdown records:

```markdown
# Daybook

- 2026-07-10 09:30 | Project review
- [ ] 2026-07-10 | Send the revised draft
- [x] 2026-07-10 | Morning walk
> 2026-07-10 | Keep this note legible outside the app
```

Unknown lines are ignored when loading. Saving rewrites the recognized entries
in canonical form beneath the `# Daybook` heading. The current MP64FS write
path is exact and synchronized, but it is not yet a transactional or
two-generation replacement protocol.

## Keys

| Key | Action |
|---|---|
| Left / Right | Previous or next day |
| Page Up / Page Down | Previous or next week |
| Up / Down | Select an agenda entry |
| Space / Enter | Toggle the selected task |
| Home or `t` | Return to today |
| Ctrl+N | Capture a task |
| Ctrl+E | Capture an event as `HH:MM title` |
| Ctrl+Shift+N | Capture a note |
| Delete | Delete the selected entry |
| Ctrl+S | Save |
| Ctrl+R | Reload `/daybook.md` |
| Ctrl+Q | Quit standalone Daybook |

## Public Words

| Word | Stack | Purpose |
|---|---|---|
| `DAYBOOK-ENTRY` | `( desc -- )` | Fill an application descriptor for Desk |
| `DAYBOOK-RUN` | `( -- )` | Run Daybook in the shared app shell |

## Verification

`python3 local_testing/akashic_tui.py smoke --profile daybook` boots a seeded
disk, captures a task through the prompt, completes it, verifies the exact
Markdown record in live MP64FS state, resizes the terminal, and writes text,
cell, raw-terminal, and PNG captures under `local_testing/out/`.

## Deliberate Next Steps

The broader ecosystem design still calls for project/tag fields, deferral,
search and backlinks, daily note files, Pad `open-path` intents, and
crash-recoverable replacement. Those features should build on this proven
calendar, prompt, VFS, and responsive-layout path rather than changing the
plain-text source-of-truth principle.
