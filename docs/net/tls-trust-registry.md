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
After every emitter, the registry revalidates the exact builder descriptor and
its complete bounded record sequence before invoking another contributor or
hashing output. A callback cannot turn corrupt count, position, capacity, or
buffer metadata into an unbounded duplicate scan or final hash.

## Reviewed run artifacts

`MTRUST-MPTA+ ( bundle-a bundle-u builder -- status )` lets a trusted boot
emitter contribute a separately reviewed MPTA v1 artifact without compiling
its CA bytes into an applet. The operation is intentionally narrower than
`TLS-TRUST-LOAD`:

- it is accepted only on core 0 during `BUILDING` with the exact active builder;
- the input and active output allocation must not overlap;
- the artifact must contain one through eight complete records and no trailing
  bytes;
- every record must use a nonempty valid DNS scope and flags `0`, so global and
  include-subdomains anchors are rejected;
- duplicates within the artifact or against earlier contributors are rejected;
  and
- all count and byte capacity is proven before the first output byte changes.

An unexpected append-pass failure rolls the builder back to its original count
and position and clears any bytes appended by that call. KDOS still performs
the authoritative certificate, CA, key-usage, and supported-key validation when
the completed machine bundle is loaded. Import success alone does not prove a
server certificate path, authorize network I/O, or make response content
trustworthy.

The artifact header's generation must equal the first 64 bits of SHA3-256 over
the exact artifact with generation bytes 8 through 15 treated as zero. This is
a deterministic content/corruption tag, not a signature, authenticated boot
claim, provenance proof, freshness proof, or rollback counter. The provisioning
path remains responsible for authenticating and reviewing the artifact and for
associating its scopes with the intended installed services.

A run composition can retain the reviewed bytes in its own bounded buffer and
pass a two-cell descriptor as contributor context:

```forth
CREATE FEED-TRUST-DESCRIPTOR 16 ALLOT

: FEED-TRUST-EMIT  ( builder descriptor -- status )
    DUP @ SWAP 8 + @ ROT MTRUST-MPTA+ ;

reviewed-bundle-a FEED-TRUST-DESCRIPTOR !
reviewed-bundle-u FEED-TRUST-DESCRIPTOR 8 + !
S" org.example.reviewed-feed-trust" ['] FEED-TRUST-EMIT
    FEED-TRUST-DESCRIPTOR MTRUST-REGISTER
MTRUST-S-OK <> ABORT" feed trust registration failed"
```

The composition owns the descriptor through registration and keeps its artifact
bytes immutable and quiescent through the synchronous `MTRUST-FREEZE` call.
The importer is core-0-only, uses global scratch, and is not reentrant. Ordinary
Streams source creation and refresh never receive the builder, import artifacts,
add anchors, or thaw the accepted snapshot.

This API supplies the reviewed preboot/run-contribution alternative; it does
not bind an artifact scope to a Streams source identity or revision. A later
configured-source composition must separately prove that the canonical source
host has the intended reviewed provisioning before opening it, and TLS still
proves the presented path. The shipped composition has no ambient broad WebPKI
fallback, although other explicitly reviewed `MTRUST-ANCHOR+` contributors may
deliberately use `TTAF-SUBDOMAINS` for their own services.

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
python local_testing/akashic_tui.py smoke --profile tls-trust-mpta
python local_testing/akashic_tui.py smoke --profile tls-trust-registry-error
python local_testing/akashic_tui.py smoke --profile tls-trust-registry-throw
python local_testing/akashic_tui.py smoke --profile tls-trust-registry-builder
```
