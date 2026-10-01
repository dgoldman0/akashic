# Desk shell composition

`tui/desk-apt1.f` composes the canonical shell snapshot and the shell producer
alongside its final-screen producer. The rich Desktop profile enables it with
8 MiB work storage and two 4 MiB immutable banks. A changed draw whose shell
layout matches the acknowledged one goes out as a retained DELTA; layout
changes publish a complete hidden START and reveal
([shell producer](SHELL-SCREEN-PRODUCER.md)). Loading the source does not start
a session, and a composition without the shell declarations allocates no shell
XMEM banks. The Desk run that qualified it is summarized under
[Desktop qualification](#desktop-qualification).

## Explicit storage selection

Before loading the composition, a product profile supplies:

```forth
-1 CONSTANT APT1-DESK-SHELL-ENABLED
\ Both values are positive, eight-byte-aligned u32 byte capacities.
work-bytes CONSTANT APT1-DESK-SHELL-WORK-CAPACITY
bank-bytes CONSTANT APT1-DESK-SHELL-BANK-CAPACITY
```

The Python `RichTerminalProfile` has corresponding optional
`guest_shell_work_bytes` and `guest_shell_bank_bytes` fields. Both default to
zero. A positive pair inserts the three declarations before cold source loading;
a partial pair, unaligned value, or overflow is rejected. Selecting storage does
not enable any retained host capability.

`desktop_apt1_shell_profile(work_bytes=..., bank_bytes=..., base=...)` in
`local_testing/akashic_tui.py` returns a new `RichTerminalProfile` that adds the
explicit storage, PANES/TASKBARS capabilities and the additive host quotas below
to a shell-free base. Its default base is `DESKTOP_APT1_RICH_TERMINAL_BASE`; the
registered rich Desktop uses its 8 MiB / 4 MiB result as
`DESKTOP_APT1_RICH_TERMINAL`. Calling the helper creates a separate value and
does not mutate the base.
Already selected shell profiles are rejected, preventing repeated
selection from accumulating quota. Overflow is rejected rather than reducing an
existing family allowance. The caller installs the returned value as the desired
profile's `rich_terminal` field.

The source model bounds come from ordinary Desk's own canonical storage, without
application-specific counts or title matching:

| Span | Capacity |
| --- | ---: |
| Each copied SHSN source bank | 49,152 bytes |
| Canonical entry limit | 140 entries |
| Canonical text/action budget | 25,504 bytes |
| SHSN source descriptor | `SHSN-SIZE` |
| Shell provider facade | `RTE-SHELL-FACADE-SIZE` |
| Optional producer descriptor | `RSHSP-SIZE` |
| Scratch work bank | explicitly selected work capacity |
| Each immutable candidate bank | explicitly selected bank capacity |

The text budget is `Desk model bytes - SHM header - entry limit * entry size`.
Both source banks therefore have exactly the ordinary model's declared byte
bound. Eight owned allocations each reserve seven alignment bytes. The selected
scratch and candidate banks are finite caller-owned storage, not permission to
truncate a model. A candidate which cannot fit remains on the existing rendering
path. Actual `RSHSP-WORK-USED@` and each `RSHSP-BANK.USED` must be measured on
completed Desk candidates before choosing a shipping profile capacity.

The 8 MiB work / 4 MiB per-candidate capacity targets the
280-by-84 qualification surface. It is not a worst-case guarantee for every
400-by-200 host surface or every maximum-size source graph: the global glyph
scratch reservation alone can exceed 8 MiB at that geometry. The host may retain
its 400-by-200 geometry limit because exact optional-candidate admission remains
authoritative. If the selected scratch or immutable bank cannot hold the complete
candidate, the entire shell candidate is refused and the base scene without
shell chrome, including ordinary CELL coverage, is published instead. No partial
shell claims, truncation or incomplete CELL fallback is permitted. Additive host
and provider quotas below do not change this caller-owned optional-bank policy.

## Additive host and provider capacity

Let `E = 140` be the canonical entry reservation and
`T = 49152 - 128 - 168 * E = 25504` the dense text/action bound. Independent
conservative reservations are `R = E + 3 = 143` regions,
`C = E + 2 = 142` controls and `P = E = 140` panes. Each valid title or label
uses a disjoint subset of the same dense text bank, so variable UTF-8 is bounded
by `T` once. Copied action IDs stay in the sidecar and are not emitted again as
provider text.

| Selected host allowance | Addition |
| --- | ---: |
| Regions | `R = 143` |
| Objects | `C + P = 282` |
| Operations per transaction | `R + C + P = 425` |
| Retained UTF-8 | `T = 25504` bytes |
| Retained and base transaction bytes | `104*R + 120*C + 144*P + T = 77576` |

The enabled Forth composition derives these same reservations from ordinary
Desk's constants before allocating the guest provider. It adds `C` to the
provider's control count, `R` to its region count and `P` to its non-control
objects/operations. Its two-generation control ledger still holds both complete
active and replacement sets until reveal.

| Guest provider storage | Addition |
| --- | ---: |
| Control ledger | `2 * 64 * C = 18176` bytes |
| Operation records | `40 * (R + C + P) = 17000` bytes |
| Immutable copies | `104*R + 168*C + 191*P + T = 90972` bytes |
| Total additional provider storage | `126148` bytes |

The 191-byte pane allowance covers its 184-byte fixed copy plus up to seven
alignment bytes. Existing control/region terms grow with their counts; shell
text is added once. These additions enlarge three existing allocations, so they
add no allocation headers; the measured XMEM delta also reflects their existing
alignment padding. The base UIDL, collection, FIELD, STATUS_FIELD,
DATA_GRAPHICS and producer arena bounds do not change.

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
`RSHSP-UNINSTALL-AFTER-STOP` retire optional candidate authority, SHSN detach its
observers, and the shell facade be finalized before the base facade. A failed
release preserves the remaining phase and its storage for a retry. Partial setup
uses the same path before an owner has been installed.

The rich Desktop profile, its single-applet checks and the constrained-text
`desktop-apt1-small-terminal` check all run with the shell. The host's
`reference` appearance remains the default
and `flowing` remains opt-in. Selection does not change geometry or bypass
complete candidate admission and fallback.

## Focused qualification

`local_testing/test_rich_shell_composition.py` exercises the full cold KDOS and
Desk source closure on the native simulator with 384 MiB external memory and a
256 MiB general XMEM partition. Its experimental 8 MiB work span and two 4 MiB
candidate banks with the additive provider reservations leave 37,070,288 bytes
free after loading and after repeated setup/uninstall. Compared with the disabled
composition, the extra allocation is 17,002,240 bytes, including source banks,
provider reservations, descriptors, alignment, and allocator overhead. Setup and
release allocate no additional storage.

The executable lifecycle proof covers successful installation, a foreign draw
observer refusing source installation at shell phase 2, and a real sidecar
constructor followed by an injected installation refusal at phase 4. Both
refusals unwind successfully and permit a later setup; the foreign observer is
preserved. Profile checks reject partial/unaligned bounds and an enabled boot
replayed against the disabled profile; explicit selection checks cover unchanged
base banks, additive quotas, overflow, duplicate selection and a smaller base's
atomic payload increase. Both enabled and disabled cold constructors verify the
actual guest provider bounds against the selected host policy and the unchanged
producer arena formula. The combined gate passes 24 cases in 21.82 seconds.
These constructor measurements do not yet
measure the scratch or packed bytes used by a completed Desk candidate.

## Desktop qualification

PANE and TASKBAR/TASK/LAUNCHER passed the complete Desk journey on
2026-09-30, in one combined run that also repeated the Grid, STATUS_FIELD,
FIELD and SERIES/WAVEFORM probes. It ran at Akashic `c19c092` with MegaPad
`cb0f27b`. The rich Desktop profile (`desktop-apt1`) selects the shell by
default, with the same 8 MiB work arena and two 4 MiB banks.

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
bounds.

From the Akashic checkout, with the paired MegaPad native extensions built:

```sh
python local_testing/run_headless_grid_acceptance.py \
  --megapad-root /path/to/megapad --output build/shell-qualification \
  --deadline 480 --require-shell
```

`--require-shell` also turns on the STATUS_FIELD, FIELD and SERIES probes.
