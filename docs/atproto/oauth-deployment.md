# AT OAuth Client Deployment Binding

`akashic/atproto/oauth-deployment.f` binds one caller-supplied OAuth Client ID
Metadata Document to one immutable OAuth client configuration and one ready AT
OAuth profile. It composes the structural decoder in
`security/oauth2/client-metadata.f`, the single-validation configuration view in
`security/oauth2/client-config.f`, and the local AT client policy in
`atproto/oauth-client.f`.

This is a synchronous, state-free local policy adapter. Success means the
selected configuration and the declarations in the supplied document agree
under the policy below. It does not prove where the document came from and does
not qualify or acquire its client-authentication keys.

For the complete confidential inline-`jwks` composition, including checked
P-256 selection and comparison with durable local client and DPoP identities,
see [AT OAuth Confidential Inline Deployment](oauth-deployment-inline.md).

## Public contract

```forth
AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE  \ 53760 bytes

AT-OAUTH-DEPLOYMENT-WORKSPACE-CLEAR
  ( workspace -- status )

AT-OAUTH-DEPLOYMENT-STATUS-VALID?
  ( status -- flag )

AT-OAUTH-DEPLOYMENT-WITH
  ( document document-u config profile callback context workspace
    -- callback-result deployment-status )
```

The callback contract is:

```forth
( config-view metadata-view context -- callback-result )
```

The callback runs exactly once only after configuration validation, profile
readiness, structural metadata parsing, and every local deployment policy check
have succeeded. Its one result is an uninterpreted caller value. Every failure
before or during the callback returns zero as `callback-result`.

A callback throw, extra result, missing result, or attempt to consume below its
arguments returns `AT-OAUTH-DEPLOYMENT-S-CALLBACK`. The callback boundary checks
both stack depth and a private guard below the callback arguments.

The callback remains trusted synchronous Forth code. The guard detects contract
mistakes; it is not a sandbox against a deliberately hostile callback that
reconstructs deeper cells while preserving depth. The public preflight proves
only that the callback execution token is nonzero, so native faults from an
arbitrary invalid token are outside the `THROW` boundary.

## Inputs and admission

`document` is a nonempty caller-owned span of at most
`OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES`, currently 5120 bytes. `config` must
be a valid `OAUTH2-CLIENT-CONFIG`, and `profile` must be a structurally valid,
ready `AT-OAUTH-PROFILE`.

The configuration, profile, and workspace must start on eight-byte boundaries.
The callback execution token must be nonzero. The complete deployment workspace
must not overlap the document, configuration, or profile. The `context` cell is
passed through unchanged and is otherwise uninterpreted.

The complete 53,760-byte workspace contains the nested 432-byte AT
client-policy workspace and the generic OAuth client-metadata workspace.
Callers allocate only the one public deployment workspace; no module-owned
operation state is retained.

`AT-OAUTH-DEPLOYMENT-WORKSPACE-CLEAR` qualifies and clears one aligned complete
workspace. A rejected clear does not modify it.

## Borrowed views and lifetime

The callback receives the exact `config-view` supplied by
`OAUTH2-CLIENT-CONFIG-WITH` and the exact `metadata-view` supplied by
`OAUTH2-CLIENT-METADATA-WITH`. Both are read-only, callback-scoped borrows. They
must not be retained, mutated, or used after the callback returns.

The configuration view uses the `OAUTH2-CLIENT-VIEW-*` accessors. The metadata
view uses the `OAUTH2-CLIENT-METADATA-VIEW-*` accessors and their component
statuses.

For confidential deployments, the metadata view exposes one of:

- `OAUTH2-CLIENT-METADATA-VIEW-JWKS@`, which borrows the exact strict-validated
  JSON object token from the caller's document; or
- `OAUTH2-CLIENT-METADATA-VIEW-JWKS-URI@`, which borrows decoded URI bytes held
  in the transient metadata workspace.

Those bytes have not passed a checked JWK Set or URI/acquisition policy. Inline
JWKS qualification must finish synchronously while the metadata borrow is live,
or the caller must copy the source bytes into separately owned storage.
A `jwks_uri` acquisition owner must copy the decoded URI during the callback
before scheduling any later fetch.

## Local deployment policy

Before inspecting the document, the binder applies
`AT-OAUTH-CLIENT-VIEW-ADMIT` to the selected configuration and ready profile.
This retains the complete local policy documented for
`atproto/oauth-client.f`: the client identifier, selected redirect, AT scope,
public or confidential authentication selection, and DPoP declaration must
already form an admissible AT client selection.

The decoded document must then satisfy all of the following:

- `client_id` is byte-for-byte equal to the configured client identifier. No
  URL normalization, case folding, or alternate serialization is applied.
