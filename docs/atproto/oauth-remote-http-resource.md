# AT OAuth remote published keys over HTTP resources

`akashic/atproto/oauth-remote-hres.f` is the retained-resource boundary for a
confidential AT OAuth client that publishes its keys through `jwks_uri`. It
derives the declared HTTPS target from one retained Client Identifier Metadata
result, then composes that same metadata result with a separately retained JWK
Set result and the provider-neutral published-P256 key owner.

The adapter is synchronous and state-free. It owns AT-specific metadata,
key-source, and two-resource provenance policy; it does not own either HTTP
resource lifecycle or duplicate generic JWK selection and durable-key
ownership.

## Public contract

```forth
AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE

AT-OAUTH-REMOTE-HRES-WORKSPACE-CLEAR
  ( workspace -- remote-hres-status )

AT-OAUTH-REMOTE-HRES-SPEC-POLICY!
  ( spec -- hres-status )

AT-OAUTH-REMOTE-HRES-STATUS-VALID?
  ( status -- flag )

AT-OAUTH-REMOTE-HRES-JWKS-TARGET!
  ( metadata-resource config profile target workspace
    -- remote-hres-status )

AT-OAUTH-REMOTE-HRES-WITH
  ( metadata-resource jwks-resource config profile vault
    callback context workspace
    -- callback-result remote-hres-status )
```

The caller provides one complete, eight-byte-aligned workspace of
`AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE` bytes. The final callback ABI is:

```forth
( config-view metadata-view
  client-kid-a client-kid-u client-public-a client-thumbprint-a
  dpop-public-a dpop-thumbprint-a
  context
  -- callback-result )
```

Every view and byte span is a read-only, callback-scoped borrow. The exact
callback result is returned only on complete success; every failure returns a
zero callback result.

`AT-OAUTH-REMOTE-HRES-SPEC-POLICY!` delegates to the shared AT OAuth HRES
policy. On an initialized, unsealed specification it installs exact status
`200`, zero redirects, required `application/json` media, and the corresponding
`Accept` value. The caller still installs the target and bind/release provider,
then seals, runs, and retains the generic resource.

## Caller-owned two-resource lifecycle

The intended synchronous flow is:

1. Configure the metadata resource for the exact configured Client Identifier,
   acquire it under the shared policy, and retain the completed result.
2. Call `AT-OAUTH-REMOTE-HRES-JWKS-TARGET!` to validate the metadata deployment
   and export its parsed `jwks_uri` as an `HTARGET`.
3. Configure and run a distinct JWK Set resource for that target, retaining its
   completed result without releasing the metadata resource.
4. Call `AT-OAUTH-REMOTE-HRES-WITH` while both descriptors and both complete
   response buffers remain stable.
5. After the call returns, deconfigure and release both resources according to
   their generic owners' cleanup contracts.

Neither exported target derivation nor final composition starts, polls,
deconfigures, or releases a resource.

## Transactional target derivation

`AT-OAUTH-REMOTE-HRES-JWKS-TARGET!` first admits the metadata descriptor, its
complete configured body-storage span, the configuration, profile, target, and
workspace. These spans must satisfy caller-memory rules and be mutually
disjoint as required by the operation.

It then requires the retained metadata envelope to be the exact configured
Client Identifier result: admitted result, status `200`, zero redirects,
matching requested and effective URI bytes, and JSON media. The body must pass
the full AT OAuth deployment composition and select confidential
`private_key_jwt` with exactly the remote `jwks_uri` source; inline `jwks` is
not an alternative. The URI is parsed into a staged HTTPS `HTARGET`.

Only a complete success copies that staged value to the caller's target.
Every rejection or failure leaves the target unchanged. Geometry rejection
also leaves the workspace unchanged; once an operation is admitted, its full
workspace is wiped on every returned outcome.

## Final provenance and key ownership

`AT-OAUTH-REMOTE-HRES-WITH` does not trust the earlier target export as
continuing evidence. While the retained metadata body is live, it reruns the
deployment validation and freshly reparses the declared `jwks_uri` into its
private staged target. It then requires the separately retained JWK Set result
to have:

