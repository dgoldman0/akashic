# Refactor Landing L3 scoped and bounded VFS access

Landing L3 extracts the repeated VFS selector, CWD, descriptor, bounded-read,
and cleanup protocol into one independent Akashic filesystem utility. It
changes no applet product behavior, storage format, commit order, or recovery
authority.

## Neutral access layer

`utils/fs/vfs-access.f` contains two caller-owned descriptors and no lexical
mutable state:

- one `VFA-SCOPE-SIZE` object borrows a target VFS, owns at most one FD, saves
  the target CWD and prior selector, and retains primary failure separately
  from cleanup uncertainty;
- one `VFA-STREAM-SIZE` object borrows an FD and caller scratch, exposes each
  chunk and absolute offset to a callback, and retains only accepted progress.

The scope uses checked `VFS-OPEN?` and `VFS-CLOSE?`. Multiple simultaneous
files compose multiple one-FD scopes; L3 does not invent a fixed FD array or
generic close-order policy. Nested ambient scopes unwind in LIFO order, while
explicit-FD reads from independent scopes can interleave.

The scope's saved CWD is a borrowed dentry under the serialized VFS
transaction and is pinned against cache eviction until restoration. A body may
read bytes and temporarily change CWD, but it may not unlink, replace, or
otherwise invalidate the saved or active CWD. None of the proving consumers
performs namespace mutation. A more general namespace transaction would
require a checked dentry hold rather than another saved pointer, so that
unrelated namespace work is not pulled into this landing.

## Distinct read policies

The public byte APIs keep four meanings separate:

| API | Contract |
| --- | --- |
| `VFA-FILE-SIZE?` | Accept only a nonnegative one-cell logical size |
| `VFA-READ-FILE?` | Preflight the complete file against caller capacity; oversize performs no read or destination mutation |
| `VFA-READ-RANGE?` | Read an exact non-wrapping half-open range at an explicit offset |
| `VFA-READ-PREFIX?` | Read a bounded prefix and report copied length, total length, and truncation explicitly |
| `VFA-STREAM-RUN` | Deliver an exact range through caller scratch with absolute offsets and explicit continue/stop |

Zero-length ranges are valid through exact EOF. Starts past EOF, nonempty EOF
ranges, ends past EOF, negative geometry, and addition wrap fail before seek or
read. Stream callbacks acknowledge a chunk with `CONTINUE` or `STOP`; a
successful stop includes the current chunk in delivered progress. Callback
exceptions, invalid actions, short/zero progress, and backend failures retain
only earlier acknowledged progress.

The utility contains no UTF-8 rule, parser, domain status, path derivation,
allocation, replacement, synchronization, generation, checksum, record,
publication, or recovery concept.

## Core descriptor hardening

The scope's no-leak guarantee exposed two generic VFS invariant gaps. A binding
`OPEN` callback could throw after the core allocated a provisional FD, and a
binding `RELEASE` callback could throw before the core retired an existing FD.

`VFS-OPEN?` now catches the exact callback exception and returns the
provisional FD to its pool before reporting it. `VFS-CLOSE?` catches the exact
release exception, retires the open reference and FD once, and reports the
exception afterward. A release exception remains cleanup uncertainty and is
never permission to retry the same FD.

## Proving consumers and deleted duplicates

Three small, already-qualified paths prove materially different policies:

- Grid embeds a scope in component state and uses the complete bounded read
  for `/grid.csv`. Missing, oversize, I/O, parser, dirty, and source-blocked
  distinctions remain applet-owned.
- Daybook embeds the same mechanism for direct `/daybook.md` loads. Its
  Markdown authority, shared-document lens, model, dirty, and recovery rules
  remain unchanged.
- FExplorer converts only the Agent-visible preview capability to an explicit
  prefix read. Its 4 KiB limit, three-byte UTF-8 lookahead, malformed-input
  refusal, and codepoint backoff remain in the applet.

