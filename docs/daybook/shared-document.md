# Daybook shared document owner

`akashic/daybook/shared-document.f` is the bounded concrete owner for the
canonical `/daybook.md` text document. Desk hosts it during a healthy Practice
activation, publishes its one RID through `RREG`, and Daybook/Pad lenses attach
with the existing `RREF`/`LBIND` contracts. Hosting is lifecycle composition:
Daybook remains the semantic owner, and neither Desk nor a lens acquires the
document. The owner does not depend on any lens lifecycle.

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

The cooperating Daybook and Pad applets use
[`shared-document-lens.f`](../interop/shared-document-lens.md) for the common
service discovery, exact attachment, and request-envelope lifecycle. Document
parsing, editing policy, snapshot/replace dispatch, binding advancement, and
post-commit handling remain with each applet.

The owner target is always its one exact Daybook RID and expected revision.
Current Daybook date/row, Pad tab/selection, focused Desk tile, and Practice
binding are neither target nor authority.

## Open security boundary

Exact-revision protection currently covers cooperating semantic lenses, not
every VFS writer. The VFS does not reserve `/daybook.md`, so code with ambient
VFS authority, including File Explorer, can mutate it outside the owner's
revision sequence. Whether to enforce ownership at the VFS boundary, through
Practice-scoped authority or mediation, or retain a documented trusted-code
convention remains an explicit design decision. Desk orchestrates the
activation but does not own the Daybook data or policy.

## Public interface

```forth
SDOC-ACTIVATE   ( vfs rid context rreg creg -- instance status )
SDOC-DEACTIVATE ( instance -- status )
SDOC-REF        ( instance destination-rref -- status )
SDOC-VALID?     ( instance -- flag )

SDOC-COMP-DESC   ( -- descriptor-address ) \ CREATE data address
SDOC-CAP-SNAPSHOT ( -- capability )
SDOC-CAP-REPLACE  ( -- capability )
SDOC-CAP-DESCRIBE ( -- capability )
```

Only one owner may be live in the module at a time. `SDOC-ACTIVATE` copies the
RID, uses `/daybook.md` as its canonical VFS backing path, recovers its `VREPL`
transaction namespace,
validates the existing bounded UTF-8 source, registers the component
instance, and publishes the RID. `SDOC-DEACTIVATE` unpublishes before it
removes and frees the instance. Lens bindings are neither accepted nor
retained by either operation. The activation must deactivate the owner before
freeing its Context, resource registry, or component registry.

Synchronous request dispatch is serialized through the request bus's recursive
cross-core dispatch boundary. That boundary spans the handler publication,
output validation, and generic component-revision advance, so two exact-N
replacements cannot both commit before either revision changes. Deactivation
rejects a call made from inside dispatch and otherwise quiesces that boundary
before unpublishing or freeing the owner; post-handler bus work therefore
cannot retain a freed instance.

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
transactional descriptor assembly, but L5 does not reinterpret them as
historical QLOC operations or introduce a resource session.

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

Normal consumers should obtain an exact `RREF`, attach an `LBIND`, stamp a
request with `LBIND-REQUEST!`, select the appropriate capability descriptor,
and dispatch through `CBUS`. After a successful replace, the committing lens
advances with `LBIND-ADVANCE`; another lens remains stale until it refreshes.

The focused contract includes an explicit ordinary-file control on the same
real MP64FS path. Two independent `VREPL` clients both publish successfully and
the second silently replaces the first: staged replacement provides atomic
file publication but no stale-snapshot detection. The shared-owner half then
shows the corresponding exact-revision second write being rejected. This
isolates the useful result to semantic ownership/binding; it does not by itself
prove that the broader Practice model is necessary.