- an admitted HTTP result, exact status `200`, zero redirects, and JSON media;
- requested and effective targets equal to the freshly parsed target; and
- a nonempty used body within
  `JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES`.

The target comparison is against normalized `HTARGET` identity exposed by the
generic HRES boundary. Canonically equivalent URI spellings are therefore
accepted when they produce the same normalized target. Original `jwks_uri`
source bytes are not the provenance boundary and are not required to compare
byte-for-byte with canonical HRES target bytes.

After provenance succeeds, the adapter delegates the retained body and the
validated configuration binding to `OAUTH2-P256-PUBLISHED-WITH`. That generic,
provider-neutral composition checks the complete JWK Set, selects the durable
client record's authenticated `kid`, requires its public point and RFC 7638
thumbprint to match the locally owned client key, resolves a distinct durable
DPoP identity, releases its private-key borrows, and only then invokes the AT
callback bridge. There is no remote-to-inline fallback.

## Ownership, admission, and cleanup

Final preflight covers both resource descriptors, both complete
`HRES-BODY-STORAGE@` spans, configuration, profile, vault, and workspace
before the first workspace write. The two resource domains must not overlap
each other or the fixed composition inputs, and every applicable span must be
external to protected vault storage. An alias in an unused response-buffer
tail is still rejected even though only `HRES-BODY@` bytes are parsed.

The adapter borrows and never wipes or mutates either resource descriptor or
response buffer. The caller must keep both byte-stable for the complete
synchronous operation; this API does not defend against concurrent caller
mutation. Once final composition is admitted, the complete adapter workspace
is wiped after success, policy failure, callback failure, or contained
internal throw. `AT-OAUTH-REMOTE-HRES-WORKSPACE-CLEAR` provides the same
qualified explicit wipe for caller cleanup.

## Status values

Values 0 through 41 use the established confidential AT OAuth composition
meanings under the `AT-OAUTH-REMOTE-HRES-S-*` prefix: success, public
admission and alias outcomes, deployment-policy failures, remote key-source
and checked-JWK failures, durable-key/vault outcomes, callback containment,
and caller-memory/platform failures. The meanings match the corresponding
table in [AT OAuth Confidential Inline Deployment](oauth-deployment-inline.md)
except that `KEY-SOURCE` here requires remote-only `jwks_uri` rather than
inline-only `jwks`.

| Value | Status | Meaning |
|---:|---|---|
| 42 | `AT-OAUTH-REMOTE-HRES-S-METADATA-HTTP` | The metadata resource is not an admitted exact Client Identifier JSON result. |
| 43 | `AT-OAUTH-REMOTE-HRES-S-JWKS-TARGET` | A declared `jwks_uri` is empty or cannot form the required HTTPS target. |
| 44 | `AT-OAUTH-REMOTE-HRES-S-JWKS-HTTP` | The JWK Set resource is not an admitted JSON result for the freshly derived normalized target. |

`AT-OAUTH-REMOTE-HRES-STATUS-VALID?` accepts only values 0 through 44.
`AT-OAUTH-REMOTE-HRES-SPEC-POLICY!` instead returns the underlying
`HRES-S-*` result from specification construction.

## Non-goals and recorded deferrals

This adapter does not perform DNS resolution, public-address or SSRF
admission, TLS hostname verification, deadlines, cancellation, lease
ownership, redirects, PAR, browser authorization, token exchange, DPoP proof
signing, nonce handling, session installation, XRPC, or Streams work. DNS,
SSRF, TLS, deadline, and truthful cleanup behavior belong to the generic
transport owner and require a later real-transport or deterministic fake-PDS
integration gate.

To reach that vertical slice sooner, the initial adapter gate intentionally
does not require the exhaustive cross-product of HTTP status, redirect, media,
target-spelling, body-capacity, alias-tail, subordinate-status, callback-stack,
and cleanup-canary variants. URI fuzz beyond representative normalized-target
provenance, concurrent caller-mutation experiments, and every checked-JWK or
durable-vault failure permutation are also recorded as non-gating follow-up
qualification. These deferrals do not weaken the production contract above;
they limit the first test matrix while real ATproto acquisition and
integration are brought online.
