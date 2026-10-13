# Scheduled Agent runs that read a Library document — 2026-10-12

A scheduled Agent run can now read one exact version of a Library document
as data. Library sends the version to Daybook, Desk's user approves the run
with the document named, and when the run starts Desk attaches the document
through Library, starting Library minimized when it is closed. The run reads
the document as itself, and a document that has changed since stops the run
for review. This is step 2 of the second Daybook scheduler slice; step 1,
prompt-only runs, is in [its note](daybook-agent-runs-20261012.md). The design
is in [automations](../../docs/tui/applets/daybook/automations.md), the
[resource owner directory](../../docs/interop/resource-owners.md), Library's
[scheduled runs section](../../docs/tui/applets/library/library.md) and the
Agent's [dispatcher](../../docs/tui/applets/agent/dispatch.md).

This note records the runs that qualify step 2 end to end on
`feature/daybook-scheduler`: Akashic `ffef9ef7`, which follows the host fix
`e10477df`, with MegaPad `5f06bc22`. MegaPad did not change.

This is functional evidence. It is not a timing comparison with earlier
runs, and it covers neither a real device nor a real model provider. The host
ran 11 to 21 million guest steps per second during these runs, about a
quarter of July's speed, so wall times here are long.

## Runs

| Run | Backend and clock | Akashic tree | Result | Steps or time | Peak memory |
| --- | --- | --- | --- | --- | --- |
| `desktop-daybook-agent-document` smoke | emulator, virtual clock | `ffef9ef7`'s files, before its commit | pass | 8,409,724,502 steps, 441 s | 315,640 KiB, one process |
| `desktop-daybook-agent` smoke | emulator, virtual clock | `ffef9ef7`'s code, an earlier harness | pass | 4,559,310,519 steps, 255 s | 315,408 KiB |
| `desktop-daybook-agent-recovery` smoke | emulator, virtual clock | `ffef9ef7`'s code, an earlier harness | pass | 2,575,232,650 steps, 291 s | 753,372 KiB |
| `desktop-daybook-reminders` smoke | emulator, virtual clock | `ffef9ef7`'s code, an earlier harness | pass | 2,870,231,971 steps, 222 s | 532,852 KiB |
| `desk-service-table-contracts` smoke | emulator | `ffef9ef7`'s code, an earlier harness | pass | 1,500,181,056 steps, 66 s | 228,180 KiB |
| `applet-host-contracts` | emulator | `ffef9ef7`'s code, an earlier harness | pass, 487 checks | | |
| Desk with Daybook | simulator, host clock | `ffef9ef7`'s files, before its commit | pass | 160.1 s | 488,525,824 bytes, aggregate |
| Desk with the Agent | simulator, host clock | `ffef9ef7`'s files, before its commit | pass | 63.0 s | 501,612,544 bytes, aggregate |
| Desktop journey | simulator, host clock | `ffef9ef7`, clean | pass | 221.1 s | 527,151,104 bytes, aggregate |
| `library-projection-owner-contracts` | emulator | `ffef9ef7`, clean | pass, 872 assertions | 59,598,262,725 steps, 3,115 s | 358,196 KiB |
| `library-applet-functional-contracts` | emulator | `ffef9ef7`, clean | pass, 696 assertions | 49,569,603,501 steps, 2,486 s | 236,192 KiB |

The runs on `ffef9ef7`'s files used exactly what the commit holds; only
its message came after them. The runs with an earlier harness used the
commit's code and ran just before the document journey's last changes in
the harness, which they do not run. Each ran alone. The physical runs used
MegaPad's native extension (SHA-256
`5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6`),
DejaVuSansMono at 18 px, the simulator backend with the native executor, a
0.75 s action delay, a 10 s hold, the 900 s watchdog and the 3.5 GiB
aggregate-RSS stop. All ran in source mode, with no compiled Forth cache,
step-limit change or timing change. The OpenAI and Agent smokes
(`openai-codec`, `openai-provider`, `agent-security`, `agent-access`) also
passed on step 2's content before its last fixes, to Library and the
applet host, neither of which they load.

