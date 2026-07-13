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
an entry synchronizes its source immediately. A failed save leaves Daybook
visibly dirty. Closing a dirty Daybook is fail-closed and requires typing
`DISCARD`; a second close request is issued by the confirmation, so Desk does
not prompt the child twice.

## Standalone and Shared Modes

Standalone Daybook remains the control case: an instance with no runtime
endpoint reads `/daybook.md` directly and publishes with its private `VREPL`
staged replacement. An attached endpoint which fails to supply Context is
treated as broken runtime wiring and blocks instead of selecting this control
path. The genuine standalone behavior and its recovery contracts are
otherwise unchanged.

Inside Desk, Daybook instead discovers the active Context, resource registry,
request bus, and `org.akashic.resource.daybook` RID through its endpoint. It
copies the RID and attaches an activation-local `RREF`/`LBIND` lens to the
shared document owner. Loads request `resource.snapshot`; saves request
`resource.replace` at the binding's exact revision and advance the binding only
after a successful owner commit. Daybook never receives the owner's VFS path,
replacement object, or private buffer.

Reference lookup and lens attachment are separate guarded registry operations.
Daybook retries a bounded exact-reference race; repeated contention is reported
as transient stale state, while missing or invalid services remain structural
and block rather than being confused with stale status codes.

If the owner reports a successful commit but the local binding cannot advance,
the commit remains authoritative: Daybook does not claim the save failed or
roll back a captured entry that is already durable. It clears the unusable
binding, marks the source blocked, and requires an explicit reload before any
later write.

If another lens commits first, save is rejected as stale, the edited model
stays dirty, and Daybook asks the user to reload before saving. Reload is the
explicit refresh boundary: it resolves the current resource reference,
reattaches the lens, and then snapshots. If a valid Desk Context is present but
any shared-resource service or attachment is unavailable, Daybook enters
`Shared resource blocked` mode and will not silently fall back to writing
`/daybook.md`.

`Edit Source in Pad` (Ctrl+O) emits the semantic resource URI from the current
binding in shared mode; standalone mode continues to emit `vfs:/daybook.md`.
Task capture persists through the same owner. Because general derived authority
does not yet exist, its nested replace is an explicitly approved, bounded
implementation hop inside the already-authorized `daybook.task.capture`
handler—not a reusable delegation mechanism.

This experiment does not make the VFS path globally exclusive. Trusted code
and File Explorer can still write `/daybook.md` directly, outside the owner's
revision sequence. The migrated Daybook/Pad path therefore demonstrates
coordinated semantic lenses by convention, not system-wide mediation. That gap
is part of the evidence for deciding whether the additional Practice machinery
earns its complexity.

## Durable Format

Daybook recognizes these UTF-8 Markdown records:

```markdown
# Daybook

- 2026-07-10 09:30 | Project review
- [ ] 2026-07-10 | Send the revised draft
- [x] 2026-07-10 | Morning walk
> 2026-07-10 | Keep this note legible outside the app
```

Import is deliberately strict and lossless. A source must contain one canonical
`# Daybook` heading before its records; blank lines and the three record forms
shown above are the only accepted lines. Dates and event times must be valid,
`[x]` is lowercase, record text is valid single-line UTF-8 of at most 120 bytes,
and the file may contain at most 96 records. Files over 32 KiB are rejected
before any read. Unknown or malformed lines, short reads, overlong text, and
capacity overflow reject the complete import rather than dropping or
truncating data.

Load uses an exact read and validates the complete buffer in a non-mutating
first pass. Only a successful second pass replaces the current model; every
failure preserves both the entries and dirty state. Reloading a dirty model
requires typing `RELOAD`, and a failed confirmed reload still preserves it.
Any load or recovery failure also blocks subsequent saves, preventing an edit
from overwriting the unaccepted external source. The status bar reports
`Source blocked`; saving is enabled again only after a clean reload (or a
confirmed reload when the in-memory model is dirty).

The exact-read path treats its file descriptor and previous VFS selector as
separate owned cleanup stages. It relinquishes each ownership marker before
calling the corresponding void cleanup operation, so a cleanup that completes
and then throws is never retried. Close and selector restoration are caught
independently, and restoration is still attempted when close fails. Any such
cleanup fault is normalized to a load I/O failure: parsing and publication do
not run, entries and dirty state remain unchanged, and the source becomes
blocked until a clean reload succeeds.

Save uses the generic VFS staged-replacement protocol. The candidate is written
and read back exactly, synchronized, and published through a checksummed
rollback marker and same-directory backup. Activation and every load recover a
pending replacement before opening `/daybook.md`; the live target is never
truncated in place. A committed target whose backup cleanup remains is treated
as saved, while ambiguous or corrupt recovery state fails closed.

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
| Ctrl+R | Reload the current Daybook source |
| Ctrl+O | Edit the source in Pad (semantic resource in Desk) |
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

`python3 local_testing/akashic_tui.py smoke --profile daybook-contracts` adds
deterministic checks for atomic strict import, unknown/malformed lines, the
96-record and 120-byte limits, pre-read oversize rejection, injected short
reads, staged persistence, interrupted-publication recovery, artifact cleanup,
corrupt-marker refusal, blocked-source overwrite prevention, dirty-state
preservation, and close negotiation. It also injects after-effect throws from
descriptor close and VFS-selector restoration, proving that both cleanup
stages are attempted exactly once, the descriptor free list remains intact,
the previous selector is restored, and no failed load publishes a model.

`python3 local_testing/test_daybook_shared_lens.py` supplies the four Desk
services to two headless Daybook instances. It verifies snapshot/replace,
revision advancement, stale overwrite refusal, reload/reattach, semantic source
URI emission, nested task-capture persistence, and fail-closed behavior when a
valid Context exposes an incomplete shared-resource service set or an attached
endpoint loses its Context service.

## Deliberate Next Steps

The broader ecosystem design still calls for project/tag fields, deferral,
search and backlinks, daily note files, and Pad `open-path` intents. Those
features should build on this strict calendar, prompt, recovery, VFS, and
responsive-layout path rather than changing the plain-text source-of-truth
principle.
