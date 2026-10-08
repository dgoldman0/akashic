# Completed shell snapshots

`akashic/tui/shell-snapshot.f` copies the ordinary `SHM` used for root shell
paint and hit testing. It is independent of child UIDL contexts and the
`RUHA` document banks. It introduces no terminal IDs, app names, text
recognition, replacement layout, or terminal input action.

| API | Stack |
| --- | --- |
| `SHSN-BANK-BYTES` | `( entry-limit text-bytes -- bytes-or-zero )` |
| `SHSN-INIT` | `( bank-a bytes-a bank-b bytes-b source -- status )` |
| `SHSN-VALID?` | `( source -- flag )` |
| `SHSN-INSTALL` | `( source -- status )` |
| `SHSN-UNINSTALL` | `( source -- status )` |
| `SHSN-SNAPSHOT-FOR@` | `( draw source -- model bytes status )` |
| `SHSN-FROZEN-VALIDATE` | `( model bytes -- status )` |
| `SHSN-RECT-CLEAR?` | `( row col height width draw source -- clear? status )` |
| `SHSN-STORAGE-DISJOINT?` | `( address bytes -- flag )` |
| `SHSN-SOURCE-STORAGE-DISJOINT?` | `( address bytes source -- flag )` |
| `SHSN-LIVE-STORAGE-DISJOINT?` | `( address bytes source -- flag )` |

Statuses are `SHSN-S-OK=0`, `CAPACITY=1`, `UNAVAILABLE=2`, and `INVALID=3`.
A missing, refused, stale, incomplete, modal, or detached draw returns
`0 0 UNAVAILABLE`. An invalid source returns `INVALID`. Each copy is validated
once, when the host callback makes it; `SHSN-SNAPSHOT-FOR@` returns the
published copy without checking it again, because a capture writes only the
bank the published copy does not use.
Capture is an optional observation: every refusal preserves ordinary CELL.

## Storage and immutable copies

The source descriptor is `SHSN-SIZE=160` bytes, aligned to eight bytes.
Nonzero active and staged pointers must name configured banks exactly; their
byte counts must fit those banks. A staged bank must differ from the active
bank. An inactive history may retain its bank pointer with zero used bytes;
positive published bytes require coherent completed-draw metadata. The
caller supplies two separately bounded, aligned banks. Each bank needs
`128 + 168 * reserved-entry-limit + copied-text-bytes` bytes. The reserved
entry extent uses the limit, not the active count. `SHSN-BANK-BYTES` checks
nonnegative 32-bit inputs and result; zero means an invalid or oversized
request. Desk's existing 49,152-byte ordinary model bound can be used for
each copied bank; no additional validation workspace is required.

A host callback copies exactly `SHM.USED` bytes once to the inactive bank,
sets only that copy's `SHM.CAPACITY` to the exact extent, and deeply validates
it. The SHM ABI, entry offsets, source keys, signed slot identities, component
owner/generation, model epoch, text and geometry remain unchanged. The bank
contains offsets, never retained host, slot, catalog, instance or widget
pointers. Unused reserved entries must be zero. All nonempty label, title and
action spans must occupy the text arena exactly in record and field order;
empty spans have offset zero or the current text cursor. No overlap, gap or
trailing bytes is admitted. All text is strict display-safe UTF-8. Unsafe
ordinary display text declines the whole copied model, leaving CELL intact.

The constructor checks full A/B capacities and descriptor disjointness
before any mutation. It rejects module scratch, invalid and wrapping spans,
active screen and UIDL authority, and the current root instance/state when
already present.
Capture additionally protects the root component descriptor, instance and
entire state; host state and live slot records; child component/application
descriptors, instances, state, region parent chains, saved UCTX and UIDL
buffers; active UIDL semantic authority; and all active screen storage.
Slot and parent walks are bounded by caller bank capacity and reject cycles
or a graph too large to prove. BEGIN stores its transaction only in private module state; no caller source
byte is changed until the host graph has been proved disjoint. A failed runtime
proof therefore leaves potentially aliased caller bytes untouched.

