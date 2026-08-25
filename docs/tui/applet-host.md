# Caller-owned applet host

`akashic/tui/applet-host/host.f` contains the reusable mechanics for hosting
multiple `APP-DESC` children inside one TUI application. It is not a desktop,
window manager, catalog, or product service container.

The caller embeds one `AHOST-SIZE` state block and supplies:

- the live component registry and endpoint assigned to new child instances;
- a relayout callback;
- an owner-resource release callback; and
- a closed-slot projection callback.

An optional `AHOST-UIDL-READY!` callback plus opaque composition context may
attach generic services after UIDL load and initial region assignment, before
application init. A zero callback is the baseline configuration; the host
does not know the service or context type.

Those callbacks carry the caller context stored by `AHOST-CONTEXT!`. The host
imports no applet and knows no service ID, catalog entry, package format,
hotbar, theme, or concrete layout policy.

The descriptor, registry, endpoint, callback execution tokens, and callback
context are borrowed and must outlive every hosted child. The host owns each
created component instance, slot, UIDL context, and retained UIDL file buffer
until rollback or close releases it. The relayout callback owns initial region
allocation and subsequent bounds updates. A linked child keeps the same region
descriptor identity for its lifetime, allowing the optional composition hook
to borrow that exact handle; the host frees it only after final detach.

The relayout callback is required before launch. A missing callback, or one
that returns without assigning a region to the new slot, is rejected with
`AHOST-LAUNCH-E-RELAYOUT` and fully rolled back before inline or file-backed
UIDL can load. The other callbacks may be zero when their facilities are not
present.

Host state is caller-owned, but operations are not reentrant. The module uses
shared operation frames internally, matching the single-threaded callback
model of the current TUI runtime; callers must not enter another host operation
from a host callback or interleave one across a yield.

## Owned mechanics

The host owns linked 104-byte `AHS-SIZE` child slots and their descriptor
instance, stable region handle, display state, monotonic host ID, UIDL context,
retained file buffer, dirty/revision state, close phase, and persistent
application-init boundary. It provides:

- transactional `AHOST-TRY-LAUNCH` with first-error-preserving rollback;
- fail-closed per-child and all-child close negotiation;
- source-safe, fail-closed finalization and retryable ordered host draining;
- focus, minimize, restore, list lookup and counts; and
- child mouse/key routing, ticking, dirty/revision tracking and painting.

Fault containment applies to transactional launch rollback, close negotiation,
ordered finalization, and draining. Event, tick, and paint callback throws
still propagate to the outer shell exactly as they did in Desk; this module is
not a per-child exception sandbox.

Normal launch does not install an app descriptor into a product catalog or
type policy. Desk performs `DESK-INSTALL` before calling the host and updates
its catalog only after a successful host launch. Likewise, the host invokes
Desk's injected callbacks during cleanup without importing Desk.

## Principal API

| Word | Stack | Purpose |
| --- | --- | --- |
| `AHOST-INIT` | `( host -- )` | Clear caller-owned state and start IDs at one |
| `AHOST-REGISTRY!` | `( registry host -- )` | Set the live-instance registry |
| `AHOST-ENDPOINT!` | `( endpoint host -- )` | Set the endpoint assigned to children |
| `AHOST-CONTEXT!` | `( context host -- )` | Set callback context |
| `AHOST-RELAYOUT!` | `( xt host -- )` | Set `( context -- )` relayout callback |
| `AHOST-RELEASE!` | `( xt host -- )` | Set `( instance context -- ior )` owner-release callback |
| `AHOST-CLOSED!` | `( xt host -- )` | Set `( slot-id context -- )` projection callback |
| `AHOST-UIDL-READY!` | `( xt context host -- )` | Set the neutral post-UIDL, pre-app-init composition hook |
| `AHOST-TRY-LAUNCH` | `( desc host -- id ior )` | Launch one already-installed descriptor transactionally |
| `AHOST-REQUEST-CLOSE-ID` | `( id reason host -- decision )` | Negotiate and, on ALLOW, finalize one child |
| `AHOST-REQUEST-CLOSE-ALL` | `( reason host -- decision )` | Negotiate every child without partial teardown |
| `AHOST-QUIESCE-ALL` | `( host -- ior )` | Quiesce each child's retained UIDL and descriptor barriers |
| `AHOST-DRAIN` | `( host -- ior )` | Retire children in order, stopping when no safe progress is possible |
| `AHOST-FOCUS-ID` | `( id host -- )` | Focus or restore one child |
| `AHOST-MINIMIZE-ID` | `( id host -- )` | Minimize one child and select another visible child |
| `AHOST-RESTORE` | `( host -- )` | Restore the last minimized child |
| `AHOST-DISPATCH-KEY` | `( event host -- handled? )` | Route a key to the focused child |
| `AHOST-DISPATCH-MOUSE` | `( event host -- handled? )` | Hit-test and route a child mouse event; focused child wins overlapping regions |
| `AHOST-TICK` | `( host -- )` | Tick eligible live children |
| `AHOST-PAINT` | `( paint-all fullframe host -- )` | Paint eligible visible children |

`AHS.*` words expose slot fields needed by a concrete layout/chrome owner.
They do not transfer ownership. Host lifecycle operations remain owner-core
work because app callbacks can throw, yield, or request close.

Each slot advances independently through `LIVE`, `QUIESCING`, `QUIESCED`,
`SHUTDOWN-CLAIMED`, and `DETACHED`. Quiesce first makes the slot noncallable,
then crosses its retained UIDL barrier and optional `APP.QUIESCE-XT` in that
order. `QUIESCED` is published only after the final UCTX save also succeeds.
Refusal leaves the complete linked slot and exact borrowed graph intact.
Shutdown is claimed before arbitrary application code and is never repeated;
final UIDL/driver detach must succeed before unlink, notification, or any
owned-resource release.

Ordinary layouts keep child regions disjoint. A concrete owner may overlap
them for presentation, as Desk does in full-frame mode. In that case pointer
hit-testing tries the focused visible child first, matching key routing and
paint ownership; otherwise list order determines the first containing slot.