Grid and Daybook delete their private old-selector, have-selector, FD,
cleanup-FD, cleanup-failure, close/use vector, thunk, and nested transaction
machinery. FExplorer deletes the equivalent preview FD and primary/cleanup
scratch. The replacement is executable shared machinery rather than applet
code moved to another folder.

## Functional-preservation scope

The production changes touch these L1 behavior groups:

- `grid.formulas-csv-and-actions`;
- `daybook.model-actions-and-markdown`;
- `fexplorer.views-and-file-actions` and
  `fexplorer.resource-capabilities` for capability preview only.

No conditional prerequisite fires. L3 changes no Grid input/capability
routing, Daybook controller or canonical resource session, or FExplorer
create/rename/delete handler. The FExplorer small-mutation prerequisite is
therefore not selected.

App-builder streaming remains unnecessary after the direct neutral stream
contract proved callback behavior. Pad's ambiguous config clipping is not
silently reinterpreted. FExplorer transfer retains its two-FD rollback and
residue policy. Streams, SoundLab, Agent generation storage, Library durable
paths, Game, and Worlds are untouched.

## Qualification

The focused `vfs-access-contracts` profile uses two independent RAM VFS
instances. It covers range geometry, bounded nonmutation, prefix truncation,
stream offsets/stop/faults, CWD and selector restoration, nested and
interleaved scopes, BUSY re-entry, idempotent cleanup, exact primary and
cleanup cells, after-effect close/restore failures, core OPEN/RELEASE callback
exceptions, failed-prefix zero acceptance, active-stream reinitialization
refusal, invalid/unmounted target CWD rejection, active-CWD eviction refusal,
foreign-CWD ownership rejection, cleanup retention across reopen and reset
between direct operations, and FD-pool/open-count restoration.

The affected applet preservation profiles, generic VFS backend suites, linked
Desk evidence, host refactor ratchets, and packaging/baseline suite form the
landing gate. The final emulator evidence is:

| Command profile | Result |
| --- | --- |
| `vfs-access-contracts` | 341 assertions; 192,908,118 steps |
| `grid-contracts` | 149 assertions; 1,475,745,607 steps |
| `daybook-contracts` | 118 assertions; 1,562,261,071 steps |
| `fexplorer` | PASS; 2,412,175,768 steps |
| `desktop` with the supported default ceiling | PASS; ready at 8,410,000,000 steps |

The Desktop ceiling is qualification headroom, not a product capacity or
scalability parameter. The combined host gate passed 205 tests:

```bash
python3 -m pytest -q \
  local_testing/test_vfs.py \
  local_testing/test_vfs_mp64fs.py \
  local_testing/test_refactor_inventory.py \
  local_testing/test_refactor_functional_baseline.py \
  local_testing/test_akashic_tui_packaging.py \
  local_testing/test_desk_gate0_baseline.py
python3 local_testing/refactor_inventory.py --check
python3 local_testing/refactor_functional_baseline.py --check
```

The broad `agent-applet-capabilities` aggregate was not counted as landing
evidence. An isolated checkout of pre-L3 commit `a150a50` reproduced its
existing return-stack failure after all 60 assertions completed with zero
failures; L3 does not absorb that unrelated fixture repair. Focused FExplorer
and linked Desktop evidence cover the changed preview path.

No ext4 profile is required; every changed consumer targets the generic VFS
contract and existing RAM/MP64FS evidence.

## Architecture ratchet

The reviewed L3 graph has 382 production modules, 1,290 resolved `REQUIRE`
occurrences, and 1,289 unique resolved edges. The new neutral module and its
four downward/resolved edges account for the change.

Applet lexical globals fall from 2,763 to 2,746 as private cleanup scratch is
deleted. The independent total rises from 7,065 to 7,066 solely for the VFS
callback result cell required to retire descriptors after callback exceptions;
`vfs-access.f` itself adds no lexical mutable state. Desk-ecosystem globals,
placement debt, layer violations, unresolved imports, cycles, identity debt,
addressability debt, and their placement/unresolved digests are unchanged.