- `application_type`, when present, is exactly `native` or `web` as selected by
  the configuration. Omission is accepted only for a web configuration, for
  which this binder applies the web default; it is not accepted for native.
- `grant_types` is present. A refresh-disabled configuration requires exactly
  the singleton `authorization_code`. A refresh-enabled configuration requires
  exactly `authorization_code` and `refresh_token`. Array order is irrelevant,
  and no additional grant value is accepted.
- `response_types` is present and is exactly the singleton `code`.
- `redirect_uris` is present and nonempty, contains the selected configured
  redirect by exact decoded-byte equality, and contains only redirects admitted
  by the same AT client-ID, application-type, and redirect policy used for the
  selected configuration. Additional declared redirects are allowed only when
  each one passes that policy.
- `scope` is present. Every exact, case-sensitive token requested by the
  configuration occurs in the declared scope set. The document may declare
  additional valid scope tokens.
- `token_endpoint_auth_method` is present, is either `none` or
  `private_key_jwt`, and exactly matches the configured method. No omitted
  authentication-method default is invented.
- A public `none` selection requires
  `token_endpoint_auth_signing_alg` to be absent. A confidential
  `private_key_jwt` selection requires it to be present, exactly `ES256`, and
  byte-for-byte equal to the configured algorithm.
- `dpop_bound_access_tokens` is present and true, and the configuration also
  declares DPoP-bound access tokens.
- A public `none` selection declares neither `jwks` nor `jwks_uri`. A
  confidential `private_key_jwt` selection declares exactly one. The generic
  metadata parser rejects simultaneous `jwks` and `jwks_uri`; this binder also
  rejects absence for confidential clients and presence for public clients.

Unknown extension members remain subject to complete strict JSON validation by
the generic metadata parser but otherwise do not affect local deployment
policy.

## Preflight, cleanup, and precedence

Span qualification, alignment, document length, callback validity, and
workspace-disjointness checks happen before any workspace write. Invalid
configuration validation and a non-ready profile also precede ownership of the
deployment workspace. These preflight failures return a zero callback result
and leave every workspace byte unchanged.

After the configuration is valid, the profile is ready, and the selected
configuration passes local AT client policy, the complete deployment workspace
is cleared before metadata parsing. Every later normal outcome wipes it again,
including structural metadata rejection, semantic-policy rejection, callback
success, and callback failure. A caught unexpected operation throw also wipes
the complete workspace before returning
`AT-OAUTH-DEPLOYMENT-S-INTERNAL`.
An admitted selected-client policy rejection also returns with the complete
deployment workspace wiped.

The document, configuration, and profile are borrowed read-only and are never
cleared or rewritten by this module.

When more than one input is bad, the first applicable stage wins:

1. public argument geometry, capacity, and alias admission;
2. complete immutable configuration validation;
3. AT profile readiness;
4. selected AT client policy;
5. structural Client ID Metadata Document parsing;
6. deployment policy in this exact order: client identifier, application type,
   grants, responses, redirects, scope, authentication method, authentication
   algorithm, DPoP, then key source;
7. caller callback execution.

Consequently an invalid configuration precedes a non-ready profile, a non-ready
profile precedes malformed metadata, and a structural metadata failure precedes
all document/config semantic mismatches.

## Qualification boundaries

An `AT-OAUTH-DEPLOYMENT-S-OK` result is deliberately not complete production
deployment qualification. Four boundaries remain separate.

### Client-metadata HTTP provenance

The binder receives bytes, not an HTTP result. It does not prove that the
document was fetched from the configured `client_id`, that the requested and
effective targets were unchanged, or that the response used exact status 200,
zero redirects, an accepted JSON media type, and a bounded body. It performs no
DNS resolution, public-address/SSRF admission, authenticated TLS hostname
verification, deadline, or lease management.

A later HTTP-resource adapter must establish those facts before treating this
local binding as deployment evidence. The document's internal `client_id`
equality check does not replace transport provenance.

### Checked inline JWKS

For inline `jwks`, the generic parser proves only that the borrowed token is a
strict JSON object. This binder still does not invoke
`JOSE-JWK-SET-P256-SELECT`, which performs the bounded full-set validation,
private/symmetric and unsupported-metadata rejection, decoded-`kid` selection,
public-key parsing, and thumbprint derivation required for an ES256
client-authentication key.

The deployment owner must invoke that selector synchronously while the
metadata callback's raw `jwks` span remains borrowed, or first copy the exact
token into separately owned stable storage. Binder success alone does not
claim checked-JWKS success.

`oauth-deployment-inline.f` closes this inline boundary together with local
private-key identity for confidential deployments. It deliberately rejects
public and `jwks_uri` key sources rather than treating them as the same
composition.

