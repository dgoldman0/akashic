# Desk shell composition

`tui/desk-apt1.f` composes the canonical shell snapshot and the shell producer
alongside its final-screen producer. The rich Desktop profile enables it. Its
storage is not sized up front: it starts small and grows from Desk's memory as
the shell needs. A changed draw whose shell layout matches the acknowledged one
goes out as a retained DELTA; layout changes publish a complete hidden START
and reveal ([shell producer](SHELL-SCREEN-PRODUCER.md)). Loading the source
does not start a session or take any shell storage. The Desk run that
qualified it is summarized under [Desktop qualification](#desktop-qualification).

## Selection and storage

Before loading the composition, a product profile selects the shell with:

```forth
-1 CONSTANT APT1-DESK-SHELL-ENABLED
```

The Python `RichTerminalProfile` has a corresponding `shell` switch, false by
default; when it is on, the boot prelude declares the constant before cold
source loading. `desktop_apt1_shell_profile(base=...)` in
`local_testing/akashic_tui.py` returns a new `RichTerminalProfile` that turns
the shell on and adds the PANES/TASKBARS capabilities and the additive host
quotas below to a shell-free base. Its default base is
`DESKTOP_APT1_RICH_TERMINAL_BASE`; the registered rich Desktop uses the result
as `DESKTOP_APT1_RICH_TERMINAL`. A profile that already has the shell is
rejected, so repeated selection cannot accumulate quota, and overflow is
rejected rather than reducing an existing family allowance.

No shell storage has a fixed size. Ordinary Desk keeps its completed-shell
model in two banks that start small and are replaced by one twice as large
whenever a paint's model runs out of room for its entries or text; after a
spike, a bank four times larger than its model is replaced by the smallest
that fits. The shell snapshot copies that model into two banks of its own,
which grow to the models they copy. The shell producer's work space and two
candidate banks grow to what each candidate needs. The snapshot's and the
producer's storage comes from Desk's memory source, the system heap, the same
source the screen producer and the engine grow into. Each part's first blocks
are taken at setup and handed over; everything goes back at release, in the
reverse of the order it was taken. A refusal of memory leaves that part
CELL, and the screen producer's fallback record keeps the bytes asked for and
held. Without memory for its own model, Desk paints a blank taskbar row with
nothing to press.

## Additive host capacity

These are what the profile's terminal grants the shell: a budget for a Desk
with 64 panes, 64 tasks and 12 pins and their text. Desk's own model is not
bounded by them; a larger shell asks the terminal for more space, which the
terminal may refuse. Let `E = 140` be the entry budget and
`T = 49152 - 128 - 168 * E = 25504` the text budget. The derived budgets are
`R = E + 3 = 143` regions, `C = E + 2 = 142` controls and `P = E = 140` panes.
Each valid title or label uses a disjoint part of the model's text, so
variable UTF-8 is counted once. Copied action IDs stay in the sidecar and are
not emitted again as provider text.

| Selected host allowance | Addition |
| --- | ---: |
| Regions | `R = 143` |
| Objects | `C + P = 282` |
| Operations per transaction | `R + C + P = 425` |
| Retained UTF-8 | `T = 25504` bytes |
| Retained and base transaction bytes | `104*R + 120*C + 144*P + T = 77576` |

The guest needs no matching reservation: the engine's working banks grow to
what each admission needs.

Atomic payload selection also includes `104 + T = 25608`, covering the largest
pane title and the smaller task/launcher control header. The current app-family
payload bound already exceeds this, so its transport capacity remains unchanged;
a smaller selected base gets an explicit payload/TX increase. Storage-only
selection still leaves host capabilities disabled and therefore uses fallback.

## Lifetime and input

Setup initializes the base producer, the shell facade, and the independent SHSN
source; then it installs the optional shell producer before attaching the
terminal owner. A separate shell construction phase records each successful
step, including failures before the terminal owner exists.

The installed input callback is `RSHSP-CONTROL-TARGET@`. Its committed correlation
and current canonical-source checks authorize the existing APTAS synthetic
pointer route. The ordinary Desk event handler still resolves `SHM-HIT`, checks
the actual task identity or launcher catalogue generation, and performs the
ordinary focus/launch operation. The composition adds no direct terminal-aware
application actions. Non-shell control targets retain the existing producer
resolver.

Release first drains and detaches the exact APTAS owner. Only then may
`RSHSP-UNINSTALL-AFTER-STOP` retire optional candidate authority and
`RSHSP-FINI` give back the producer's storage, SHSN detach its observers and
`SHSN-FINI` give back its banks, and the shell facade be finalized before the
base facade. A failed release preserves the remaining phase for a retry.
Partial setup uses the same path before an owner has been installed.

The rich Desktop profile, its single-applet checks and the constrained-text
`desktop-apt1-small-terminal` check all run with the shell. The host's
`reference` appearance remains the default
and `flowing` remains opt-in. Selection does not change geometry or bypass
complete candidate admission and fallback.

## Focused qualification

`local_testing/test_rich_shell_composition.py` exercises the full cold KDOS and
Desk source closure on the native simulator with 384 MiB external memory and a
256 MiB general XMEM partition. Setup takes only the first, smallest blocks
from Desk's memory source, the snapshot and the shell producer own them once
set up, and release gives every byte back: the memory source holds nothing
after release, and the system heap's high-water mark does not move over
repeated setup and release.

The executable lifecycle proof covers successful installation, a foreign draw
observer refusing source installation at shell phase 2, and a real sidecar
constructor followed by an injected installation refusal at phase 4. Both
refusals unwind successfully and permit a later setup; the foreign observer is
preserved. Profile checks reject an enabled boot replayed against the
disabled profile and a non-bool selection; selection checks cover unchanged
base banks, additive quotas, overflow, duplicate selection and a smaller base's
atomic payload increase.

## Desktop qualification

PANE and TASKBAR/TASK/LAUNCHER passed the complete Desk journey on
2026-09-30, in one combined run that also repeated the Grid, STATUS_FIELD,
FIELD and SERIES/WAVEFORM probes. It ran at Akashic `c19c092` with MegaPad
`cb0f27b`. The rich Desktop profile (`desktop-apt1`) selects the shell by
default; at the time its work arena and banks had fixed sizes, 8 MiB and two
of 4 MiB.

The runner, `local_testing/run_headless_grid_acceptance.py`, drove Desk at
280 by 84 cells. It starts Desk through the real `megapad.main --mode simulator
--executor native` entry point, replaces only the Unix listener with
in-process dispatch, and composes into an SDL dummy sink. It ran the native
simulator without machine code, so it is not a hybrid or prepared
machine-task Desk run. It does not cover sockets, a physical display, audio
or UART, and it qualifies objects and input, not font coverage or
pixel-level design.

After the other probes, the shell probe took five snapshots: a baseline,
then after an ACTIVATE of another task, after Alt+M minimized that task,
after an ACTIVATE of the minimized task restored it, and after an ACTIVATE
of a catalog launcher whose component was already running. At each one the
runner paused the guest at a completed PRESENT and required Desk's ordinary
shell model to match the acknowledged shell bank and every retained shell
claim of that exact offer. Component identity came from the native lifecycle
and catalog records, never from painted titles or application names. Task
identities stayed stable, with one selected task and two TASKBAR roots
throughout. Minimizing removed only the target PANE, and restoring brought
back its exact pane geometry. The launcher step proves activation and focus
of a running component, not the creation of a new instance.

These acceptance rules remain in force. If backpressure accepts no input
and a newer offer arrives, the probe drops the old control ID and resolves
the same ordinary component again from the new source; it never replays an
old ID against a new offer. The source reader checks the producer arena as
the native code does, as an unsigned range that must not wrap, and reads
only the fixed 336-byte target header. Two producer corrections from this
run, explicit clips for fully visible instrument roots and the START-ACK
frontier advance, are described in the
[shell producer](SHELL-SCREEN-PRODUCER.md).

The run predates DELTA publication. Every changed draw was then a complete
START, so the run proved that every waveform sample survived shell
replacement, not that identities were reused. Over its five snapshots the
largest scratch use was 3,490,336 bytes of the 8 MiB work arena, the active
bank held 318,456 bytes of its 4 MiB, and the copied shell model held 24,065
of its 49,152 bytes. These are observations at five points, not worst-case
bounds. Since then the storage grows instead: in the Desk + Pad physical
check at the same size, the work space grew to about 4.3 MB and each bank to
about 130 KB.

From the Akashic checkout, with the paired MegaPad native extensions built:

```sh
python local_testing/run_headless_grid_acceptance.py \
  --megapad-root /path/to/megapad --output build/shell-qualification \
  --deadline 480 --require-shell
```

`--require-shell` also turns on the STATUS_FIELD, FIELD and SERIES probes.
