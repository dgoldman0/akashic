# Akashic Pad

A minimal text editor for **KDOS / Megapad-64**, built on the
UIDL-TUI widget stack.  Akashic Pad is an *application* — it lives
in `akashic/examples/pad/akashic-pad.f` and demonstrates how to
compose the TUI library into a working program.

## Quick Start

```
python local_testing/boot_editor.py          # build + boot
python local_testing/boot_editor.py --build-only   # image only
```

The BIOS loads `kdos.f`, KDOS runs `autoexec.f`, which loads
`akashic-pad.f`.  The editor fills the 80×24 terminal.

## Keyboard

| Key | Action |
|-----|--------|
| Printable keys | Insert at cursor |
| Enter | Insert newline |
| Backspace | Delete before cursor |
| Delete | Delete at cursor |
| Arrow keys | Move cursor |
| Home / End | Start / end of line |
| PgUp / PgDn | Scroll by visible height |
| Ctrl+Left / Ctrl+Right | Word movement |
| Shift+Arrow | Extend selection (all directions) |
| Shift+Home / Shift+End | Select to start / end of line |
| Shift+PgUp / Shift+PgDn | Select by page |
| Ctrl+A | Select all |
| Ctrl+C | Copy selection to clipboard |
| Ctrl+X | Cut selection to clipboard |
| Ctrl+V | Paste from clipboard |
| Ctrl+Q | Quit |

## Architecture

```
akashic-pad.f            (application — examples/pad/)
  ├── tui/uidl-tui.f     (UIDL ↔ TUI bridge)
  │     ├── tui/widgets/textarea.f
  │     ├── tui/keys.f
  │     ├── tui/screen.f, draw.f, cell.f, …
  │     └── liraq/uidl.f, markup/xml.f, …
  └── utils/clipboard.f  (XMEM ring-buffer clipboard)
```

The editor defines a UIDL document inline:

```xml
<uidl cols='80' rows='24'>
  <textarea id='editor'/>
  <status>
    <label id='st-msg'  text='Ready'/>
    <label id='st-pos'  text='Ln 1, Col 1'/>
    <label id='st-mode' text='INSERT'/>
  </status>
  <action id='k-quit' do='quit' key='Ctrl+Q'/>
</uidl>
```

`UTUI-LOAD` parses the document and materialises widgets.  The event
loop calls `KEY-READ` → `UTUI-DISPATCH-KEY`.  Unhandled events
(Ctrl+C/X/V) fall through to app-layer clipboard logic.

### Clipboard integration

Clipboard operations are intentionally **not** in the textarea widget.
The widget exposes small primitives (`TXTA-GET-SEL`, `TXTA-DEL-SEL`,
`TXTA-INS-STR`) that the app layer composes with `clipboard.f`:

| App word | Widget call | Clipboard call |
|----------|------------|----------------|
| `_PAD-COPY` | `TXTA-GET-SEL` | `CLIP-COPY` |
| `_PAD-CUT` | `TXTA-GET-SEL` + `TXTA-DEL-SEL` | `CLIP-COPY` |
| `_PAD-PASTE` | `TXTA-INS-STR` | `CLIP-PASTE` |

After cut/paste the app marks the UIDL element dirty
(`UIDL-DIRTY!`) so `UTUI-PAINT` repaints in the same cycle.

### Selection model

Selection is an *anchor + cursor* range stored in the textarea
descriptor at offset +88 (`sel-anchor`).  A value of −1 means no
active selection.

- **Shift+movement** sets the anchor (if unset) and moves the
  cursor — the selected range is always `min(anchor, cursor)` to
  `max(anchor, cursor)`.
- **Any unshifted movement** clears selection.
- **Typing, Backspace, Delete** delete the selection first, then
  apply the edit.
- **Ctrl+A** sets anchor=0, cursor=buf-len.
- Selected text renders with **reverse video** (CELL-A-REVERSE).

### Status bar

The bottom row shows three labels:

| Label | Content |
|-------|---------|
| `st-msg` | "Ready" (clean) or "Modified" (dirty) |
| `st-pos` | "Ln N, Col M" (1-based, updated every cycle) |
| `st-mode` | "INSERT" (placeholder for future overwrite mode) |

`_PAD-ON-CHANGE` is wired as the textarea's change callback.  On the
first edit it pokes "Modified" into the `st-msg` attribute.

## Limitations (current state)

- **No file I/O.**  There is no save/load — the buffer exists only
  in memory.  File system integration is planned for a future phase.
- **No undo/redo.**  The clipboard ring keeps recent copies but
  there is no edit history.
- **Single buffer.**  Only one document at a time.
- **Fixed 80×24.**  No terminal resize handling.
- **INSERT mode only.**  Overwrite mode is not implemented.
- **No line numbers.**  The status bar shows the cursor position but
  the gutter does not display line numbers.
- **No syntax highlighting.**
- **No find/replace.**
- **Shift+Arrow in some terminals.**  Shift+Arrow sequences
  (`ESC[1;2A` etc.) work correctly in raw-mode terminals, but some
  terminal emulators (notably VS Code's integrated terminal) may
  intercept Shift+Arrow for their own selection and never forward
  the escape sequence to the child process.  Use a standard
  terminal (xterm, gnome-terminal, Alacritty, kitty, etc.) for
  full keyboard support.

## Dependencies

| File | Purpose |
|------|---------|
| `tui/uidl-tui.f` | UIDL document → TUI widget tree |
| `tui/widgets/textarea.f` | Multi-line editor widget |
| `tui/keys.f` | VT/CSI key decoder |
| `utils/clipboard.f` | XMEM-backed clipboard ring (8 slots) |

All dependencies are loaded via `REQUIRE` from within the source
files; the disk image built by `boot_editor.py` provides the full
chain.

## Testing

```bash
# Widget-level tests (textarea mechanics):
python local_testing/test_tui_app.py      # 29 tests — core textarea
python local_testing/diag_batch_a.py      # 13 tests — PgUp/PgDn, word nav, dirty
python local_testing/diag_batch_b.py      # 38 tests — selection, clipboard, Shift+Arrow

# Interactive:
python local_testing/boot_editor.py       # boots the full editor
```
