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

The authoritative profile registry and each journey's assertions live in
`akashic_tui.py`; `--help` lists the accepted profile names. Profiles are
organized around focused library/runtime contracts, standalone applet journeys,
and linked Desk journeys. Run the narrow profile for the behavior being changed
and the linked profile that owns its production lifecycle. Generated images,
terminal text, cell JSON, and PNG captures go under `local_testing/out/`.

The Streams qualification path is intentionally split by boundary:

- `streams-contracts` covers the owned feed model and typed capabilities.
- `streams-draft-contracts` covers the draft record and replacement primitive.
- `streams-persistence-contracts` covers normal applet load/save/recovery.
- `streams` covers the standalone timeline, context, search, and draft UI.
- `desktop-streams` covers launch, close, relaunch, and recovery through Desk.

The synthetic Streams page lives at
`local_testing/fixtures/atproto/timeline.json`. The harness copies it into the
guest test namespace as `/testing/streams/timeline.json`; it is qualification
input, not an `akashic/atproto` runtime resource or an applet fallback feed.

Closures that exceed MP64FS's entry or byte limits are linked into
dependency-ordered native Forth chunks under `/.akashic/`, each below KDOS's
255-sector module-transfer ceiling. This includes the full Desktop and several
large focused Agent/provider profiles; smaller profiles keep ordinary
per-module `REQUIRE` loading. Linking and deployment-only comment stripping
change only generated images, not source organization, executable tokens, or
runtime ABI. The copied KDOS source receives the narrower safe transform: only
blank and full-line backslash-comment lines are omitted.

Smoke journeys assert semantic application behavior in the guest, not only boot
markers or screenshots. Focused contract profiles cover bounds, ownership,
failure cleanup, and stack balance; applet profiles cover user interaction; Desk
profiles cover the linked lifecycle and Practice boundary. Keep detailed
assertion inventories beside the corresponding profile implementation so they
cannot drift from this README.

The audio qualification path has no host audio-device dependency and does not
claim that numerical checks establish aesthetic quality. Run it with:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile audio-contracts --max-steps 2500000000 --timeout 180
```

The guest leaves bounded mono FP16 buffers and one encoded WAV alive for the
duration of the smoke session, while the headless machine records exact raw
S16 and converted FP16 AudioOut submissions without requiring an audible host
sink. The host reads those exact mapped-memory spans and capture bytes,
recomputes its own time- and frequency-domain results, and writes the FP16
vectors, `audio-output-{raw,fp16}.s16le`, `tone.wav`, and a JSON report under
`local_testing/out/audio-contracts/`. This is deliberately separate from
subjective audition; `aplay local_testing/out/audio-contracts/tone.wav` is an
optional human check after the deterministic contracts pass.

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

`CBR-SIZE` is 512 bytes and includes the semantic resource ID plus the typed
operand seal's canonical length, SHA3-256 digest, and seal state. A zero
resource ID is the legacy/non-lens default. Precompiled code that allocates an
older request-record size must be rebuilt.

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
