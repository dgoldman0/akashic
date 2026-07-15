# Machine TLS trust registry

`akashic/net/tls-trust-registry.f` composes the reviewed TLS anchors needed by
the installed machine image. Trusted boot modules register contributors; the
machine owner then builds one bounded MPTA bundle and loads it into KDOS before
external I/O becomes available.

The registry is a provisioning boundary, not a network capability or a trust
discovery service. Registration does not authorize an applet to make requests,
and applets are not given the builder or a way to replace the frozen bundle.

## Lifecycle

The machine-global registry is core-0 owned and has a one-way lifecycle:

- `OPEN`: reviewed contributors may register.
- `BUILDING`: `MTRUST-FREEZE` is invoking contributors and validating the
  composed bundle.
- `FROZEN`: KDOS contains the one accepted snapshot. Repeating
  `MTRUST-FREEZE` only verifies its version, anchor count, and generation.
- `FAILED`: composition failed and the KDOS trust store was reset. There is no
  retry or thaw within that boot.

Desk calls `MTRUST-FREEZE` before it initializes the machine external-I/O
service, publishes interoperability endpoints, or autostarts applets. A valid
empty bundle is allowed for an image with no live-network contributors.

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
during applet launch.

`MTRUST-ANCHOR+` accepts a DER CA certificate, a nonempty validated DNS scope,
and either exact-host flags (`0`) or `TTAF-SUBDOMAINS`. It rejects malformed
bounds, unsupported flags, exact duplicate records, stale builders, and totals
beyond KDOS's eight-anchor and 32768-byte limits. KDOS remains the final X.509
and CA validator at the single load boundary. An emitter error, throw, or stack
imbalance fails the entire composition; partial trust is never retained.

## Bundle identity

The registry serializes MPTA version 1 with a zero generation field, computes
SHA3-256 over those exact bytes using the standard guarded hardware wrapper,
and stores the first 64 digest bits as the bundle generation. It then invokes
`TLS-TRUST-LOAD` once. The generation is a deterministic content tag for
detecting unexpected replacement; it is not a signature, an update sequence,
or rollback protection.

`MTRUST-GENERATION@`, `MTRUST-COUNT@`, and `MTRUST-FROZEN?` describe the accepted
snapshot. `MTRUST-LAST-STATUS@` and `MTRUST-LAST-DETAIL@` retain freeze failure
diagnostics. Direct KDOS trust loading remains a platform primitive, not an
applet or provider lifecycle operation.

Run the deterministic contracts with:

```sh
python local_testing/akashic_tui.py smoke --profile tls-trust-registry
python local_testing/akashic_tui.py smoke --profile tls-trust-registry-error
python local_testing/akashic_tui.py smoke --profile tls-trust-registry-throw
```
