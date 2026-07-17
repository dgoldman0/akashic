# Deterministic intent negotiation

`akashic/interop/intent.f` registers bounded, borrowed handler declarations
and selects a handler without treating discovery as authority. The router holds
at most 32 entries. Handler IDs and optional owner, resource-kind, and media
constraints are each bounded to 128 bytes, must be valid UTF-8, and must
remain alive for the router's activation.

Intent declarations may reference only a valid descriptor in the declaring
component's own capability array. That may be the command or resource
capability that performs the nominated behavior; it need not have
`CAP-K-INTENT` kind. Registration rejects an arbitrary valid capability
pointer from another component. Component-wide registration validates the
complete bounded declaration array and available router capacity before
installing any entry, so a rejected component cannot leave a partial route
behind.

`CINTD.PRIORITY` and `CIE.PRIORITY` remain readable for source compatibility,
but negotiation never consults them. An integer priority cannot resolve two
equally applicable handlers.

## Matching order

Callers initialize a 128-byte `CINT-SELECTOR-SIZE` record with
`CINT-SELECTOR-INIT`, set the required intent ID, and optionally set owner,
kind, and media hints. Selector, result, and choice records are exact-size
closed ABI records; larger layouts are not accepted implicitly, flags and
declared reserved cells must remain zero, and new layouts require a new ABI.
A blank handler dimension is a wildcard. A nonblank
handler constraint conflicts with a different nonblank selector value and is
excluded; a selector that omits the dimension leaves that constrained handler
eligible but does not give it an exact-match rank.

`CINT-NEGOTIATE` then applies this order:

1. keep the highest exact owner/kind rank;
2. within that class, prefer an exact media match over a media wildcard;
3. honor a valid activation-local explicit choice within the remaining class;
4. reject unavailable or stale top-ranked handlers without falling through to
   a less applicable handler;
5. return the sole remaining handler, `CINT-S-AMBIGUOUS`, or the precise
   no-handler/stale/unavailable result.

The caller-owned 312-byte `CINT-RESULT-SIZE` record retains up to all 32
top-ranked candidates. `CINT-RESULT-NTH` therefore gives a bounded Open With
candidate set when `CINTR.STATUS` is `CINT-S-AMBIGUOUS`. Registration order is
retained only to make that candidate list deterministic; it is not a
tie-breaker.

Results are canonical closed records. OK contains exactly one nonzero
candidate equal to `CINTR.SELECTED`; ambiguity contains two through 32
nonzero candidates and no selected instance; every failure contains no
candidates or selected instance. Candidate cells beyond `CINTR.COUNT` are
zeroed after every ranking/filtering pass, so a stale lower-ranked pointer is
not observable as an unused tail or available for accidental fallback.

An optional availability callback has stack effect
`( entry data -- CINT-S-* )`. It is an activation probe, must not mutate or
reenter the router, and may return only OK, unavailable, or stale-handler.
Availability is checked after applicability ranking so a dead exact-owner
handler cannot silently route an operation to a generic peer.

## Explicit choices and lifetime

`CINT-CHOICE!` captures one router entry and one exact live component instance
in an 80-byte `CINT-CHOICE-SIZE` record. The record contains the live router
address/epoch, entry order, and component instance/generation. It is
intentionally activation-local: negotiation requires the current component
registry, rejects a different router/epoch, reports unavailable when the
chosen handler has no live instance, and reports stale-handler when only a new
instance generation remains. A stale or inapplicable explicit choice never
falls back to another handler.

The choice contains live coordinates and must never be persisted. Neither a
choice, a selector, a component descriptor, an intent match, nor an Open With
candidate grants a capability. Actual calls still require ordinary target
resolution, request-bus policy, and authority checks.

## Compatibility API

`CINT-RESOLVE-STATUS ( id-a id-u router -- entry status )` performs an
unhinted negotiation and exposes ambiguity. `CINT-RESOLVE` preserves the old
single-result stack shape, but now returns zero for ambiguity instead of
choosing the highest priority. Existing Pad `resource.open` and Explorer
`resource.reveal` routes remain single-handler cases.
