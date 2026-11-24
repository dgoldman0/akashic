# Machine TLS trust registry

`akashic/net/tls-trust-registry.f` composes the TLS anchors the installed
machine trusts. Trusted boot modules register contributors; the machine owner
then builds one MPTA version 2 bundle, sized to what they contribute, and
loads it into KDOS before external I/O becomes available.

The registry is a provisioning boundary, not a network capability or a trust
discovery service. Registration does not authorize an applet to make requests,
and applets are not given the builder or a way to replace the frozen bundle.

## What a bundle holds

Two kinds of anchor reach KDOS (MegaPad's `docs/tls-hardening.md`, Trust
Bundles):

- **Global anchors** may end the certificate path of any host that no scoped
  anchor binds. They come from one place only: the pinned root set, the roots
  NSS trusts for TLS server authentication, with Mozilla's distrust-after
  dates and NSS's imposed name constraints (see [web-roots.md](web-roots.md)).
- **Scoped anchors** are private roots. A scoped anchor names an exact host,
  or with `TTAF-SUBDOMAINS` a domain and every name below it, and binds those
  hosts: their paths may end only at scoped anchors that name them, so no
  public certificate can stand in for the private root.

Public services such as Bluesky or an AI provider need no anchor of their own:
their chains verify against the global set.

## Lifecycle

The machine-global registry is core-0 owned and has a one-way lifecycle:

- `OPEN`: reviewed contributors may register.
- `BUILDING`: `MTRUST-FREEZE` is invoking contributors and validating the
  composed bundle.
- `FROZEN`: KDOS contains the one accepted snapshot. Repeating
  `MTRUST-FREEZE` only verifies its version, anchor count, and generation.
- `FAILED`: composition failed and the KDOS trust store was reset. There is no
  retry or thaw within that boot.

Desk registers the root set's contributor with its origin place, when it has
one, then calls `MTRUST-FREEZE` before it initializes the machine external-I/O
service, publishes interoperability endpoints, or autostarts applets. An image
built without the root set's file composes a bundle with no global anchors, so
its public TLS fails closed with `TLS-CERT-NO-TRUST`.

## Contributors

A contributor has a stable identifier and an emitter with stack effect
`( builder context -- status )`:

```forth
: EXAMPLE-TRUST-EMIT  ( builder context -- status )
    DROP >R
    example-cert example-cert-u S" service.example" 0 R>
    MTRUST-ANCHOR+ ;

S" org.example.trust.service" ['] EXAMPLE-TRUST-EMIT 0 MTRUST-REGISTER
MTRUST-S-OK <> ABORT" trust registration failed"
```

Repeating the same identifier, emitter, and context while the registry is open
is idempotent. Reusing an identifier for a different emitter or context is a
conflict. Registration after freezing is rejected, so installing a new
live-network package requires a new boot composition rather than widening trust
during applet launch. The contributor table grows as contributors register.

`MTRUST-ANCHOR+ ( cert-a cert-u scope-a scope-u flags builder -- status )`
adds a scoped anchor: a DER CA certificate of 128 to 8192 bytes, a nonempty
validated DNS scope, and either exact-host flags (`0`) or `TTAF-SUBDOMAINS`.
It rejects malformed bounds, unsupported flags, a missing scope, exact
duplicate records, and stale builders, and answers `MTRUST-S-CAPACITY` when
the builder cannot grow.

`MTRUST-WEB-ROOTS+ ( bundle-a bundle-u builder -- status )` adds the global
root set, once per composition. The bundle must be exactly `WEB-ROOTS-BYTES`
long, hash to `WEB-ROOTS-SHA256` and hold `WEB-ROOTS-COUNT` records without
scopes, the constants `net/web-roots/web-roots-pin.f` pins; anything else is
`MTRUST-S-INVALID`. No other path adds a global anchor.

KDOS remains the final X.509 and CA validator at the single load boundary. An
emitter error, throw, or stack imbalance fails the entire composition; partial
trust is never retained. After every emitter, the registry revalidates the
exact builder descriptor and its complete record sequence before invoking
another contributor or hashing output, so a callback cannot turn corrupt
count, position, capacity, or buffer metadata into an unbounded scan or hash.

## Bundle identity

The registry serializes MPTA version 2 with a zero generation field, computes
SHA3-256 over those exact bytes using the standard guarded hardware wrapper,
and stores the first 64 digest bits as the bundle generation. It then invokes
`TLS-TRUST-LOAD` once. The generation is a deterministic content tag for
detecting unexpected replacement; it is not a signature, an update sequence,
or rollback protection.

`MTRUST-GENERATION@`, `MTRUST-COUNT@`, and `MTRUST-FROZEN?` describe the accepted
snapshot. `MTRUST-LAST-STATUS@` and `MTRUST-LAST-DETAIL@` retain freeze failure
diagnostics. Direct KDOS trust loading remains a platform primitive, not an
applet or provider lifecycle operation.

`local_testing/test_tls_trust_contracts.py` checks registration, scoped
anchors, the root set's refusals, the freeze and every way an emitter can fail
the composition; `local_testing/test_web_roots.py` loads the root set through a
place and verifies captured public chains against it.
