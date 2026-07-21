# Resource-owner pool

`akashic/interop/resource-owner-pool.f` is the policy-neutral lifetime core for
semantic resource owners. A concrete owner supplies bounded slot and lease
arrays, its runtime graph, an owner ID, and three callbacks. The callbacks
decide whether a qualified locator is admitted, which component descriptor a
tag selects, and how the new component state is initialized. The pool owns the
repeated mechanics around those decisions:

- one live component and `RREG` publication per admitted RID;
- distinct self-bound RACQ tokens for every acquisition of a shared RID;
- generation, cookie, refcount, inflight, and closing-state validation;
- rollback of component creation, registration, publication, or attachment;
- dispatch-safe final unpublication and destruction; and
- retryable quiescence and release without clearing the caller's token early.

It does not interpret resource content, locators beyond the caller's admission
decision, capability schemas, domain revisions, storage errors, mutability, or
applet behavior. Library and Daybook remain the semantic owners of their
resources.

## Caller-owned layout

The pool allocates no capacity. A caller initializes `ROPOOL-CONFIG-SIZE`
bytes, supplies `ROPOOL-SLOT-SIZE * slot-capacity` and
`ROPOOL-LEASE-SIZE * lease-capacity` disjoint bytes, then calls
`ROPOOL-INIT`. Capacities must be positive and the complete runtime graph must
belong to one live Context. The retained owner-identifier bytes, config,
destination pool, slot array, lease array, Context, component registry, and
resource registry are eight pairwise disjoint spans. Initialization verifies
that entire matrix before clearing any caller byte, so rejected construction
is nonmutating even for hostile aliases.

Every descriptor selected by the caller must reserve
`ROPOOL-MEMBER-SIZE` bytes at the beginning of its component state. The pool
writes the exact pool, slot, generation, and caller tag there before invoking
the state initializer. Concrete state follows that prefix; handlers can recover
the member without a domain-specific global owner lookup. A selected descriptor
must leave its ordinary component state initializer unset: the pool invokes the
owner's contained initializer only after it has installed the member prefix and
can roll the partially created instance back.

```forth
ROPOOL-CONFIG-INIT  ( config -- )
ROPOOL-CONFIG-VALID? ( config -- flag )
ROPOOL-INIT         ( config pool -- racq-status )
ROPOOL-FINI         ( pool -- racq-status )
ROPOOL-VALID?       ( pool -- flag )

ROPOOL-RACQ         ( pool -- racq-root )
ROPOOL-ATTACH
  ( locator pool context rreg binding result -- racq-status )

ROPOOL-HANDLER-BEGIN ( request instance -- member flag )
ROPOOL-HANDLER-END   ( member -- racq-status )

ROFFER-INIT   ( rid pool offer -- racq-status )
ROFFER-VALID? ( offer -- flag )
ROFFER-RID    ( offer -- rid | 0 )
ROFFER-POOL@  ( offer -- pool | 0 )
```

`ROPOOL-VALID?` is an explicit deep diagnostic. It checks the complete slot,
lease, publication, registry, and member graph and therefore is not a request
hot-path operation. Handler begin/end use a guarded bounded member/slot check;
ordinary dispatch does not walk the full resource registry or all pool slots.

Initialization, attachment/release, offer construction, deep validation, and
observation still pass through a small module-level control-plane scratch
trampoline and are serialized across pools. An owner callback must not
recursively enter a `ROPOOL` lifecycle/control-plane API on the same or another
pool. This limitation does not apply to handler begin/end, whose O(1) request
hot path is stack-local and guarded by the exact owning pool. A future need for
concurrent high-rate session lifecycle would require caller-owned operation
workspaces; L6 makes no such throughput claim.

## Per-resource discovery offer

`ROFFER-SIZE` is a neutral descriptor stored by the concrete owner. After the
owner has established an exact RID in a live pool, `ROFFER-INIT` copies that
RID and the pool pointer into the owner's caller-owned offer storage. The
owner's named resource service lends the offer while that owner is active.

There is deliberately no process-wide or Desk-wide “current resource pool.” A
consumer asks for one named resource service, validates its offer, and copies
the exact RID and owning pool into its own session before it retains the
resource. It never keeps the offer pointer. This lets different resource IDs
route to different pools through the same endpoint without a global selector,
pool scan, or applet-specific discovery record. An offer is activation-local
discovery metadata, not authority and not a persistent locator.

## Retains, anchors, and teardown

`ROPOOL-ATTACH` performs the pool-sized alias preflight, acquires through the
embedded RACQ root, and attaches the caller's exact binding. The output result
owns one active token on success. Same-RID acquisitions increment the existing
slot's refcount; a different RID consumes another caller-owned slot. A full
slot or lease array fails explicitly and never evicts or retargets a live
owner. Output spans are also disjoint from every active instance header and
state, its live component descriptor, and that descriptor's reachable
capability table, as well as the retained owner-identifier bytes; attachment
or offer construction cannot overwrite borrowed dispatch or root metadata.

An owner that must publish a RID for its whole activation can retain one
ordinary acquisition and mark its token with `ROPOOL-ANCHOR!`. Only one anchor
is allowed per slot. Releasing that anchor while other references remain
returns `RACQ-S-BUSY` and leaves it retryable; once it is the final reference,
normal RACQ teardown unpublishes and destroys the component.

Final release coordinates with the request bus's recursive dispatch guard.
The slot enters closing state before its inflight count is checked, preventing
new owner handlers from starting. Contention, injected quiescence failure, or
unpublication/destruction failure leaves the exact token and slot recoverable
for retry. `ROPOOL-FINI` succeeds only after every slot and lease is gone.
Failed finalization leaves the live pool guard intact; its storage is cleared
only after successful destruction has released the last guard hold.

Observation words expose live/lease/ref counts and exact slot instances for
owner tests and composition. The deterministic busy and release-failure hooks
exist to prove retry behavior; they do not change owner policy.
