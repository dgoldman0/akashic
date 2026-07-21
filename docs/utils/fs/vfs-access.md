# Scoped VFS access

`vfs-access.f` provides caller-owned file-descriptor scopes and bounded byte
reads over the generic VFS. It centralizes selector, CWD, descriptor, range,
and cleanup mechanics without owning a file format or a persistence policy.

```forth
REQUIRE utils/fs/vfs-access.f
```

The module provides `akashic-vfs-access`. It depends only on the generic VFS
contract. It does not derive companion paths, stage a replacement, synchronize
a commit, validate records, compare generations, or choose recovery authority.
Those decisions remain with the caller or with a higher storage protocol.

## Caller-owned scope

Allocate one `VFA-SCOPE-SIZE` region for each independently live access:

```forth
CREATE source-scope VFA-SCOPE-SIZE ALLOT

my-vfs source-scope VFA-SCOPE-INIT THROW
S" notes.txt" VFS-FF-READ source-scope VFA-SCOPE-OPEN? THROW
DROP
source-scope VFA-SCOPE-CLOSE? THROW
```

The scope API is:

```forth
VFA-SCOPE-INIT       ( vfs scope -- ior )
VFA-SCOPE-VALID?     ( scope -- flag )
VFA-SCOPE-VFS@       ( scope -- vfs )
VFA-SCOPE-FD@        ( scope -- fd|0 )
VFA-SCOPE-PRIMARY@   ( scope -- primary )
VFA-SCOPE-CLEANUP@   ( scope -- cleanup )
VFA-SCOPE-OPEN?      ( path-a path-u flags scope -- fd ior )
VFA-SCOPE-CLOSE?     ( scope -- ior )
VFA-SCOPE-CALL       ( body-xt scope -- primary cleanup )
```

`VFA-SCOPE-OPEN?` accepts the checked VFS open flags and refuses a second open
with `VFS-E-BUSY`. It snapshots the previously selected VFS and the target
VFS's CWD, selects the target, and opens the path. Relative paths therefore
resolve under the target's entry CWD. Failed open restores the context before
returning and remains available through `VFA-SCOPE-PRIMARY@`. An unmounted,
stale, null-CWD, foreign-CWD, or non-directory-CWD target is rejected before
the scope dereferences or pins that CWD.

`VFA-SCOPE-CLOSE?` retires descriptor ownership before attempting cleanup. It
attempts the owned close once, restores the target CWD, and restores the prior
VFS selector. A close or restore that fails after taking effect is not retried.
Calling close again is safe and performs no second release. Nested scopes must
unwind in LIFO order because each scope restores the selector it observed at
entry; explicit-FD reads from independently live scopes may otherwise be
interleaved.

The saved CWD is pinned against cache eviction until restoration. It remains a
borrowed namespace object: a scoped body must not unlink, replace, or otherwise
invalidate the saved or active CWD. Namespace transactions that need that
freedom require a separate checked dentry-lifetime contract; this byte-access
scope does not pretend to provide one.

`VFA-SCOPE-CALL` executes a stack-balanced body whose stack effect is `( -- )`,
catches its exact exception code, and always runs scope cleanup. Its two return
cells deliberately keep primary failure and cleanup uncertainty separate. The
same values remain available through `VFA-SCOPE-PRIMARY@` and
`VFA-SCOPE-CLEANUP@`. A caller must not reinterpret cleanup failure as proof
that durable publication did or did not occur. If a body explicitly closes
and reopens its scope, the first cleanup uncertainty is retained across the
later descriptor; each descriptor remains an exact-once obligation.

Two narrow dependency-injection setters support deterministic qualification
and mediated environments:

```forth
VFA-SCOPE-CLOSE-XT!  ( close-xt scope -- ior )  \ close-xt: ( fd -- ior )
VFA-SCOPE-USE-XT!    ( use-xt scope -- ior )    \ use-xt:   ( vfs -- )
```

The default XTs are `VFS-CLOSE?` and `VFS-USE`. Installed XTs may `THROW`;
the scope catches the exact code and still observes the same exact-once
ownership rule. Setters are configuration, not per-operation callbacks, and
are refused while the scope has a live context or owned FD. An injected close
XT assumes the same ownership contract as `VFS-CLOSE?`: it must retire or
delegate the supplied FD before returning or throwing. The scope clears its
own ownership before that after-effect boundary and never retries it.

## Bounded reads

All byte helpers use an explicit FD and checked VFS results:

```forth
VFA-FILE-SIZE?       ( fd -- size ior )
VFA-READ-FILE?       ( buffer capacity fd -- length ior )
VFA-READ-RANGE?      ( buffer length offset fd -- ior )
VFA-READ-PREFIX?     ( buffer capacity fd -- length total truncated? ior )
```

