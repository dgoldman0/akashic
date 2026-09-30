# Optional Desk shell composition

`tui/desk-apt1.f` can compose the canonical shell snapshot and optional shell
producer alongside its existing final-screen producer. The standard rich
Desktop profile leaves this path disabled: until per-pane DELTA publication
exists, every changed draw with the shell installed is a complete hidden START
and reveal of the whole retained scene. The explicit `desktop-apt1-shell`
development profile enables it with 8 MiB work storage and two 4 MiB immutable
banks. Loading the source does not start a session, and the disabled path
allocates no additional shell XMEM banks. The complete run evidence is recorded
in [Shell Desktop qualification](SHELL-DESKTOP-QUALIFICATION.md).

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

For a diagnostic or subsequently qualified product selection, use
`desktop_apt1_shell_profile(work_bytes=..., bank_bytes=..., base=...)` from
`local_testing/akashic_tui.py`. It returns a new `RichTerminalProfile` with the
explicit storage, PANES/TASKBARS capabilities and the additive host quotas below.
The helper's default base is the shell-off `DESKTOP_APT1_RICH_TERMINAL` of the
registered rich Desktop. `desktop-apt1-shell` installs its 8 MiB / 4 MiB result.
Calling the helper creates a separate value and does not mutate either profile.
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

The `desktop-apt1-shell` 8 MiB work / 4 MiB per-candidate capacity targets the
280-by-84 qualification surface. It is not a worst-case guarantee for every
400-by-200 host surface or every maximum-size source graph: the global glyph
scratch reservation alone can exceed 8 MiB at that geometry. The host may retain
its 400-by-200 geometry limit because exact optional-candidate admission remains
authoritative. If the selected scratch or immutable bank cannot hold the complete
candidate, the entire optional shell is refused and the unchanged supported
legacy scene, including ordinary CELL coverage, remains available. No partial
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

The standard rich Desktop profile and the constrained-text
`desktop-apt1-small-terminal` check keep the shell off until per-pane DELTA
publication lands and typing cadence is measured
([cleanup plan](RICH-DESK-CLEANUP-PLAN.md), steps 2 and 3); `desktop-apt1-shell`
selects it for that work. The host's `reference` appearance remains the default
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