```bash
python3 local_testing/akashic_tui.py smoke --profile desktop-daybook-agent-document
python3 local_testing/physical_desktop_acceptance.py \
  --akashic-root . --megapad-root ../megapad \
  --font assets/fonts/DejaVuSansMono.ttf \
  --output-parent <scratch directory> [--applet agent | --applet daybook]
python3 local_testing/akashic_tui.py smoke \
  --profile library-projection-owner-contracts \
  --max-steps 70000000000 --timeout 3600
python3 local_testing/akashic_tui.py smoke \
  --profile library-applet-functional-contracts \
  --max-steps 55000000000 --timeout 3600
```

## What the runs show

**The document smoke (CELL, emulator).** Desk runs with Daybook, the Agent
and Library, the Agent on the scripted provider, and the journey types
ordinary keys.

- Library makes "Field notes", 39 bytes, through Ctrl+N. Its first document
  makes its store. Library's tile is too narrow for its preview, but it reads
  the selected version's preview as it lists it.
- Ctrl+G sends that exact version to Daybook as the intent
  `agent-run.schedule`. Daybook comes forward and begins a new Agent run
  reading it, once Desk has described the document through Library; its
  prompt page names the document.
- The run is daily, on gpt-fast. Desk's approval names the document as
  "Field notes, revision 1, 39 bytes" and the run may disclose 59 bytes, the
  prompt and the document. After A, Daybook's file holds the run approved,
  with observe effects and the context flag.
- Library closes. When the run comes due, Desk starts Library minimized, in
  the taskbar with no tile and no focus, and the run reads the document. The
  Agent's transcript says "Read the document: Field notes (revision 1, 39
  bytes)" and never shows its text; the scripted model reports a reference of
  39 bytes with the document's SHA3 prefix, so it was given the exact text.
- Library comes back when the user asks for it by its number.
- Renamed there, "Field notes (revised)" is at revision 2. The run started by
  hand stops for review before it reads anything: Daybook's list, the
  schedule's details and the Agent's runs all say "stopped for review: the
  document changed".

What each step cost the guest, as steps and its own clock. These are
device costs: at 100 MHz, 100 million steps is one second.

| Step | Steps | Guest time |
| --- | --- | --- |
| Library's first document, which makes its store | about 1.7 billion | |
| Ctrl+G until Daybook's first step, with the document described | 275 million | 3.5 s |
| Ctrl+S until Desk's approval, with the document described | 330 million | 4.2 s |
| A until Daybook says "Approved" | 100 million | 1.3 s |
| Alt+W until Library has closed | 150 million | 10.8 s |
| Renaming the document | 1.42 billion | 18.1 s |

**The other Desk smokes** passed as on step 1. The early idle samples were
0.7% of the clock, and the Agent smoke's end sample, held to the 10%
ceiling, was 0.9%.

**Rich.** The Daybook-alone and Agent-alone journeys passed unchanged. The
canonical Desktop journey passed with the same 48 milestones and 51 inputs as
the step 1 runs.

**Library fixtures.** Both pass on the commit, within their step limits:
the projection owner contract, which now reads a snapshot into a buffer of
exactly the document's size, with 872 assertions, and the applet's
lifecycle, which now opens and closes the documents' owner with its
service, with 696. This is the projection fixture's first pass on this
branch: its earlier runs here, when the 16 MiB change landed, failed for
want of external memory, which main has since given it.

## Found and fixed while qualifying

- Library published its documents' owner only when its store already existed
  as it started. A Library whose first document made its store during the
  session published nothing, and Daybook could not describe the document it
  sent. It now publishes each time its service opens. The document smoke
  fails without this.
- Desk's applet host drew a child that changed itself as it ticked only when
  something else asked Desk to paint. Daybook recorded the approval 1.3 s
  after A but showed "Approved" 845 s later, when the run came due. The host
  now draws such a child in the same pass (`e10477df`, with its own contract
  scenario).

## Not covered

- A real model provider. The OpenAI and Codex providers still hold a turn's
  input in fixed buffers, so a prompt and document over about 32 KiB are
  refused there as too large for the model; making them grow is the next
  landing.
- Large documents in Desk. The smoke's document is 39 bytes; the native
  suites read documents up to the run's disclosure, and the value system and
  resource contract carry up to 16 MiB.
- A real device's clock, UART, panel or touch.
- Library's own costs above: its first document, a rename and its close.
  They are Library's, not step 2's, and are noted for Library's own work.
- The rich terminal with Library. No rich journey drives Library.
