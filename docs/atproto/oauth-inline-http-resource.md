# AT OAuth confidential inline deployment over HTTP resources

`akashic/atproto/oauth-inline-hres.f` is the retained-resource boundary between
one caller-owned generic HTTPS resource and the confidential inline deployment
composition in `atproto/oauth-deployment-inline.f`. It binds transport
provenance for a Client Identifier Metadata Document to the exact configured
`client_id`, then submits the admitted response body to
`AT-OAUTH-INLINE-WITH`.

This is a synchronous, state-free adapter. It consumes an already completed
and retained `HRES` result; it does not start or poll a request, own a port
lease, deconfigure the resource, or perform DNS, socket, TLS, browser, token,
session, XRPC, or Streams work.

## Public contract

```forth
AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE  \ 111928 bytes

AT-OAUTH-INLINE-HRES-WORKSPACE-CLEAR
  ( workspace -- inline-hres-status )

AT-OAUTH-INLINE-HRES-SPEC-POLICY!
  ( spec -- hres-status )

AT-OAUTH-INLINE-HRES-STATUS-VALID?
  ( status -- flag )

AT-OAUTH-INLINE-HRES-WITH
  ( resource config profile vault callback context workspace
    -- callback-result inline-hres-status )
```

The workspace is exactly the 111,928-byte
`AT-OAUTH-INLINE-WORKSPACE-SIZE`; the adapter adds no hidden operation storage.
Its clear operation retains the same admission and no-write-on-rejection
contract as `AT-OAUTH-INLINE-WORKSPACE-CLEAR`.

The final callback ABI is unchanged:

```forth
( config-view metadata-view
  client-kid-a client-kid-u client-public-a client-thumbprint-a
  dpop-public-a dpop-thumbprint-a
  context
  -- callback-result )
```

All views and byte spans remain read-only, callback-scoped borrows. The
resource body remains caller-owned and must stay stable until
`AT-OAUTH-INLINE-HRES-WITH` returns. The complete callback, checked JWK Set,
durable-key, cleanup, and result semantics are those documented in
[AT OAuth Confidential Inline Deployment](oauth-deployment-inline.md).

## Resource specification policy

Call `AT-OAUTH-INLINE-HRES-SPEC-POLICY!` on an initialized, unsealed `HRES`
specification. It installs:

- `Accept: application/json`;
- exact success status `200`;
- a redirect maximum of zero;
- required response media; and
- a pure media callback accepting only the case-insensitive base media type
  `application/json`.

Syntactically valid media parameters such as `charset=utf-8` are accepted.
Vendor `+json`, `text/json`, missing, duplicate, or malformed content types are
not.

The helper returns the first exact `HRES` setter failure. Like the underlying
pre-seal setters, it is not an atomic transaction and does not seal the
specification. The caller still installs the configured Client Identifier as
the exact target and supplies the bind/release provider before sealing.

That provider remains responsible for hardened DNS resolution, public-address
and SSRF admission, authenticated TLS hostname verification, deadlines, and
truthful lease cleanup. An HTTPS URI in an immutable client configuration does
not establish any of those properties by itself.

## Retained-result admission

The adapter does not trust the caller merely because the policy helper was
used. Before parsing the response body or invoking the inline composition, it
independently requires:

- a valid admitted `HRES` result;
- exact HTTP status `200`;
- redirect count zero;
- the canonical requested-target URI bytes to equal the validated
  configuration's `client_id` bytes exactly;
- the canonical effective-target URI bytes to equal the same configured
  `client_id` bytes exactly; and
- parsed base media type `application/json`.

Both target comparisons and the explicit redirect count are intentional.
There is no URI normalization, case folding, or alternate Client Identifier
serialization at this boundary. The requested-target comparison prevents an
unrelated completed resource from being replayed into the deployment, while
the effective-target and redirect checks retain final-destination provenance.

After those checks, the adapter passes the exact `HRES-BODY@` bytes to
`AT-OAUTH-INLINE-WITH`. All Client ID Metadata structure, selected-client
policy, inline JWK Set, durable local identity, and final callback checks
remain owned by that composition rather than being duplicated here.

