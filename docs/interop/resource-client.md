# Typed common-resource client

`akashic/interop/resource-client.f` is an activation-local client over one
successful acquisition and LBIND. It requires canonical describe and snapshot
capabilities and treats replace as optional. Capability IDs are insufficient:
kind, effects, and the exact canonical RCON input/output schema objects must
all match, so a legacy capability under the same name is not misclassified as
portable. It copies the binding but borrows the acquisition result, Context,
bus, owner instance, and capability descriptors for that activation.

Descriptor discovery is routing metadata, not authority. Every operation is
stamped from the LBIND and dispatched through `CBUS`, so ordinary policy,
approval, authority, target-generation, input-schema, and output-schema checks
still run at the owner boundary.

The convenience calls perform prepare and dispatch in one operation. The
split `*-PREPARE` and `*-DISPATCH` words support consequential/Agent callers:
prepare builds and stamps the exact typed request, the caller may bind a
reviewed invocation/mandate, and dispatch still submits through CBUS.
Discovery never manufactures or caches a grant.

Describe validates the closed result, RID, and semantic-owner ID. Snapshot
requires an exact QLOC for the acquired RID and verifies its evidence against
the returned content and independent content digest. Replace refuses a client
without the optional capability, copies the submitted content digest before
dispatch, validates the new domain result against it, and advances only the
client's live component binding from the bus completion.

`RCLI-FINI` releases through `RACQ-DETACH`. On cleanup failure it leaves the
client and original token valid for retry; it clears the client only after the
owner release succeeds.
