# Transactional interoperability construction

`akashic/interop/construction.f` provides caller-owned builders for the three
repeated mechanical parts of interoperability contracts: closed map schemas,
owned `CV` trees, and capability descriptors. It does not choose capability
IDs, schema keys, resource semantics, effects, handlers, or persistence order.

All builders use the common statuses `CBUILD-S-OK`, `CBUILD-S-INVALID`,
`CBUILD-S-BUSY`, `CBUILD-S-CAPACITY`, `CBUILD-S-NOMEM`, `CBUILD-S-SCHEMA`,
`CBUILD-S-VALUE`, and `CBUILD-S-CAPABILITY`. The first operation failure in an
active transaction is sticky. A second `BEGIN` on the same workspace returns
`BUSY` without changing that transaction; distinct workspaces can be
interleaved. `ABORT` resets a workspace for reuse.

## Closed map schemas

Allocate `CSB-SIZE` bytes for the builder and a separate candidate field array.
The lifecycle is:

```forth
builder CSB-INIT
fields field-capacity builder CSB-BEGIN
key-a key-u child-schema builder CSB-REQUIRED
key-a key-u child-schema builder CSB-OPTIONAL
destination-schema builder CSB-SEAL-CLOSED-MAP
```

Sealing validates every reachable child schema, rejects duplicate or malformed
fields, sets the map's exact maximum length to its field count, and only then
copies the descriptor into the destination. Field names and child schemas are
borrowed. The candidate field array also becomes borrowed by the published
schema and must remain live and immutable. It must be fresh unpublished staging
storage; reusing an array already reachable from a published schema would
mutate that older graph before sealing.

`CSB-ABORT` wipes unpublished candidate fields. A successful seal detaches the
builder without wiping the now-published field array.

## Owned values

Allocate `CVB-SIZE` bytes and begin a root map or list with
`CVB-BEGIN-MAP` or `CVB-BEGIN-LIST`. `CVB-MAP-SLOT!`, `CVB-MAP-NTH`, and
`CVB-LIST-NTH` return candidate-reachable children. Nested containers use
`CVB-MAP!` and `CVB-LIST!`; scalar setters are `CVB-NULL!`, `CVB-BOOL!`,
`CVB-INT!`, `CVB-F32!`, `CVB-STRING!`, `CVB-BYTES!`, and `CVB-RESOURCE!`.
Construction setters accept an unpopulated child and fail closed if a caller
passes a value outside the candidate tree.

`CVB` is control-plane construction for bounded interoperability values, not a
container for an applet corpus. Large datasets remain in paged or streamed
storage; a contract value carries only its bounded fields or payload span.

A domain-specific atomic setter may populate a returned empty child directly
when a generic scalar setter cannot express its representation—for example,
`IRES-RREF!`. The caller must check that setter's status and abort the CVB on
failure. This is not a callback surface and does not transfer ownership out of
the candidate.

`schema-or-zero builder CVB-SEAL` performs optional deep validation; zero means
the caller deliberately requests no schema check. Publication requires a
successful seal:

```forth
destination-value builder CVB-PUBLISH
```

The destination is unchanged until publication. Publication rejects a
destination inside the candidate tree, recursively frees the destination's old
value, copies the root descriptor without allocating, and zeros the candidate.
The destination then owns the exact candidate allocation graph. `CVB-ABORT`
recursively frees that graph after any ordinary or allocation failure.

## Capability descriptors

Allocate `CAPB-SIZE` bytes, then use `CAPB-INIT` and `CAPB-BEGIN`.
`CAPB-META` stages kind and borrowed ID/title/description strings;
`CAPB-CONTRACT` stages borrowed input/output schemas, effects, flags, time
budget, and concurrency class; `CAPB-CALLBACKS` stages handler, preview, and
undo execution tokens. `destination builder CAPB-SEAL` validates the complete
descriptor with `CAP-DESC-VALID?` before publishing it. No builder invokes a
handler or any other caller callback.

## Qualification

Run the focused guest contract with:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile interop-construction-contracts \
  --max-steps 350000000 --timeout 60
```

The fixture covers destination nonmutation, malformed and duplicate schemas,
malformed capabilities, first-error stickiness, same-workspace `BUSY`,
independent builders, candidate alias refusal, ownership-transfer publication,
deterministic root/key/nested allocation failures, recursive cleanup, and exact
available-memory restoration.
