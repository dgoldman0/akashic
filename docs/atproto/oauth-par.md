# AT Protocol OAuth pushed authorization requests

`akashic/atproto/oauth-par.f` is the state-free AT Protocol policy adapter for
the pushed authorization request (PAR) portion of one OAuth authorization-code
attempt. It composes:

- an immutable generic OAuth client configuration;
- a ready AT OAuth discovery profile;
- the generic `O2CODE` state, PKCE, issuer, and one-shot transaction;
- one caller-configured generic OAuth form POST owner; and
- the generic strict PAR success-response decoder.

The adapter owns no transport, clock, DPoP key, client-authentication key,
assertion signer, browser, callback listener, durable transaction, token
exchange, session, XRPC, or Streams state.

## Public API

```forth
AT-OAUTH-PAR-WORKSPACE-SIZE  \ 14832 bytes

AT-OAUTH-PAR-WORKSPACE-CLEAR
  ( workspace -- status )

AT-OAUTH-PAR-STATUS-VALID?
  ( status -- flag )

AT-OAUTH-PAR-PREPARE
  ( config profile transaction workspace -- status )

AT-OAUTH-PAR-BUILD
  ( login-a login-u assertion-a assertion-u dpop-a dpop-u
    config profile transaction post workspace -- status )

AT-OAUTH-PAR-ACCEPT
  ( post now-seconds profile transaction workspace
    -- nonce-a nonce-u status )
```

`config`, `profile`, `transaction`, `post`, and `workspace` are complete
caller-owned fixed objects. `workspace` must begin on an eight-byte boundary.
The adapter serially reuses one child region large enough for the largest of:

```forth
O2CODE-WORKSPACE-SIZE
AT-OAUTH-CLIENT-WORKSPACE-SIZE
OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE
```

The current layout is a 72-byte orchestration header followed by a
14,760-byte child. No operation state survives a completed admitted call.

## Preparing the authorization transaction

`AT-OAUTH-PAR-PREPARE` validates the configuration once through
`OAUTH2-CLIENT-CONFIG-WITH`, applies `AT-OAUTH-CLIENT-VIEW-ADMIT`, and requires
a structurally valid ready AT OAuth profile. That retains all selected-client
policy from `oauth-client.f`, including:

- an admitted AT client identifier and redirect;
- scope containing the exact `atproto` token;
- the public `none` or confidential `private_key_jwt` authentication profile;
- `ES256` for confidential client authentication; and
- DPoP-bound access-token declaration.

The operation passes the exact opaque configuration binding and the exact
issuer selected by the profile to:

```forth
O2CODE-PREPARE
```

with `O2CODE-ISSUER-REQUIRED`. `O2CODE` therefore generates fresh independent
state and S256 PKCE material, binds the immutable client selection, and later
requires the exact RFC 9207 `iss` value in the browser callback.

The transaction must be a valid nonborrowed `O2CODE` object in its `EMPTY`
phase. Entropy and checked SHA-256 failures remain distinct PAR statuses.

## Building the PAR form

Before `BUILD`, the caller configures one `OAUTH2-HTTP-POST` with the profile's
exact PAR `HTARGET` and caller-owned request, form, and response arenas. The
post must still be in `OAUTH2-HTTP-POST-STATE-CONFIGURED`; `BUILD` does not
reuse a `RESULT` owner. The copied target must have no redirect history and
must compare exactly with `AT-OAUTH-PROFILE-PAR-TARGET@`.

The transaction must remain in `O2CODE-PHASE-PREPARED`. `BUILD` borrows its
binding, issuer policy, state, and PKCE challenge through `O2CODE-WITH-PAR`.
It compares the borrowed binding byte-for-byte with
`OAUTH2-CLIENT-VIEW-BINDING@`, requires the retained issuer to match the
current ready profile exactly, and requires the retained
`O2CODE-ISSUER-REQUIRED` policy. A valid transaction prepared for a different
configuration or profile is rejected before `POST-BEGIN`.

