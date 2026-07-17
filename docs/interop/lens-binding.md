# Activation-local lens bindings

`akashic/interop/lens-binding.f` binds a semantic RID to one live component
instance inside one Context. The pointer-free structure records activation
epoch, Context and Practice identity, target instance generation, and the
target's positive component revision.

An `LBIND` is activation-local even though its bytes contain no pointer. Its
epoch, Context generation, component generation, and revision have meaning
only while that activation remains live. It must not be used as durable
resource history or embedded in a qualified locator.

`LBIND-ATTACH` resolves an RREF through `RREG` and records the current live
component target. `LBIND-REQUEST!` resets and stamps a request envelope with
that target and component revision. `LBIND-ADVANCE` accepts only a completed
successful request for the same activation, resource, target, and expected
revision, then advances to the bus-reported component revision. These checks
are concurrency guards; they do not qualify a durable domain state.

Resource acquisition owns the separate live retain token. Releasing an
acquisition clears its binding only after the semantic owner accepts release.
QLOC owns the separate durable identity and domain-evidence contract.
