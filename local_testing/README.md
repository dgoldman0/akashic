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

Smoke and served sessions use 32 MiB of emulated external memory by default.
This leaves realistic headroom for the userland dictionary and applet working
sets as the Desk image grows; pass `--ext-mem-mib N` to test another budget.

Profiles are `credential`, `http-request`, `tls-port`, `net-stream`, `mcp`,
`mcp-component`, `codec-json`, `jsonrpc`, `openai-codec`, `openai-provider`,
`openai-source`, `codex-auth`, `codex-catalog`, `codex-source`,
`codex-live-tls` (opt-in, credential-free TAP/TLS gate),
`codex-live-auth` (opt-in native device-flow probe),
`conversation-store`,
`agent-context`, `agent-persistence`,
`agent-security`, `agent-access`, `agent-applet-capabilities`,
`interop` (the non-TUI runtime and interoperability contracts),
`resource-contracts` (resource-reference and lens-binding contracts),
`practice-contracts` (Practice/Context/facet/Mandate authority contracts),
`agent`
(provider-neutral conversations), `agent-ui`, `agent-layout-ui`,
`agent-auth-ui`, `agent-widgets`,
`agent-device-ui`, `desktop` (Desk with all five applets), `desktop-agent`,
`desktop-agent-hardening`,
`desktop-fallback`, `desktop-recovery`,
`desktop-codex`, `desktop-codex-live` (opt-in TAP-backed shared environment),
`pad`, `pad-contracts`, `fexplorer`, `daybook`, `daybook-contracts`,
`grid-eval`, `grid-contracts`, and `grid`.
Generated images, terminal text, cell JSON, and PNG captures go under
`local_testing/out/`.