Immediately after `POST-BEGIN`, `BUILD` copies the exact borrowed O2CODE state
into the generic post's bounded opaque correlation field. The post retains
that token through its terminal result. This is local owner metadata rather
than another protocol field; `ACCEPT` uses it to prove that the response
belongs to the exact transaction whose state and challenge were serialized.

On success the form fields are emitted in this order:

```text
client_id
response_type=code
code_challenge
code_challenge_method=S256
state
redirect_uri
scope
[client_assertion_type]
[client_assertion]
[login_hint]
```

`client_id`, `redirect_uri`, and `scope` are the exact immutable configuration
bytes. State and challenge are the exact fixed-size O2CODE borrows.

An absent login hint is exactly `(0,0)`. A present hint must be a syntactically
valid DID or AT Protocol handle. The adapter does not resolve the identifier
or prove that it names the eventual authorization subject.

### Client authentication

For `token_endpoint_auth_method=none`, the assertion span must be exactly
`(0,0)` and no assertion fields are emitted.

For `private_key_jwt`, the assertion must be a nonempty caller-owned span. The
adapter emits:

```text
client_assertion_type=
  urn:ietf:params:oauth:client-assertion-type:jwt-bearer
client_assertion=<the supplied compact assertion>
```

There is currently no generic client-assertion signer in this composition.
Assertion creation is explicitly deferred to the caller's qualified key owner.
That owner must select the client-authentication key bound by the immutable
configuration, construct the appropriate audience and temporal claims, sign
with the admitted ES256 key, and keep the assertion lifetime and replay policy
within the authorization server's requirements. This adapter borrows the
resulting bytes only for `BUILD`; it does not parse or verify the JWT.

### DPoP

The DPoP proof span is mandatory and nonempty. `BUILD` supplies it as the
`DPoP` header to `OAUTH2-HTTP-POST-SEAL` and supplies exact `(0,0)` for the
Authorization header. A successful build verifies that DPoP was included and
Authorization was not.

At this low-level raw API, DPoP proof construction remains a caller
responsibility. The proof owner must use `POST`, the exact
`OAUTH2-HTTP-POST-HTU$`, its protected DPoP key, trusted time and identifier
sources, and any authorization-server nonce required for the attempt. The
public-client composition in
[AT Protocol public PAR with durable P-256 DPoP](oauth-par-p256.md) performs
that work from the configuration-bound durable key and then invokes this
`BUILD`; confidential-client assertion composition remains separate. See also
[OAuth 2 DPoP ES256](../security/oauth2-dpop-es256.md).

`BUILD` returns with the generic post in `SEALED` state. The caller binds a
cooperative TLS port to the exact post target and uses
`OAUTH2-HTTP-POST-START` / `POLL` under its own deadline.

## Accepting a successful PAR result

`AT-OAUTH-PAR-ACCEPT` accepts only a valid retained post result satisfying all
of these conditions:

- state is `RESULT` with cleanup certain;
- the last post lifecycle status is `OAUTH2-HTTP-POST-S-OK`;
- the target still exactly matches the ready profile's PAR target and has no
  redirect history;
- DPoP was both included and actually sent;
- Authorization was neither included nor sent;
- the retained local request correlation is present and nonempty;
- the semantic outcome is `OAUTH2-HTTP-POST-O-SUCCESS`;
- detail is `OAUTH2-HTTP-POST-D-NONE`;
- HTTP status is exactly `201`;
- the validated JSON body is nonempty; and
- one valid nonempty `DPoP-Nonce` is retained.

This is stricter than merely observing a 201 status. The generic post owner has
already enforced singleton JSON media type, content-encoding, header,
body, and transport-cleanup policy.

`now-seconds` is a caller-sampled nonnegative value in the same monotonic time
domain used for the later authorization launch. The strict generic
`OAUTH2-PAR-RESPONSE-WITH` decoder supplies `request_uri` and `expires_in` to
an ephemeral callback. That callback immediately invokes:

```forth
O2CODE-ACCEPT-PAR
```

with the current profile issuer, mandatory issuer policy, and the post's
retained correlation token. The generic transaction verifies that issuer and
token against its own retained issuer and state before copying the request URI
or deriving its checked deadline. A result from another post or prepared
transaction therefore cannot consume this transaction. Success moves the
transaction to `O2CODE-PHASE-PAR-READY`.

The returned `(nonce-a, nonce-u)` is a read-only borrow from the retained HTTP
post, not from the wiped PAR decoder workspace. Success itself proves the
nonce is present. The borrow remains valid only until the post's next
`BEGIN` or `WIPE`; copy it immediately into the authorization-server nonce
owner if it is needed later.

All failures return `(0,0,status)`. Structural JSON failures leave the
transaction unchanged. A transaction phase, shape, deadline-overflow, or
other O2CODE acceptance failure is reported without retaining any ephemeral
decoded response view.

## Challenges and retry ownership

A `400` or `401` result is not accepted as PAR success. The generic post owner
may nevertheless retain a valid `DPoP-Nonce` from that response. The caller can
borrow or copy that nonce through `OAUTH2-HTTP-POST-NONCE@`, release or wipe
the old post according to its cleanup state, configure a fresh post, construct
a fresh proof, and invoke `BUILD` again. `O2CODE-WITH-PAR` is repeatable while
the transaction remains `PREPARED`.

The adapter does not hide transport or OAuth error diagnostics. Inspect the
generic post outcome, detail, HTTP status, and lower diagnostics before
releasing a rejected result.

## Memory ownership and cleanup

Public geometry checks occur before mutation. The complete PAR workspace must
not overlap any fixed input object or any nonempty login, assertion, or DPoP
span. The mutable O2CODE transaction is also required to be disjoint from the
configuration, profile, post descriptor, and input spans. Exact adjacency is
allowed.

The adapter uses the generic
`OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS` composition boundary before `BUILD`
and `ACCEPT`. It mechanically proves that every live fixed object, the
complete PAR workspace, and every nonempty BUILD source span are external to
the post descriptor and its complete request, form, and response arenas.
`OAUTH2-HTTP-POST-BEGIN` can therefore clear its arenas without erasing a
validated input or operation owner.

The adapter never wipes the caller's login hint, client assertion, DPoP proof,
configuration, profile, transaction, post, or post arenas. The generic post
owner scrubs its copied egress material on cleanup-certain terminal paths.
Callers must promptly clear their original assertion and proof storage.

Invalid public geometry and invalid immutable configuration leave the PAR
workspace unchanged. A non-ready profile is rejected before the adapter owns
the workspace. Once selected-client policy has been admitted, the complete
workspace is wiped before staging and again before return on success, policy
rejection, subordinate rejection, or caught internal throw. `ACCEPT` likewise
leaves the workspace unchanged for envelope/body preflight rejection and wipes
it on every admitted decode path.

A form or request capacity failure after `POST-BEGIN` can leave the generic
post in the lifecycle state documented by `oauth2/http-post.f`. The caller
must inspect and release that owner; this adapter does not erase its retained
diagnostics or silently reconfigure it.

Underlying config-view, O2CODE, form-writer, HTTP, and JSON operations retain
their documented process-wide non-reentrancy boundaries. One owner must
serialize access to each configuration, transaction, post, workspace, and
backing arena.

## Status model