The published bank remains immutable until a later root capture selects it
again. A publisher must copy the returned span into its own independently
validated candidate before retaining it across another root draw or retry.
`SHSN-SOURCE-STORAGE-DISJOINT?` protects both full bank capacities, including
the inactive bank, so candidate storage cannot silently alias a future copy.
`SHSN-LIVE-STORAGE-DISJOINT?` additionally protects the ordinary model's full
capacity and its retained host, root and child lifecycle storage, including
component state, descriptors, region parents, saved UCTX and UIDL buffers.
It also checks current screen/UIDL authority. Publishers use this stronger
predicate before constructing or capturing into a writable span; checking
only frozen banks would allow an ordinary model or root-state alias. The
query performs no caller-memory writes, rejects private-scratch aliases
before using scratch, and clears its borrowed query pointers on return.
It is a synchronous UI-owner-core proof, not permission to retain live
pointers or to reuse the result after lifecycle mutation.
No RUHA schema or bank changes are required.

## Completed root authority

The source exclusively owns two ordinary observers while installed:
`AHOST-SHELL-OBSERVE!` and `ASHELL-DRAW-OBSERVE!`. Installation refuses an
existing observer or another source; it never replaces someone else's
callback. Reinstalling the exact already installed source is idempotent.
Reinitialization while any source is installed is refused. Uninstall removes
only callbacks still owned by that source and invalidates its publication.
Call it before freeing the source or either bank. A host must publish null
and notify before freeing its model, state or instance.

`ASHELL-DRAW-BEGIN` precedes every write of an actual root paint. It
invalidates prior publication and records the exact root instance, selected
screen, geometry and previous completed generation. A host callback stages
only during that transaction and only when its `AHOST.CONTEXT` is the same
root instance and agrees with the SHM owner/generation. Multiple host
publications in one transaction are ambiguous and decline the snapshot.

`ASHELL-DRAW-COMPLETE` occurs only after successful root paint, toast, cursor
and `SCR-DRAW-COMPLETE`. It publishes the staged copy only for the same
instance and screen, the immediately completed generation, and the still
current host model. A throwing paint never sends COMPLETE. A dialog sends
`ASHELL-DRAW-MODAL` before its separate completed draw and invalidates both
pending and published shell data. A screen change, resize, later draw without
fresh observation or host-model invalidation makes old snapshots unavailable.
Callback exceptions are caught by ordinary observation and cannot stop CELL
publication. These APIs execute synchronously on the UI owner core.

## Geometry, lifetime and final writers

Validation preserves exact pane outer/content rectangles and ordered,
nonoverlapping one-row task and launcher slots. It requires selected and
minimized task states to be mutually exclusive, at most one selected task,
no task entries under a hidden taskbar, and inert legacy launchers with no
invented catalog action. Display label width must exactly equal its slot.
Identity uniqueness includes kind, key, signed slot/catalog identity and
component owner/generation. An ordinary pane with slot `+2` and an overlay
with slot `-2` may therefore both have display key `2` without aliasing.

Capture additionally resolves each pane/task against its unique live signed
slot and component owner/generation, checks callable state, host focus coherence and exact selected
or minimized flags, and verifies pane content against its live region and
every parent clip. Retired, regionless, partially clipped or mismatched
entries refuse the snapshot. The ordinary builder remains the source of
full-frame omission and modal presentation. The copy neither manufactures omitted panes nor promotes
minimized children to visible panes. Pane content origin and extent never
move; pane chrome is only the existing outer-minus-content area.

A truthful model does not prove that its cells survived later foreground
paint. Before removing CELL ownership, a publisher must query final-writer
provenance for the exact rectangle and completed draw. `SHSN-RECT-CLEAR?`
requires a complete positive onscreen rectangle and combines source draw
validation with `SCR-OCCLUSION-RECT?`; `false OK` requires
fallback for that rectangle. Toast, cursor and overlays stay visible. The
publisher must also validate its family support, quotas, candidate ownership
and input mapping; snapshot validity alone grants no retained paint claim or
host action authority. Task and launcher events must resolve the copied
lifecycle identity through the ordinary host/catalog action path.