Closures that exceed MP64FS's entry or byte limits are linked into
dependency-ordered native Forth chunks under `/.akashic/`, each below KDOS's
255-sector module-transfer ceiling. This includes the full Desktop and several
large focused Agent/provider profiles; smaller profiles keep ordinary
per-module `REQUIRE` loading. Linking and deployment-only comment stripping
change only generated images, not source organization, executable tokens, or
runtime ABI. The copied KDOS source receives the narrower safe transform: only
blank and full-line backslash-comment lines are omitted.

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
| `openai-provider` | a fully in-guest HTTP/SSE fixture through request streaming, tool discovery, persistent-write approval, native capability execution, stateless tool continuation, asynchronous token refresh, byte-identical one-shot 401 replay, one-time tool-history commit, terminal repeated 401, final transcript text, cancellation, credential-use accounting, request zeroization, and stack balance |
| `openai-source` | provider-source composition, KDOS TLS-port ownership, provider construction, generic authentication, reconnect, credential clearing/zeroization, and stack balance without opening a network connection |
| `codex-auth` | native device authorization, pending polling, PKCE exchange, JWT claims, account/plan metadata, refresh rotation, cancellation, logout, zeroization, and stack balance |
| `codex-catalog` | source-pinned authenticated catalog request, bounded parse/filter/sort, model instructions, reasoning/tier/verbosity selection, ordinary and Responses Lite projection, malformed recovery, exact one-shot 401 retry, and stack balance |
| `codex-source` | Codex source composition, exact-host WE1 trust provisioning, separate auth/model KDOS TLS ports, catalog/provider/runtime ownership, Responses Lite header binding, cleanup, and stack balance without opening a network connection |
| `codex-live-tls` | opt-in credential-free native DNS/TCP/TLS authentication of `auth.openai.com` and `chatgpt.com`; no HTTP request, login code, token, or API key is sent |
| `codex-live-auth` | opt-in native device-code request, displayed browser code, persistent-connection polling, and bounded transport/auth diagnostics against `auth.openai.com` |
| `agent-context` | structured turns, transcript-independent model items, provider/tool identity, source filtering, bounded rollback, and stack balance |
| `conversation-store` | checksummed bounded transcript encoding, alternating VFS generations, newest-valid selection, corruption fallback, fail-closed loading, interrupted-state normalization, deterministic VFS/codec fault cleanup, uncertain-publication recovery, ownership cleanup, and stack balance |
| `agent-persistence` | completed approval audit, repeated runtime reconstruction over one native VFS, interrupted approval recovery, run-ID continuity, durable clearing, and stack balance |
| `agent-security` | recursively typed operand seals, post-review mutation denial, one-shot authority, bounded audit/review output, disclosure accounting, cancellation races, lifecycle quiescence, provider-boundary failures, and stack balance |
| `agent-access` | exact immutable access presets, unavailable/busy rejection, scoped target selection, and stale focused-instance rejection |
| `agent-applet-capabilities` | bounded Pad and File Explorer observations, UTF-8 integrity, null results, handler-fault cleanup, exact capability schemas, and stack balance |
| `interop` | instance-relative state, isolated instances, capability validation at registration and owner dispatch, legacy zero-resource requests, explicit queued/running/complete request lifecycle, bounded dispatch, and typed values without loading TUI |
| `resource-contracts` | pointer-free stable resource references, canonical URI round trips, Context-scoped bounded resolution, the one-resource-per-owner-instance invariant, stale revision/instance/epoch rejection, pointer-free lens bindings, queued/running reuse rejection, completed request reuse, exact resource stamping/dispatch, revision advancement, and stack balance |
| `practice-contracts` | versioned Practice/Context/Mandate/Turn layouts, sealed one-use grants, semantic newest-to-older head validation, rejected-candidate diagnostics, exact target-generation facets, frozen Mandate Run bindings, tool/disclosure exhaustion, recovery, and stack balance |
| `agent` | native offline fallback, provider connection, streamed transcript assembly, approval resolution, cancellation, and owned conversation cleanup without loading TUI |
| `agent-ui` | transcript, streaming, prompt, review, cancellation, reconnect, resize, and terminal rendering |
| `agent-layout-ui` | hard-newline and Unicode-aware wrapping, visual-row scrolling, resize reflow, and stable transcript anchors at wide and compact terminal sizes |
| `agent-auth-ui` | native OpenAI source selection, missing-credential state, masked entry, cancellation, reconnect, clearing, resize, and plaintext absence from all captures |
| `agent-widgets` | provider-neutral account and run-settings panel states, selection, refresh, cancellation, direct Escape close behavior, and stack balance |
| `agent-device-ui` | external-browser device code, pending/connected/sign-out states, catalog loading, model/reasoning/speed/verbosity controls, conversation, cancellation, and resize through a reusable native development source |
| `pad` | edit/undo/redo, open/find/go-to, fragmented multi-sector Save As, exact bytes, word and line replacement, dirty-state redraw |
| `pad-contracts` | open-buffer search reporting and wraparound navigation, exact line/column jumps, canonical paths, exact bounded load, crash-recoverable replacement, failure rollback, dirty-close negotiation, all 16 worst-case newline-dense buffers, repeated slot reuse, and resource/stack balance |
| `fexplorer` | create file/folder, rename, copy/paste, confirmed deletion, preview, and persisted MP64FS metadata |
| `daybook` | task capture, completion, exact Markdown persistence, responsive calendar/agenda resize |
| `daybook-contracts` | transactional strict import, source bounds, injected short reads, staged replacement, interrupted-publication recovery, dirty-state preservation, close negotiation, and stack balance |
| `grid-eval` | bounded dependency traversal, exact depth/cycle/error classification, recovery after errors, and stack balance |
| `grid-contracts` | strict transactional CSV import, exact shape bounds, oversized and injected short reads, source blocking, failed-sync rollback, replacement cleanup, close registration, and stack balance |
| `grid` | formula edit, dependent `SUM` recalculation, CSV persistence/reload, virtual-grid resize |
| `desktop-agent` | all five applets, direct intents, deterministic Mandate-scoped agenda read and reviewed task capture, hidden raw-source-name rejection, global prompt, focus, persistence, and resize |
| `desktop-agent-hardening` | exact Chat/read/assist facets, bounded scoped history, structured local review and denial, excluded-capability rejection, cancellation, no-target chat, Agent lens relaunch, shared transcript persistence, and full production component closure |
| `desktop-fallback` | cold Desk boot from one structurally valid older Practice-head slot when the newer MP64FS envelope is corrupt, with visible fallback status and normal applet activation |
| `desktop-recovery` | cold dual-corruption boot into a visible read-only shell with applets, interop, Agent/provider, and transient authority suppressed |
| `desktop-codex` | the complete linked Desktop with the real native Codex source, signed-out account gating, model-readiness gating, all applets, and production-shaped visual boot |
| `desktop-codex-live` | the same linked Desktop with explicit TAP network configuration for watchable native device login and subscription-backed Codex use |

Run the focused profile plus `desktop-agent` before changing shared TUI, VFS,
agent, or app-shell behavior. The normal suite is fully native and offline.
The OpenAI profiles use deterministic in-guest fixture credentials and
transports; they never contact OpenAI or require a developer API key.

The substrate and lifecycle regressions also have focused production-emulator
drivers:

```bash
python3 local_testing/test_guard.py
python3 local_testing/test_vfs_replace.py
python3 local_testing/test_explorer_transactions.py
python3 local_testing/test_applet_close.py
```

The applet-close driver deliberately isolates the guarded APP-SHELL contract;
run the `desktop` and `desktop-agent` profiles for the full linked Desk
lifecycle.

The default Desk Practice validator is structural. CRC and record validation
detect corruption and torn envelopes, but do not authenticate a hostile
replacement or validate a manifest/schema object graph. The development image
may provision a blank Practice only when both slots are genuinely absent; this
is bootstrap fixture behavior, not secure Practice enrollment. The current
recovery profile proves fail-closed startup, not an inspection or repair
console.

The substrate freeze first appended a 32-byte semantic `CBR.RESOURCE-ID`,
growing the request record from 432 to 464 bytes. The later typed-operand seal
added its canonical length, SHA3-256 digest, and seal state, growing
`CBR-SIZE` from 464 to 512 bytes. Existing earlier field offsets are unchanged
and a zero resource ID remains the legacy/non-lens default. Any precompiled
code that allocated either former request size must be rebuilt.

MP64FS test images remain limited to 4096 sectors (2 MiB) even though the host
image builder can describe a larger disk. KDOS currently formats, reads, and
writes one 512-byte allocation bitmap, so sectors beyond bit 4095 are not
mountable by the guest. Raising this limit requires a versioned multi-sector
bitmap design plus mount, allocation, recovery, and compatibility tests; it is
tracked as substrate work rather than being folded into applet or Agent
changes. Focused profiles may omit unrelated large-file fixtures to stay
within the supported image format, but they must not omit production modules
or resources in their declared scope. Generated images also omit non-executable
blank/comment lines; production source and the declared component set remain
unchanged.

## Opt-In Live Network

The live profiles require a user-owned TAP interface. From the workspace root,
one script configures it and immediately runs the credential-free gate:

```bash
sudo local_testing/setup_codex_live.sh
```

The script creates or reuses `mp64tap0`, enables forwarding and masquerading,
drops back to the account that invoked `sudo`, and runs this gate command. It
authenticates both source-pinned hosts with the native KDOS TLS stack but sends
no application request:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile codex-live-tls --nic-tap mp64tap0 \
  --max-steps 5000000000 --timeout 300
```

The Codex source provisions Google Trust Services WE1 as two exact-host
anchors: `auth.openai.com` and `chatgpt.com`. It does not trust `openai.com`,
`api.openai.com`, arbitrary subdomains, or unrelated services. The anchor is
valid through 2029-02-20; certificate/algorithm rotation must be handled as an
explicit reviewed update, not an automatic network download.

The live gate uses MegaPad's standards-only public ClientHello. Private
MegaPad hybrid suites and groups are not offered to OpenAI endpoints. On
failure, the report includes both Akashic's broad transport error and KDOS's
native handshake-phase status, plus a bounded TAP frame trace.

After that keyless gate, the focused device-flow probe can be kept alive for a
browser authorization run:

```bash
python3 local_testing/akashic_tui.py serve \
  --profile codex-live-auth --nic-tap mp64tap0 \
  --socket /tmp/akashic-tui.sock
```

The `desktop-codex-live` smoke journey automatically focuses Agent, opens F9,
starts login, and verifies that the guest reaches the displayed-code state.
Use `serve` for a watched login that must continue through browser completion,
catalog discovery, and conversation.

## Shared Live Environment

Start the machine owner:

```bash
python3 local_testing/akashic_tui.py serve \
  --profile desktop --socket /tmp/akashic-tui.sock
```

For native Codex account access after the credential-free gate passes:

```bash
python3 local_testing/akashic_tui.py serve \
  --profile desktop-codex-live --nic-tap mp64tap0 \
  --socket /tmp/akashic-tui.sock
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
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock network
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock forth \
  _ASHELL-LAST-TICK DESK-DESC
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock peek 0x1000 4
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
In Agent, F8 opens provider-neutral model/run settings and F9 opens account
access. For the direct API provider, `Ctrl+K` opens masked credential entry and
`Ctrl+Shift+K` clears the active credential. Codex device login shows an
external verification URL and one-time code; it does not require a guest
browser or an API key.
Bare F1-F12 keys are forwarded to the guest. Viewer controls use `Ctrl+F5` to
pause/resume, `Ctrl+F10` to pause and step one instruction, `Ctrl+R` to reset,
and `Ctrl+Q` to close only the viewer. Combined guest shortcuts such as
`Ctrl+Shift+S` are encoded with CSI-u and work from both the viewer and
`session_ctl.py`.