### `jwks_uri` acquisition

For `jwks_uri`, the binder proves only the declaration relationship required by
the selected authentication method. It does not validate URI syntax or scheme
and does not fetch the resource.

A later acquisition owner must apply HTTPS target policy, hardened DNS and SSRF
admission, authenticated TLS, exact requested/effective target equality, exact
HTTP status and redirect policy, JSON media validation, and a bounded response.
The acquired body must then pass `JOSE-JWK-SET-P256-SELECT`, the same checked
JWK Set qualification used for inline data.

### Private-key ownership

Neither the metadata document nor this binder proves possession of the
corresponding private client-authentication key. The configuration's opaque
binding is an identity, not key material.

A higher deployment owner must resolve that binding to the intended durable
private key, derive or recover its public identity, and compare it with the
selected published JWK, for example through an RFC 7638 thumbprint. It must also
prove that the client-authentication key and the per-session DPoP key are
distinct identities. Vault recovery, rotation, revocation, assertion signing,
and durable key continuity remain outside this module.

The confidential inline composition described in
[AT OAuth Confidential Inline Deployment](oauth-deployment-inline.md) performs
that synchronous local resolution, compares both the public key and
thumbprint, and proves client/DPoP distinctness. Remote `jwks_uri` acquisition
remains outside it.

Native custom-scheme or universal/app-link ownership, browser launch, PAR,
PKCE, token exchange, session persistence, XRPC, and Streams integration also
remain later composition responsibilities.

## Status values

| Status | Meaning |
|---|---|
| `AT-OAUTH-DEPLOYMENT-S-OK` | Local binding succeeded and the callback returned exactly one result. |
| `AT-OAUTH-DEPLOYMENT-S-INVALID` | A pointer shape, required nonempty span, alignment, or callback argument is invalid. |
| `AT-OAUTH-DEPLOYMENT-S-CAPACITY` | The document exceeds its public bound or structural metadata capacity is exhausted. |
| `AT-OAUTH-DEPLOYMENT-S-ALIAS` | The writable workspace overlaps an input, or a subordinate parser reports an alias. |
| `AT-OAUTH-DEPLOYMENT-S-CONFIG` | The immutable client configuration is invalid. |
| `AT-OAUTH-DEPLOYMENT-S-PROFILE` | The AT OAuth profile is not structurally ready. |
| `AT-OAUTH-DEPLOYMENT-S-METADATA` | Strict JSON, required structural metadata, type, value, or duplicate validation failed. |
| `AT-OAUTH-DEPLOYMENT-S-CLIENT-ID` | The selected client identifier fails local AT policy or differs from document `client_id`. |
| `AT-OAUTH-DEPLOYMENT-S-APPLICATION` | The application declaration is absent where required or does not match the selection. |
| `AT-OAUTH-DEPLOYMENT-S-GRANT` | The grant declaration is absent or is not the exact selected grant set. |
| `AT-OAUTH-DEPLOYMENT-S-RESPONSE` | The response declaration is absent or is not exactly `code`. |
| `AT-OAUTH-DEPLOYMENT-S-REDIRECT` | Redirect declarations are absent, omit the selected redirect, or contain a locally invalid redirect. |
| `AT-OAUTH-DEPLOYMENT-S-SCOPE` | Scope is absent or does not contain every configured requested token. |
| `AT-OAUTH-DEPLOYMENT-S-AUTH-METHOD` | The method is absent, unsupported, or differs from the configuration. |
| `AT-OAUTH-DEPLOYMENT-S-AUTH-ALGORITHM` | The signing-algorithm presence or ES256 value does not match the selected method/configuration. |
| `AT-OAUTH-DEPLOYMENT-S-DPOP` | The document does not explicitly declare DPoP-bound tokens, or the configuration is not DPoP-bound. |
| `AT-OAUTH-DEPLOYMENT-S-KEY-SOURCE` | Key-source absence or presence does not match the selected public or confidential method. |
| `AT-OAUTH-DEPLOYMENT-S-CALLBACK` | The caller callback threw or violated its exact stack contract. |
| `AT-OAUTH-DEPLOYMENT-S-INTERNAL` | An operation threw after admission or a subordinate component returned an impossible status. |
| `AT-OAUTH-DEPLOYMENT-S-RANGE` | A caller span has invalid physical geometry or crosses an admitted memory window. |
| `AT-OAUTH-DEPLOYMENT-S-PROTECTED` | A caller span intersects BIOS, private, or live-stack storage. |
| `AT-OAUTH-DEPLOYMENT-S-PLATFORM` | Caller-memory qualification failed unexpectedly or returned an undocumented result. |

Use `AT-OAUTH-DEPLOYMENT-STATUS-VALID?` before accepting an arbitrary status
cell.
