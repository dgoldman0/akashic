# Fixed VFS snapshots

`akashic/utils/fs/vfs-fixed-snapshot.f` provides the mechanical part of a
fixed-capacity, crash-recoverable snapshot store over `vfs-replace.f`. It owns
the 64-byte envelope, exact reads, CRC checks, optimistic generation changes,
VREPL recovery, blocked-state latch, and scratch hygiene. Typed owners retain
their paths, payload formats, semantic validation, and public status adapters.

This module is for fixed-size payloads only. Variable-size records, dual-slot
heads, and stores with different recovery semantics are not admitted by this
contract.

## Record format

Every target is exactly `64 + payload-u` bytes:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 8 | caller-supplied magic, compared as exactly eight bytes |
| 8 | 8 | format |
| 16 | 8 | header size, always 64 |
| 24 | 8 | positive generation |
| 32 | 8 | exact payload size |
| 40 | 8 | CRC-32 of the complete payload |
| 48 | 8 | CRC-32 of header bytes 0–47 and 56–63 |
| 56 | 8 | flags, currently zero |
| 64 | fixed | typed payload |

Read validation is ordered: exact target resolution/open, minimum header size,
eight-byte magic, header CRC, supported format, header shape/generation/payload
size, exact total file size, exact payload read, payload CRC, then the typed
validator. A destination is published only after all checks pass.

## Specification lifecycle

```forth
VFSNAP-SPEC-INIT
  ( magic-a magic-u format payload-u encode-xt validate-xt spec -- status )
VFSNAP-SPEC-PRIVATE-ADD  ( private-a private-u spec -- status )
VFSNAP-SPEC-SEAL         ( spec -- status )
```

`magic-u` must be exactly eight. Payload size must be positive and must not
overflow when the envelope is added. Callback execution tokens must be
nonzero. A specification can register up to `VFSNAP-SPEC-PRIVATE-MAX` disjoint
private spans and must be sealed before a store can use it. Registration after
seal returns `VFSNAP-S-BUSY`.

The encode callback has this exact ABI:

```forth
( opaque-context payload-a payload-u next-generation -- status )
```

The core supplies an exact, all-zero payload span and selects the optimistic
next generation. The callback must write only the payload and cannot see or
rewrite the envelope.

The validation callback has this exact ABI:

```forth
( immutable-payload-a payload-u verified-envelope-generation -- status )
```

It owns semantic validity, canonical unused bytes, and any redundant internal
generation comparison. It must not mutate the payload. Callback statuses use
the `VFSNAP-S-*` domain; typed wrappers explicitly translate them to their
public status names.

## Store lifecycle

```forth
VFSNAP-INIT-AT
  ( path-a path-u scratch-a scratch-u vfs spec store -- status )
VFSNAP-FINI     ( store -- status )
VFSNAP-LOAD
  ( payload-destination capacity generation-destination store -- status )
VFSNAP-SAVE     ( encode-context expected-generation store -- status )
VFSNAP-RECOVER  ( store -- status )
VFSNAP-BLOCKED? ( store -- flag )
VFSNAP-PATH$    ( store -- a u )
```

The caller owns `VFSNAP-STORE-SIZE` bytes and an exclusive scratch span of
exactly `VFSNAP-HEADER-SIZE + payload-u` bytes for the complete initialized
lifetime. The store contains VREPL at offset zero, followed by core state and
the caller scratch pointer. This permits typed adapters to place the core at a
legacy VREPL offset without moving their accessor.

`INIT-AT` derives and owns all VREPL paths. `LOAD`, `SAVE`, and `RECOVER` wipe
the complete caller scratch on every terminal status and caught exception.
`FINI` refuses an active store, wipes scratch, clears the core descriptor, and
makes later operations invalid. Typed adapters must clear their own prefix and
per-instance adapter cells after successful `FINI`.

`SAVE` is optimistic. Expected generation zero admits only an absent target;
otherwise it must equal the fully validated current envelope generation. The
core selects `expected + 1`; overflow is `VFSNAP-S-CAPACITY`. Conflict does not
replace the target.

Snapshot paths retain VREPL's namespace rules.  Exact reads first require the
shared parent to resolve to a directory, then inspect the terminal target with
the VFS no-follow policy before opening it.  Only a proven missing terminal
name is `VFSNAP-S-ABSENT`; a terminal symbolic link or other type collision is
blocking recovery state.  Failure to establish the parent is also recovery
state, while a non-absence terminal lookup error or open failure remains I/O.

## Durability boundary

Snapshot publication inherits the selected VFS binding's durability contract.
`VFS-SYNC` dispatches `SYNCFS`; a disk-backed binding owns `SYNCFS`, per-file
`FSYNC`, and lifecycle `UNMOUNT`, and each successful durability path must end
at a successful `VOL-FLUSH`. A write or flush failure remains a failed snapshot
barrier and is normalized or latched by VREPL/VFSNAP as described below.

`VFS-RAM-BINDING` has no persistent medium, so its `SYNCFS`, `FSYNC`, and
`UNMOUNT` operations form a no-op durability boundary. The RAM fixed-snapshot
fixture exercises exact I/O, barrier ordering, recovery, and blocked-state
behavior; it does not model survival across power loss.

## Blocking and recovery

The statuses are:

```text
OK ABSENT CORRUPT UNSUPPORTED INVALID CAPACITY IO RECOVERY BUSY CONFLICT
```

Corrupt, unsupported, I/O, and uncertain recovery results latch the descriptor
blocked. Later loads and saves return the latched status and do not manufacture
an empty payload or replace evidence. A fresh lifecycle is required. VREPL
rollback and committed-cleanup results normalize to success; marker corruption
and uncertain publication normalize to recovery failure.

Open descriptors and the process VFS selector are restored exactly once on
normal, status-failure, and caught-exception paths. Actual VREPL/VFS activity
retains the process-wide serialization already required by those libraries.
Distinct store instances nevertheless own disjoint paths, lifecycle state, and
scratch. Recursive entry while any callback is active returns `VFSNAP-S-BUSY`
before callback-visible scratch is touched.

## Hostile-alias contract

All public mutating operations perform overflow-safe, half-open span checks
before acquiring a guard or writing module state. Store memory, scratch, path
input, load destination, generation destination, specification memory, core
and dependency private state, and every caller-registered private span must be
disjoint where the operation requires it. Exact adjacency is allowed. Alias
rejection is nonmutating, including when a rejected caller span surrounds
scratch or guard state.

Typed adapters remain responsible for spans the generic ABI cannot describe,
notably the complete typed descriptor and the fixed extent behind an opaque
encode context.