`VFA-FILE-SIZE?` validates that the FD is current, readable, and not a
directory, including for zero-length access. It accepts only a file size
representable by a nonnegative signed cell. Larger or malformed sizes return
`VFS-E-OVERFLOW`.

`VFA-READ-FILE?` is the complete bounded form. It preflights the total size;
when the file is larger than `capacity`, it returns `0 VFS-E-OVERFLOW` without
reading, advancing the FD, or changing the destination. On success it reads
the complete file from absolute offset zero and returns its exact length.

`VFA-READ-RANGE?` reads exactly the half-open file range
`[offset, offset + length)`. Zero length is valid through `offset = file-size`,
including exactly at EOF. A start past EOF, a nonempty range at EOF, an end
past EOF, a negative argument, or unsigned addition wrap returns
`VFS-E-OVERFLOW` before seek or read. A successful call leaves the FD at the
end of the requested range. If backend I/O fails after progress, the returned
error is authoritative and the caller must not interpret destination bytes as
a complete value.

`VFA-READ-PREFIX?` reads at most `capacity` bytes from absolute offset zero.
It returns both copied `length` and preflighted `total`; `truncated?` is true
exactly when `total > capacity`. Prefix truncation is a successful result, not
an implicit claim that the bytes form a complete document or record. A failed
read returns zero copied bytes while retaining the preflighted total and
truncation result; destination bytes are not accepted after a nonzero `ior`.

Nonempty destination spans require a nonzero, nonwrapping address range.
Zero-capacity and zero-length calls do not dereference their buffer address.

## Callback streaming

A stream uses caller-owned state and scratch space:

```forth
CREATE read-stream VFA-STREAM-SIZE ALLOT
CREATE chunk 4096 ALLOT

fd 0 requested-bytes chunk 4096 ['] consume-chunk context read-stream
    VFA-STREAM-INIT THROW
read-stream VFA-STREAM-RUN  ( delivered stopped? ior )
```

The public stream API is:

```forth
VFA-STREAM-CONTINUE
VFA-STREAM-STOP
VFA-STREAM-SIZE
VFA-STREAM-INIT       ( fd offset length scratch-a scratch-u
                        callback-xt context stream -- ior )
VFA-STREAM-RUN        ( stream -- delivered stopped? ior )
VFA-STREAM-DATA@      ( stream -- chunk-a chunk-u )
VFA-STREAM-OFFSET@    ( stream -- absolute-offset )
VFA-STREAM-CONTEXT@   ( stream -- context )
```

`VFA-STREAM-INIT` may reset a completed descriptor, but refuses an active
descriptor with `VFS-E-BUSY`. A callback therefore cannot replace the range or
callback state of the `VFA-STREAM-RUN` invocation that is delivering it.

The callback has stack effect:

```forth
( stream -- action ior )
```

During the callback, `VFA-STREAM-DATA@` is a borrowed view into the caller's
scratch buffer. Its lifetime ends when the callback returns. OFFSET is the
absolute file offset of that chunk, not a stream-relative counter, and CONTEXT
is the exact caller cell supplied at initialization.

`VFA-STREAM-CONTINUE 0` accepts the current chunk and requests another.
`VFA-STREAM-STOP 0` accepts the current chunk and returns success with
`stopped?` true. The accepted current chunk is included in `delivered`.
Nonzero callback results, invalid actions, callback exceptions, zero-progress
backend reads, and backend I/O failures stop the stream. `delivered` retains
only the bytes accepted by completed callbacks before the failure. The stream
does not retain or interpret chunk contents.

Stream geometry follows the same exact range rules as `VFA-READ-RANGE?` and is
validated before the first callback. A zero-length range at EOF succeeds with
zero callbacks. Scratch capacity must be positive for a nonempty stream.

## Boundary with storage policy

This module owns only resource mechanics and bytes:

- one caller-owned VFS/CWD/FD cleanup scope;
- exact, complete, prefix, and streamed access;
- byte counts, truncation, primary error, and cleanup error.

It intentionally has no generation, active-slot, candidate, committed,
checksum, record, publication, recovery, staging, backup, or marker concept.
`vfs-replace.f`, fixed snapshots, and domain owners may use these mechanics,
but their commit order, size limits, formats, synchronization, and recovery
authority remain above this layer.

## Qualification

The focused emulator profile uses two cloned RAM VFS bindings and exercises
range edges, complete-read nonmutation, prefix truncation, stream offsets and
faults, nested/interleaved scopes, CWD and selector restoration, after-effect
cleanup faults, separate primary/cleanup results, BUSY re-entry, idempotent
close, invalid target rejection, active-CWD eviction refusal, cleanup retention
across reopen, and FD-pool leak checks:

```bash
python3 local_testing/akashic_tui.py smoke --profile vfs-access-contracts
```

The generic backend suites remain complementary:

```bash
python3 -m pytest -q local_testing/test_vfs.py local_testing/test_vfs_mp64fs.py
```