## Ownership and cleanup

Admission covers the resource descriptor, its complete configured
`HRES-BODY-STORAGE@` span, the immutable configuration, ready profile, vault,
and complete writable workspace. The full response buffer is considered even
when only a prefix contains the admitted body; an alias in its unused tail is
still an alias. Caller-memory, vault-external-span, alignment, and disjointness
failures are rejected before the first workspace write.

This retained-result check cannot retroactively make an unsafe response buffer
safe. The resource owner must establish that the complete response storage is
external to the vault, configuration, profile, resource descriptor, and
composition workspace before starting acquisition. The adapter repeats those
checks before consuming the result so an unsafe or replayed resource cannot be
treated as deployment evidence.

The adapter borrows but never wipes, deconfigures, or mutates the resource or
its response storage. The caller remains responsible for deconfiguring the
resource and completing any release or cleanup quarantine after this
synchronous call returns, including after an HTTP-envelope or inline-policy
failure. No resource body, metadata view, JWK token, key identity, or callback
view acquires a lifetime beyond the call.

## Status values

Values 0 through 41 are the existing `AT-OAUTH-INLINE-S-*` values and meanings,
passed through unchanged. This preserves distinctions among caller-memory,
deployment-policy, checked-JWK, durable-key, callback, and cleanup failures.
See the complete table in
[AT OAuth Confidential Inline Deployment](oauth-deployment-inline.md).

| Value | Status | Meaning |
|---:|---|---|
| 0–41 | `AT-OAUTH-INLINE-S-*` | Exact subordinate inline status, unchanged. |
| 42 | `AT-OAUTH-INLINE-HRES-S-HTTP` | The retained resource is not an admitted result or fails status, redirect, requested/effective Client Identifier, or JSON-media provenance. |

`AT-OAUTH-INLINE-HRES-STATUS-VALID?` accepts only the documented range 0
through 42. `AT-OAUTH-INLINE-HRES-SPEC-POLICY!` instead returns the underlying
`HRES-S-*` status from specification construction.

An HTTP provenance failure returns a zero callback result and never invokes
the final callback. Once provenance is admitted,
`AT-OAUTH-INLINE-HRES-WITH` returns the exact callback result and inline status
from `AT-OAUTH-INLINE-WITH`.

## Qualification scope and recorded deferrals

The vertical-slice gate passed the static contract check and the complete
sequential staged lifecycle in 1,326,867,836 guest steps and 856.64 summed
stage seconds. The focused adapter groups cover the shared specification
policy, one exact confidential-inline success, wrong requested/effective
target provenance, redirect, status and media rejection, and full
response-storage alias preflight. The staged run also retains the linked
generic HRES and established profile, deployment, and inline fixture loads;
their broader behavior remains covered by the separately recorded suites
rather than being rerun as a new edge matrix here.

The following broader qualification is intentionally recorded rather than
made a gate to the next production-shaped step:

- the full cross-product of HRES status, redirect, header, and media outcomes;
- every subordinate `AT-OAUTH-INLINE-S-*` pass-through value;
- URI spelling and canonical-target fuzz beyond the exact-byte provenance
  cases; and
- real DNS, public-address/SSRF admission, TLS hostname verification,
  deadline, cancellation, and lease-cleanup integration.

The first three items must be reviewed before this boundary is declared
finally closed. The last item belongs to the generic transport owner and the
deterministic fake-PDS vertical slice, because this retained-result adapter
neither opens nor owns a network operation.

## Remaining boundary

This adapter establishes transport provenance only for the Client Identifier
Metadata Document used by the existing confidential inline-`jwks`
composition. It does not acquire a remote `jwks_uri`, construct PAR or PKCE
state, process an authorization response, sign a client assertion or DPoP
proof, exchange a token, handle a DPoP nonce, or install a durable session.

Remote `jwks_uri` remains a separate acquisition path. It must bind the exact
declared URI to another retained HTTPS result under equivalent transport
controls, pass the body through the checked P-256 JWK Set selector, and compare
the selected public key and thumbprint with the same durable local client
identity. There is no fallback between inline and remote key sources.
