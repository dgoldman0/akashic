# Shared document lens

`akashic/interop/shared-document-lens.f` is the reusable client side of the
bounded semantic text-document contract. It owns no document model and knows
nothing about `/daybook.md`. A consuming applet embeds `SDLENS-SIZE` bytes in
its instance state and supplies the semantic resource service name at
initialization.

Its landed evidence is narrower than its location suggests: it currently has
one concrete owner/product witness, the Desk-hosted Daybook owner, and two
Daybook-specific consumers (Daybook and Pad). It is not yet proof of a generic
Library/Streams text-resource abstraction. The Gate 2C audit found no Daybook
path, service label, RID, `SDOC-*` identifier, owner import, or owner policy in
this implementation: the caller supplies the semantic service ID, and the lens
discovers only the portable Context, registry, bus, exact binding, and canonical
snapshot/replace descriptors. It therefore remains in `interop/` unchanged.
Gate 6A may extract or revise mechanics only after the real Library owner
provides an independent comparison.

The lens centralizes the plumbing shared by Daybook and Pad:

- endpoint-aware service discovery for Context, RREG, and CBUS;
- fail-closed validation of their Practice relationships;
- semantic RID discovery and bounded current-reference attachment;
- exact `RREF`/`LBIND` retention;
- owner and snapshot/replace capability discovery;
- one reusable request envelope.

It deliberately does not own parsing, serialization, editor buffers, dirty or
stale UI state, replace approval, `LBIND-ADVANCE`, or post-commit recovery.
Those policies differ between Daybook and Pad and remain applet-local.

The lens is activation-local plumbing, not identity or authority. Its `LBIND`,
borrowed pointers, and request envelope are never durable. A caller targets
the exact semantic RID/reference and expected revision supplied by the owner;
the selected Daybook row, active Pad tab, or focused Desk tile cannot retarget
a request. Discovery or successful attachment still does not grant snapshot or
replace authority.

## Interface

```forth
SDLENS-SIZE

SDLENS-M-DIRECT   SDLENS-M-SHARED   SDLENS-M-BLOCKED
SDLENS-S-OK       SDLENS-S-STALE    SDLENS-S-STRUCTURAL

SDLENS-INIT      ( service-a service-u instance lens -- )
SDLENS-FINI      ( lens -- )

SDLENS-REFRESH   ( lens -- status )

SDLENS.MODE          ( lens -- a )
SDLENS.CONTEXT       ( lens -- a )
SDLENS.RREG          ( lens -- a )
SDLENS.BUS           ( lens -- a )
SDLENS.RID           ( lens -- rid )
SDLENS.REF           ( lens -- ref )
SDLENS.BIND          ( lens -- binding )
SDLENS.SNAPSHOT-CAP  ( lens -- a )
SDLENS.REPLACE-CAP   ( lens -- a )
SDLENS.REQUEST       ( lens -- a )
```

`SDLENS-INIT` leaves an endpoint-free instance in `SDLENS-M-DIRECT`. Once an
endpoint exists, a missing, inactive, invalid, or incoherent service set leaves
the lens in `SDLENS-M-BLOCKED`; it never converts broken Practice wiring into
ambient VFS access. A complete service set leaves it in `SDLENS-M-SHARED` with
an exact primary binding.

`SDLENS-REFRESH` retries only the bounded race between current-reference lookup
and exact attachment. Other failures are structural. Pad's explicit attachment
of a user-selected candidate remains editor-local.

Context, registry, bus, owner, and capability pointers are borrowed from the
activation. RID, exact reference, and binding state are copied into the lens;
the request envelope is lens-owned. The cell accessors return addresses so an
applet can read the borrowed pointer or current mode, while the structured
accessors return the embedded RID, `RREF`, or `LBIND` address.

Snapshot and replace dispatch remain applet-local. Any text in the reusable
request result is valid only until the next request reset or `SDLENS-FINI`, so
callers must copy or consume it synchronously and must not free it. Finalization
assumes the applet is quiesced; it frees only the lens-owned request and never
borrowed Context, registry, bus, owner, or capability objects.

`SDLENS-INIT` requires fresh storage or storage previously passed to
`SDLENS-FINI`. Reinitializing a live lens without finalizing it first abandons
its owned request and violates the lifecycle contract.
