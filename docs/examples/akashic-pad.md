# Akashic Pad

Akashic Pad is the UIDL-based text editor applet for KDOS and MegaPad-64.
Its implementation lives in `akashic/tui/applets/pad/`; it can run by itself
through `PAD-RUN` or inside Desk through `PAD-ENTRY`.

## Run And Test

From the Akashic repository:

```bash
python3 local_testing/akashic_tui.py smoke --profile pad
python3 local_testing/akashic_tui.py smoke --profile pad-contracts
```

The smoke profile builds a bootable MP64FS image from Pad's transitive
`REQUIRE` closure, boots it in the sibling MegaPad checkout, drives real key
events through the guest, and captures terminal text, cells, and PNG output in
`local_testing/out/`.

For a shared live machine that a person can watch while another process drives
it, see [`local_testing/README.md`](../../local_testing/README.md).

## Features

- Up to 16 open buffers with a dynamic tab strip and per-buffer cursor,
  selection, scroll, dirty, undo, and redo state.
- Arena-backed gap-buffer text with independently reclaimable packed line
  indexes and a compact four-column line-number gutter.
- A cell-accurate software caret that remains visible when Pad is hosted by
  Desk or observed through the shared-session viewer.
- VFS-backed new, open, save, Save As, and Save All operations.
- Crash-recoverable staged replacement with exact readback, including files
  that shrink and files that grow into fragmented MP64FS extents.
- Sidebar file explorer and optional output pane.
- Clipboard copy, cut, and paste.
- Find with wraparound, single replacement, go to line, and go to file.
- Word, line, and full-document selection.
- Dirty-buffer confirmation for close tab, close all, and quit.
- TOML-configurable colors and responsive terminal layout.

## Keyboard

The textarea also supports ordinary cursor movement, Home/End, Page Up/Page
Down, Ctrl+Left/Ctrl+Right word movement, and Shift-modified movement for
selection.

| Key | Action |
|---|---|
| Ctrl+N | New buffer |
| Ctrl+O | Open path |
| Ctrl+S | Save |
| Ctrl+Shift+S | Save As |
| Ctrl+W | Close active tab |
| Ctrl+Q | Quit |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Ctrl+C / Ctrl+X / Ctrl+V | Copy / cut / paste |
| Ctrl+A | Select all |
| Ctrl+D | Select current word |
| Ctrl+L | Select current line, including its line break |
| Ctrl+Shift+K | Delete current line |
| Ctrl+F | Find |
| Ctrl+H | Find and replace |
| Ctrl+G | Go to line |
| Ctrl+P | Go to file |
| Ctrl+B | Toggle sidebar |
| Ctrl+J | Toggle output pane |
| Ctrl+PageDown / Ctrl+PageUp | Next / previous tab |
| Tab | Insert spaces to the next four-column tab stop |

## Architecture

```text
pad.f / pad.uidl
  |
  +-- app-shell.f + app-desc.f       lifecycle and host integration
  +-- uidl-tui.f                     menus, splits, status, shortcuts
  +-- explorer.f                     VFS sidebar
  +-- textarea.f                     editing, cursor, selection, redraw
  |     +-- gap-buf.f                text storage and line index
  |     +-- undo.f                   per-buffer edit history
  +-- prompt.f                       non-blocking status-row command bar
  +-- vfs.f + vfs-mp64fs.f           file I/O and persistence
  |     +-- vfs-replace.f            staged replace and recovery
  +-- clipboard.f + search.f         app-level editing operations
```

Pad mounts a custom panel widget into the UIDL `editor-area` region. The panel
draws the tab strip and delegates the content rows to one shared textarea. A
buffer switch saves the current textarea state, rebinds that textarea to the
new buffer's gap buffer and undo object, restores cursor and selection state,
and dirties the panel for repaint. The panel then overlays the caret from the
textarea's logical line, column, and scroll state, so its position is part of
the captured cell grid rather than host-terminal state.

The status row doubles as a command bar. `prompt.f` receives normal shell key
events, so open, Save As, find, replace, and go-to operations remain inside the
main event loop. This is important when Pad is hosted by Desk: no nested
blocking input loop steals terminal ownership from the desktop.

## File I/O

Pad uses the abstract VFS API rather than KDOS directory internals. It
canonicalizes every path, rejects traversal and reserved replacement names,
captures one immutable buffer snapshot, and publishes that snapshot through
`VREPL-REPLACE`. Recovery runs before an open or save. A save clears dirty state
only when publication succeeded (including the committed-cleanup status); a
failure retains both the editor model and its dirty state.

Opening performs an exact bounded read into a new buffer. Files larger than
64 KiB, short reads, recovery failures, and unexpected VFS throws are reported
instead of silently truncating the document. A failed open closes the candidate
tab and restores the original active buffer. MP64FS can extend files through a
primary and secondary extent, and staged replacement verifies the exact bytes
before publication.

## Selection And Editing

Textarea selections are half-open byte ranges represented by an anchor and the
cursor. Selecting a word or line moves the gap to the range endpoint but leaves
the anchor at its start. The first inserted character deletes the selected
range, moves the cursor to the start, and then inserts normally; later
characters append at the updated gap.

All gap-buffer mutators have strict stack contracts. `GB-INS`, `GB-DEL`, and
`GB-BS` update the affected line-index range incrementally; `GB-SET` performs a
bounded whole-document rebuild after sizing the packed index once. This is
covered by focused gap-buffer tests and the Pad contract journey.

## Current Boundaries

- There is no syntax-highlighting or language-server layer yet.
- The output pane is present but is not connected to a build/run task system.
- Loading one file is capped at 64 KiB. All 16 retained tab slots have been
  exercised simultaneously with worst-case newline-dense 64 KiB documents;
  packed line indexes are reclaimed independently of the fixed editor arena.
- Find-and-replace replaces one wrapped match per invocation rather than all
  matches.

These are product-level extensions; the core multi-buffer editing, navigation,
selection, persistence, and Desk-hosted workflows are functional.
