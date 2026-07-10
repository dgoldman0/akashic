# Akashic TUI Development

`akashic_tui.py` is the supported bridge between this repository and the
sibling MegaPad checkout. It builds only the transitive `REQUIRE` closure for
the selected app profile, preserving the source paths inside MP64FS. It does
not use or create `local_testing/emu`.

By default the repositories are expected to be siblings:

```text
fantasy-computing/
  akashic/
  megapad/
```

Set `MEGAPAD_ROOT` when using a different layout.

## Build And Smoke Test

```bash
python3 local_testing/akashic_tui.py build --profile desktop
python3 local_testing/akashic_tui.py smoke --profile desktop
```

Profiles are `desktop` (Desk with all four applets), `pad`, `fexplorer`,
`daybook`, and `grid`. Generated images, terminal text, cell JSON, and PNG
captures go under `local_testing/out/`.

The smoke journeys exercise application behavior, not just boot markers:

| Profile | Verified journey |
|---|---|
| `pad` | edit/undo/redo, open/find/go-to, fragmented multi-sector Save As, exact bytes, word and line replacement, dirty-state redraw |
| `fexplorer` | create file/folder, rename, copy/paste, confirmed deletion, preview, and persisted MP64FS metadata |
| `daybook` | task capture, completion, exact Markdown persistence, responsive calendar/agenda resize |
| `grid` | formula edit, dependent `SUM` recalculation, CSV persistence/reload, virtual-grid resize |
| `desktop` | Pad, File Explorer, Daybook, and Grid boot together with app focus/routing, compact layouts, resize, editing, and live terminal redraw |

Run all five before changing shared TUI, VFS, or app-shell behavior.

## Shared Live Environment

Start the machine owner:

```bash
python3 local_testing/akashic_tui.py serve \
  --profile desktop --socket /tmp/akashic-tui.sock
```

Attach the viewer from the workspace root in another terminal:

```bash
python3 megapad/session_viewer.py \
  --socket /tmp/akashic-tui.sock \
  --font akashic/assets/fonts/DejaVuSansMono.ttf \
  --title "Akashic TUI"
```

The viewer and automation clients share the same guest. Control it with:

```bash
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock status
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock key alt+1
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock send "hello"
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock resize 120 36
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock capture \
  --text akashic/local_testing/out/live.txt \
  --json akashic/local_testing/out/live.cells.json \
  --png akashic/local_testing/out/live.png
```

In the desktop profile, `Alt+1` focuses Pad, `Alt+2` File Explorer, `Alt+3`
Daybook, and `Alt+4` Grid. Desk's other shortcuts remain documented in
`docs/tui/applets/desk/desk.md`.
Bare F1-F12 keys are forwarded to the guest. Viewer controls use `Ctrl+F5` to
pause/resume, `Ctrl+F10` to pause and step one instruction, `Ctrl+R` to reset,
and `Ctrl+Q` to close only the viewer. Combined guest shortcuts such as
`Ctrl+Shift+S` are encoded with CSI-u and work from both the viewer and
`session_ctl.py`.
