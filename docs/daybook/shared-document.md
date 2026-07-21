# Daybook shared document owner

`akashic/daybook/shared-document.f` is the bounded concrete owner for the
canonical `/daybook.md` text document. Desk hosts it during a healthy Practice
activation and exposes its owner-lent resource offer to Daybook and Pad
sessions. The offer carries that exact RID and its neutral resource-owner pool;
Desk does not publish a separate global pool service. Hosting is lifecycle
composition: Daybook remains the semantic owner, and Desk does not acquire
document policy or content authority.

Gate 2C relocated the unchanged concrete policy into the Daybook domain. It
preserved the path, bytes, RID, `SDOC-*` public words, descriptor/capability
schemas, and lifecycle and left no compatibility loader in the domain-neutral
interop package. This module is not permission to reuse Daybook policy for
Library, Streams, or a generic text owner.

This is intentionally not a general resource graph, Library projection, or
durable Practice model. The RID-to-instance mapping, current component
revision, registries, `LBIND`s, and VFS handles are activation-local. The
current positive revision is an exact cooperating-client guard, not a
qualified persistent historical-domain locator. `resource.describe` therefore
reports `domain_revision=0` even when the live component revision is positive.
Code is trusted native code;
capabilities are routing and authority contracts, not a sandbox boundary.

The owner delegates component publication, leases, generation/refcount
validation, inflight quiescence, and retryable release to the neutral
[`resource-owner-pool.f`](../interop/resource-owner-pool.md). The cooperating
Daybook and Pad applets use
[`resource-session.f`](../interop/resource-session.md) for retained discovery,
exact attachment, candidate binding, and request-envelope lifecycle. Document
parsing, editing policy, request arguments/results, and post-commit UI handling
remain with each applet.

The owner target is always its one exact Daybook RID and expected revision.
Current Daybook date/row, Pad tab/selection, focused Desk tile, and Practice
binding are neither target nor authority.

## Open security boundary

Exact-revision protection currently covers cooperating semantic consumers, not
every VFS writer. The VFS does not reserve `/daybook.md`, so code with ambient
VFS authority, including File Explorer, can mutate it outside the owner's
revision sequence. Whether to enforce ownership at the VFS boundary, through
Practice-scoped authority or mediation, or retain a documented trusted-code
convention remains an explicit design decision. Desk orchestrates the
activation but does not own the Daybook data or policy.

## Public interface

```forth
SDOC-ACTIVATE   ( vfs rid context rreg creg -- instance status )
SDOC-ACTIVATION-CLEANUP ( context rreg creg -- status )
SDOC-DEACTIVATE ( instance -- status )
SDOC-REF        ( instance destination-rref -- status )
SDOC-VALID?     ( instance -- flag )
SDOC-SERVICE    ( -- offer | 0 )
SDOC-POOL       ( -- resource-owner-pool | 0 )

SDOC-COMP-DESC   ( -- descriptor-address ) \ CREATE data address
SDOC-CAP-SNAPSHOT ( -- capability )
SDOC-CAP-REPLACE  ( -- capability )
SDOC-CAP-DESCRIBE ( -- capability )
```

Only one owner may be live in the module at a time. `SDOC-ACTIVATE` configures
a one-slot caller-owned pool, acquires an identity locator as the owner's
anchor, copies the RID, uses `/daybook.md` as its canonical VFS backing path,
recovers its `VREPL` transaction namespace, validates the existing bounded
UTF-8 source, publishes the pool-created component, and initializes its
caller-owned `ROFFER`. `SDOC-SERVICE` lends that offer as the public named-
service seam. Sessions validate it, copy its RID and pool, and do not retain
the offer pointer. `SDOC-POOL` remains available for direct owner composition
and diagnostics; Desk does not expose it as an independent service. Neither
word exposes VFS state.

If activation fails after the pool has acquired its anchor, a retryable
release fault can leave that unpublished pool holding the exact borrowed
Context and registries. `SDOC-ACTIVATION-CLEANUP` is the dependency owner's
bounded rollback seam: it acts only when those three addresses exactly match
the unpublished pool. Desk retries that cleanup before freeing any of them.
It neither deactivates a live owner nor reaches a pool belonging to a different
activation.

Every active Daybook or Pad session holds another pool lease. Consequently
`SDOC-DEACTIVATE` returns busy while any session remains, leaving the anchor
and owner intact for retry. Once the anchor is the final reference, release
quiesces dispatch, unpublishes, removes, and frees the component before the
pool is finalized. The activation must close child sessions before freeing its
Context, resource registry, or component registry.

Synchronous request dispatch is serialized through the request bus's recursive
cross-core dispatch boundary. The pool adds a guarded constant-time member/
slot check and inflight pin around each concrete handler; it does not perform a
whole-registry validation per request. The bus boundary spans handler
publication, output validation, and generic component-revision advance, so two
exact-N replacements cannot both commit before either revision changes.
Closing prevents new handler entry and waits for inflight work before the
component can be unpublished or freed.

`resource.snapshot` accepts a null argument and returns an owned string copy
of the current document. An expected revision of zero means “current”; a
positive expected revision must match.

`resource.describe` accepts null and returns the portable closed common-
resource description. It identifies the Daybook RID, owner, kind, media type,
current size, and mutability without exposing `/daybook.md`. Its semantic RREF
revision and `domain_revision` are both zero. This is an explicit identity-
only description: the owner has durable bytes but no retained domain-history
ledger and refuses to mint weaker “current” evidence as an exact locator.

The description result and its canonical descriptor use the neutral
resource-contract constructors. Daybook's snapshot and replace capabilities
deliberately remain the compact activation-revision protocol described here:
null to string and string to bool. They use the neutral capability builder for
transactional descriptor assembly, and the protocol-neutral resource session
uses them without reinterpreting them as historical QLOC operations.

`resource.replace` accepts a UTF-8 string of at most `SDOC-MAX-BYTES` (32768)
and requires a positive `CBR.EXPECT-REV`. Publication goes through
`VREPL-REPLACE`; no public direct-write entry point exists. The handler
rechecks the expected revision under the owner's commit guard. A mismatch
returns `CBUS-S-STALE-REVISION` before VFS mutation. On success the handler
does not touch the instance; `CBUS-DISPATCH` performs its existing single
revision advance and records the new value in `CBR.ACTUAL-REV`.

The owner also checks its stored Practice Context immediately before the
replace contract. If the activation is read-only, replacement returns
`CBUS-S-DENIED` without invoking `VREPL`, changing the file, or advancing the
owner revision. This is enforced by the owner rather than left to lens UI.

An indeterminate publication or unrecoverable transaction state blocks
state-bearing snapshot/replace work for the remainder of that activation.
Identity description remains unqualified and reports the resource as not
mutable. A later
activation performs `VREPL` recovery before establishing its fresh
activation-local revision baseline.

Normal applet consumers initialize an `RSES` through their endpoint, select the
appropriate concrete capability descriptor, prepare and dispatch through
`CBUS`, and explicitly advance or refresh. The retained token keeps the exact
owner alive throughout that session. After a successful replace, another
session remains stale until it refreshes.

The focused contract includes an explicit ordinary-file control on the same
real MP64FS path. Two independent `VREPL` clients both publish successfully and
the second silently replaces the first: staged replacement provides atomic
file publication but no stale-snapshot detection. The shared-owner half then
shows the corresponding exact-revision second write being rejected. This
isolates the useful result to semantic ownership/binding; it does not by itself
prove that the broader Practice model is necessary.