| Status | Meaning |
|---|---|
| `AT-OAUTH-PAR-S-OK` | Operation succeeded |
| `AT-OAUTH-PAR-S-INVALID` | Invalid public argument, span shape, alignment, or time |
| `AT-OAUTH-PAR-S-CAPACITY` | A bounded generic owner or codec could not represent the input/result |
| `AT-OAUTH-PAR-S-ALIAS` | Prohibited caller-memory overlap |
| `AT-OAUTH-PAR-S-CONFIG` | Invalid or AT-policy-inadmissible client configuration |
| `AT-OAUTH-PAR-S-PROFILE` | Invalid or non-ready AT OAuth profile |
| `AT-OAUTH-PAR-S-TRANSACTION` | Invalid, busy, or wrong-phase O2CODE transaction |
| `AT-OAUTH-PAR-S-BINDING` | Transaction/configuration/profile/correlation mismatch |
| `AT-OAUTH-PAR-S-LOGIN-HINT` | Present login hint is neither a valid DID nor handle |
| `AT-OAUTH-PAR-S-AUTH` | Assertion policy failed or Authorization was observed |
| `AT-OAUTH-PAR-S-DPOP` | Mandatory DPoP inclusion/transmission policy failed |
| `AT-OAUTH-PAR-S-TARGET` | Post target differs from the selected PAR endpoint |
| `AT-OAUTH-PAR-S-POST` | Invalid post owner, lifecycle, or form/request operation |
| `AT-OAUTH-PAR-S-HTTP` | Terminal response is not the exact admitted 201 JSON success |
| `AT-OAUTH-PAR-S-RESPONSE` | Strict PAR success JSON failed schema/value validation |
| `AT-OAUTH-PAR-S-NONCE` | Mandatory successful-response DPoP nonce is absent |
| `AT-OAUTH-PAR-S-CALLBACK` | An internal subordinate callback contract failed |
| `AT-OAUTH-PAR-S-ENTROPY` | Checked state or PKCE entropy was unavailable |
| `AT-OAUTH-PAR-S-CRYPTO` | Checked PKCE cryptography failed |
| `AT-OAUTH-PAR-S-RANGE` | Caller span lies outside the admitted memory range |
| `AT-OAUTH-PAR-S-PROTECTED` | Caller span aliases protected platform storage |
| `AT-OAUTH-PAR-S-PLATFORM` | Caller-span platform qualification failed |
| `AT-OAUTH-PAR-S-INTERNAL` | An admitted invariant or unexpected operation failed |

## Authorization continuation

This adapter intentionally stops at `PAR-READY`. The durable caller should:

1. copy the returned nonce into its selected authorization-server/DPoP nonce
   owner;
2. checkpoint the nonborrowed `PAR-READY` transaction;
3. use `O2CODE-WITH-LAUNCH` to borrow the exact binding and one-shot
   `request_uri`, copy the resulting browser-launch command, and checkpoint
   the resulting `AWAITING` phase before launching it;
4. send only the PAR continuation parameters required by the authorization
   server, normally the configured `client_id` and returned `request_uri`;
5. pass the raw redirect query to `O2CODE-ACCEPT-CALLBACK`, which enforces the
   generated state and the mandatory exact issuer selected by `PREPARE`; and
6. use `O2CODE-WITH-GRANT` to copy the one-shot authorization code and PKCE
   verifier into the separately owned token request.

Browser launch, redirect listening, durable ordering, and token exchange
remain O2CODE caller continuations rather than hidden side effects of PAR
acceptance.

## Focused qualification and deferred matrices

The current vertical gate is intentionally narrow: production client/profile
policy, real O2CODE state and PKCE generation, real form and HTTP request
serialization, a deterministic cooperative fake server returning one exact
201 JSON result plus `DPoP-Nonce`, strict PAR decoding, exact issuer and
correlation continuity, and one representative preflight/cleanup failure.

The following are recorded non-gating follow-up work rather than implied
coverage: the confidential `private_key_jwt` assertion path; the full
login-hint matrix; 400/401 DPoP nonce retry orchestration; broad malformed
response, media, header, capacity, alias, protected-span, and canary
cross-products; live TLS and browser integration; and durable restart. Direct
public-client composition of the retained P-256 key owner into proof
generation is now covered by the focused
[durable P-256 PAR composition](oauth-par-p256.md) gate. The remaining items
stay required at their production acceptance boundaries.
