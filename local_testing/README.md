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

Profiles are `credential`, `http-request`, `tls-port`, `net-stream`, `mcp`,
`mcp-component`, `codec-json`, `jsonrpc`, `openai-codec`, `openai-provider`,
`openai-source`, `codex-auth`, `codex-source`, `conversation-store`,
`agent-context`, `agent-persistence`,
`interop` (the non-TUI runtime and interoperability contracts), `agent`
(provider-neutral conversations), `agent-ui`, `agent-auth-ui`, `desktop` (Desk
with all five applets), `desktop-agent`, `pad`, `fexplorer`, `daybook`, and
`grid`.
Generated images, terminal text, cell JSON, and PNG captures go under
`local_testing/out/`.

The smoke journeys exercise application behavior, not just boot markers:

| Profile | Verified journey |
|---|---|
| `credential` | native bounded secret replacement, callback-only borrowing, callback fault isolation, overlap rejection, generation/use metadata, replacement and clear zeroization, allocation cleanup, and stack balance |
| `http-request` | caller-owned request framing, header validation, partial cooperative sends, transport cancellation and faults, capacity sentinels, authorization-buffer zeroization, and stack balance |
| `tls-port` | caller-owned KDOS DNS/TLS binding, SNI and trust gating, authenticated opens, partial I/O, idle/EOF distinction, single-owner serialization, callback faults, retries, and stack balance |
| `net-stream` | native incremental SSE and HTTP parsing across every fixture boundary, body framing, trailers, interim responses, EOF, limits, callback isolation, cooperative receive pumping, cancellation, transport faults, and stack balance |
| `mcp` | native lifecycle gating, initialization, ping, tool discovery/call, resource and template discovery, resource reads, malformed requests, and stack balance |
| `mcp-component` | native component catalog mapping, stable names and URIs, approved persistence, denial, approval-required, timeout, malformed arguments, resources, stale targets, and stack balance |
| `codec-json` | owned value decode/encode, nested containers, Unicode, duplicate rejection, schema coercion, JSON Schema projection, bounds, and stack balance |
| `jsonrpc` | strict native JSON grammar, JSON-RPC message forms, escaped methods, bounded serialization, method dispatch, handler faults, and stack balance |
| `openai-codec` | native Responses request projection, strict tool schemas and stable names, stateless continuation history, representative stream-event decoding, provider construction/binding, credential-backed runtime connection, bounds, and stack balance |
| `openai-provider` | a fully in-guest HTTP/SSE fixture through request streaming, tool discovery, persistent-write approval, native capability execution, stateless tool continuation, final transcript text, cancellation, credential-use accounting, request zeroization, and stack balance |
| `openai-source` | provider-source composition, KDOS TLS-port ownership, provider construction, generic authentication, reconnect, credential clearing/zeroization, and stack balance without opening a network connection |
| `codex-auth` | native device authorization, pending polling, PKCE exchange, JWT claims, account/plan metadata, refresh rotation, cancellation, logout, zeroization, and stack balance |
| `codex-source` | Codex source composition, separate auth/model KDOS TLS ports, provider/runtime ownership, account-port binding, cleanup, and stack balance without opening a network connection |
| `agent-context` | structured turns, transcript-independent model items, provider/tool identity, source filtering, bounded rollback, and stack balance |
| `conversation-store` | checksummed bounded transcript encoding, alternating VFS generations, newest-valid selection, corruption fallback, fail-closed loading, interrupted-state normalization, ownership cleanup, and stack balance |
| `agent-persistence` | completed approval audit, repeated runtime reconstruction over one native VFS, interrupted approval recovery, run-ID continuity, durable clearing, and stack balance |
| `interop` | instance-relative state, isolated instances, registry lookup, bounded request dispatch, and typed values without loading TUI |
| `agent` | native offline fallback, provider connection, streamed transcript assembly, approval resolution, cancellation, and owned conversation cleanup without loading TUI |
| `agent-ui` | transcript, streaming, prompt, review, cancellation, reconnect, resize, and terminal rendering |
| `agent-auth-ui` | native OpenAI source selection, missing-credential state, masked entry, cancellation, reconnect, clearing, resize, and plaintext absence from all captures |
| `pad` | edit/undo/redo, open/find/go-to, fragmented multi-sector Save As, exact bytes, word and line replacement, dirty-state redraw |
| `fexplorer` | create file/folder, rename, copy/paste, confirmed deletion, preview, and persisted MP64FS metadata |
| `daybook` | task capture, completion, exact Markdown persistence, responsive calendar/agenda resize |
| `grid` | formula edit, dependent `SUM` recalculation, CSV persistence/reload, virtual-grid resize |
| `desktop-agent` | all five applets, direct intents, deterministic conversation/tool approval, global prompt, focus, and resize |

Run the focused profile plus `desktop-agent` before changing shared TUI, VFS,
agent, or app-shell behavior. The normal suite is fully native and offline.
The OpenAI profiles use deterministic in-guest fixture credentials and
transports; they never contact OpenAI or require a developer API key.

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
In Agent, `Ctrl+K` opens masked credential entry and `Ctrl+Shift+K` clears the
active provider credential.
Bare F1-F12 keys are forwarded to the guest. Viewer controls use `Ctrl+F5` to
pause/resume, `Ctrl+F10` to pause and step one instruction, `Ctrl+R` to reset,
and `Ctrl+Q` to close only the viewer. Combined guest shortcuts such as
`Ctrl+Shift+S` are encoded with CSI-u and work from both the viewer and
`session_ctl.py`.
