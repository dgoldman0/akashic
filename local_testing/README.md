# Akashic TUI Development

`akashic_tui.py` is the supported test harness between this repository and the
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

Profiles are `codec-json`, `jsonrpc`, `interop` (the non-TUI runtime and
interoperability contracts), `agent` (provider-neutral conversations),
`agent-ui`, `desktop` (Desk with all five applets), `desktop-agent`, `pad`,
`fexplorer`, `daybook`, and `grid`.
Generated images, terminal text, cell JSON, and PNG captures go under
`local_testing/out/`.

The smoke journeys exercise application behavior, not just boot markers:

| Profile | Verified journey |
|---|---|
| `codec-json` | owned value decode/encode, nested containers, Unicode, duplicate rejection, schema coercion, JSON Schema projection, bounds, and stack balance |
| `jsonrpc` | strict native JSON grammar, JSON-RPC message forms, escaped methods, bounded serialization, method dispatch, handler faults, and stack balance |
| `interop` | instance-relative state, isolated instances, registry lookup, bounded request dispatch, and typed values without loading TUI |
| `agent` | native offline fallback, provider connection, streamed transcript assembly, approval resolution, cancellation, and owned conversation cleanup without loading TUI |
| `agent-ui` | transcript, streaming, prompt, review, cancellation, reconnect, resize, and terminal rendering |
| `pad` | edit/undo/redo, open/find/go-to, fragmented multi-sector Save As, exact bytes, word and line replacement, dirty-state redraw |
| `fexplorer` | create file/folder, rename, copy/paste, confirmed deletion, preview, and persisted MP64FS metadata |
| `daybook` | task capture, completion, exact Markdown persistence, responsive calendar/agenda resize |
| `grid` | formula edit, dependent `SUM` recalculation, CSV persistence/reload, virtual-grid resize |
| `desktop-agent` | all five applets, direct intents, deterministic conversation/tool approval, global prompt, focus, and resize |

Run the focused profile plus `desktop-agent` before changing shared TUI, VFS,
agent, or app-shell behavior. The normal suite is fully native and offline.

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

In the agent desktop profiles, `Alt+1` focuses Pad, `Alt+2` File Explorer,
`Alt+3` Daybook, `Alt+4` Grid, and `Alt+5` Agent. `Ctrl+Space` or `Alt+A` opens
Desk's global agent prompt. Desk's other shortcuts remain documented in
`docs/tui/applets/desk/desk.md`.
Bare F1-F12 keys are forwarded to the guest. Viewer controls use `Ctrl+F5` to
pause/resume, `Ctrl+F10` to pause and step one instruction, `Ctrl+R` to reset,
and `Ctrl+Q` to close only the viewer. Combined guest shortcuts such as
`Ctrl+Shift+S` are encoded with CSI-u and work from both the viewer and
`session_ctl.py`.
