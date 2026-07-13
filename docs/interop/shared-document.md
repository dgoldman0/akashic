# Shared document owner

`interop/shared-document.f` is the bounded first shared-resource witness for
the canonical `/daybook.md` text document. It is a headless component: a
Practice activation creates it, publishes its one RID through `RREG`, and
reusable lenses attach with the existing `RREF`/`LBIND` contracts. The owner
does not depend on any lens lifecycle.

This is intentionally not a general resource graph or a durable Practice
model. The RID-to-instance mapping, current revision, registries, and VFS
handles are activation-local. Code is trusted native code; capabilities are
routing and authority contracts, not a sandbox boundary.

Cooperating applets use
[`shared-document-lens.f`](shared-document-lens.md) for the common service
discovery, exact attachment, and request-envelope lifecycle. Document parsing,
editing policy, snapshot/replace dispatch, binding advancement, and post-commit
handling remain with each applet.

## Open security boundary

Exact-revision protection currently covers cooperating semantic lenses, not
every VFS writer. The VFS does not reserve `/daybook.md`, so code with ambient
VFS authority, including File Explorer, can mutate it outside the owner's
revision sequence. Whether to enforce ownership at the VFS boundary, through
Practice-scoped authority or mediation, or retain a documented trusted-code
convention remains an explicit design decision. Desk orchestrates the
activation but need not be the enforcement layer.

## Public interface

```forth
SDOC-ACTIVATE   ( vfs rid context rreg creg -- instance status )
SDOC-DEACTIVATE ( instance -- status )
SDOC-REF        ( instance destination-rref -- status )
SDOC-VALID?     ( instance -- flag )

SDOC-COMP-DESC   ( -- descriptor-address ) \ CREATE data address
SDOC-CAP-SNAPSHOT ( -- capability )
SDOC-CAP-REPLACE  ( -- capability )
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

An indeterminate publication or unrecoverable transaction state blocks the
owner for the remainder of that activation. Further requests fail instead of
exposing content under a revision which may no longer describe it. A later
activation performs `VREPL` recovery before establishing its fresh
activation-local revision baseline.

Normal consumers should obtain an exact `RREF`, attach an `LBIND`, stamp a
request with `LBIND-REQUEST!`, select one of the two capability descriptors,
and dispatch through `CBUS`. After a successful replace, the committing lens
advances with `LBIND-ADVANCE`; another lens remains stale until it refreshes.

The focused contract includes an explicit ordinary-file control on the same
real MP64FS path. Two independent `VREPL` clients both publish successfully and
the second silently replaces the first: staged replacement provides atomic
file publication but no stale-snapshot detection. The shared-owner half then
shows the corresponding exact-revision second write being rejected. This
isolates the useful result to semantic ownership/binding; it does not by itself
prove that the broader Practice model is necessary.
