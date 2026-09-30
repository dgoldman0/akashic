# Optional Desk shell composition

`tui/desk-apt1.f` can compose the canonical shell snapshot and optional shell
producer alongside its existing final-screen producer. The standard profile
leaves this path disabled. Loading the source does not start a session, and the
disabled path allocates no additional shell XMEM banks.

## Explicit storage selection

Before loading the composition, an experimental product profile supplies:

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

The standard profile keeps shell storage and shell capabilities off while the
full Desk candidate, input, teardown, and memory measurements are qualified.

## Focused qualification

`local_testing/test_rich_shell_composition.py` exercises the full cold KDOS and
Desk source closure on the native simulator with 384 MiB external memory and a
256 MiB general XMEM partition. Its experimental 8 MiB work span and two 4 MiB
candidate banks leave 37,196,432 bytes free after loading and after repeated
setup/uninstall. Compared with the disabled composition, the extra allocation is
16,876,096 bytes, including source banks, descriptors, alignment, and allocator
overhead. Setup and release allocate no additional storage.

The executable lifecycle proof covers successful installation, a foreign draw
observer refusing source installation at shell phase 2, and a real sidecar
constructor followed by an injected installation refusal at phase 4. Both
refusals unwind successfully and permit a later setup; the foreign observer is
preserved. Profile checks reject partial/unaligned bounds and an enabled boot
replayed against the disabled profile. These constructor measurements do not yet
measure the scratch or packed bytes used by a completed Desk candidate.
