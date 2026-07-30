# AT Protocol token requests with durable P-256 DPoP

`akashic/atproto/oauth-token-p256.f` is the state-free public-client
composition for constructing one proof-bearing AT Protocol authorization-code
token request from the DPoP identity retained by an immutable OAuth client
configuration.

The module is deliberately narrow:

- `security/oauth2/key-p256.f` remains the provider-neutral owner of durable
  credential-vault records, configuration bindings, private-key confinement,
  and generic DPoP proof construction;
- `security/oauth2/dpop-nonce.f` remains the provider-neutral, issuer-bound
  authorization-server nonce owner;
- `atproto/oauth-token.f` remains the raw protected token-request, form, retry,
  response, and initial-grant policy adapter; and
- this wrapper joins those boundaries for one AT public-client request
  attempt and configures its fresh generic form POST.

The wrapper owns no credential-vault implementation, cryptographic primitive,
clock, entropy source, transport port, TLS connection, deadline, automatic
retry, response acceptance, token/session persistence, refresh, logout,
confidential-client authentication, XRPC, repository, or Streams state.

## Public API and geometry

The implementation exposes one caller-filled input descriptor and one
caller-owned operation workspace:

```forth
AT-OAUTH-TOKEN-P256-INPUT-SIZE  \ symbolically derived

AT-OAUTH-TOKEN-P256-I.IAT
AT-OAUTH-TOKEN-P256-I.VAULT
AT-OAUTH-TOKEN-P256-I.CONFIG
AT-OAUTH-TOKEN-P256-I.PROFILE
AT-OAUTH-TOKEN-P256-I.TOKEN-REQUEST
AT-OAUTH-TOKEN-P256-I.NONCE-OWNER
AT-OAUTH-TOKEN-P256-I.POST
AT-OAUTH-TOKEN-P256-I.REQUEST-A
AT-OAUTH-TOKEN-P256-I.REQUEST-CAP
AT-OAUTH-TOKEN-P256-I.FORM-A
AT-OAUTH-TOKEN-P256-I.FORM-CAP
AT-OAUTH-TOKEN-P256-I.RESPONSE-A
AT-OAUTH-TOKEN-P256-I.RESPONSE-CAP

AT-OAUTH-TOKEN-P256-INPUT-CLEAR
  ( input -- status )

AT-OAUTH-TOKEN-P256-WORKSPACE-SIZE  \ symbolically derived

AT-OAUTH-TOKEN-P256-WORKSPACE-CLEAR
  ( workspace -- status )

AT-OAUTH-TOKEN-P256-BUILD
  ( input workspace -- status )
```

All capacities remain represented by exported symbolic words. The proof arena
is derived from `OAUTH2-DPOP-ES256-MAX-PROOF-BYTES`, and the serial child
region is derived from the largest subordinate workspace used by AT client
admission, durable P-256 proof construction, and raw AT token construction:

```forth
AT-OAUTH-CLIENT-WORKSPACE-SIZE
OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE MAX
AT-OAUTH-TOKEN-WORKSPACE-SIZE MAX
```

The wrapper workspace also contains one proof-length cell, a complete input
snapshot, one `OAUTH2-P256-KEY-BINDING-SIZE` binding snapshot, one
`OAUTH2-P256-KEY-DPOP-INPUT-SIZE` descriptor, the proof arena, and alignment
padding. Callers must allocate the complete advertised objects and must not
depend on private offsets or current numeric sizes.

The caller supplies:

- a trusted nonnegative DPoP `iat`;
- the live credential vault;
- one immutable public-client configuration and ready AT OAuth profile;
- one prepared `O2TREQ` in `READY` or `RETRY-READY`;
- the initialized authorization-server nonce owner bound to the profile's
  exact issuer;
- one fresh generic HTTP POST owner; and
- bounded request, form, and response arenas for that POST.

The input, workspace, vault, configuration, profile, token request, nonce
owner, and POST are complete eight-byte-aligned fixed objects. Each arena
capacity must be positive. The descriptor is snapshotted after complete
geometry admission. One caller must serialize access to all mutable owners,
and all supplied objects and arenas must remain stable for the synchronous
BUILD call.

This surface is public-client specific. It neither accepts nor synthesizes a
`private_key_jwt` client assertion.

## Fresh POST ownership per attempt

The supplied POST must be either completely zeroed or the canonical `EMPTY`
descriptor produced by `OAUTH2-HTTP-POST-WIPE`. A configured, sealed, active,
result, or cleanup descriptor is rejected with `AT-OAUTH-TOKEN-S-POST` before
the wrapper workspace or caller arenas change.

Every first request and every authorized retry is a distinct attempt. A retry
must receive a different fresh POST owner and arenas that are not still owned
by the retained first-attempt POST. The wrapper cannot discover some other
POST object that the caller omitted from its descriptor, so this cross-attempt
ownership rule remains a caller obligation. It preserves the first challenge
as evidence and avoids resetting diagnostic state in place.

Before any write, the wrapper qualifies every named fixed object and arena,
checks their direct ownership geometry, and admits every external span through
the credential vault. After configuring the fresh POST, it re-admits the
vault, configuration, profile, protected token request, nonce owner, and
complete wrapper workspace through the POST owner's external-span boundary.
The workspace admission covers its snapshot, copied binding, proof input,
proof destination, and subordinate scratch. The wrapper adds no smaller limit
to the caller's bounded arenas.

## Public-client and durable-key policy

The wrapper freshly borrows and admits the immutable configuration before
opening the nonce loan. The selected client must satisfy normal AT client
policy and additionally have:

- `token_endpoint_auth_method` exactly `none`;
- no client-authentication algorithm;
- DPoP-bound access tokens required; and
- one canonical `OAUTH2-P256-KEY-BINDING-SIZE` binding whose DPoP role is
  present and client-authentication role is absent.

The durable key owner authenticates the selected DPoP record, role, credential
generation, and RFC 7638 thumbprint against that copied binding. A missing,
revoked, locked, stale, corrupt, or otherwise unusable key fails the request;
the wrapper does not choose a fallback identity or silently reprovision one.

The raw token adapter independently re-admits the same configuration/profile
pair and the protected request's copied binding, issuer, token `htu`, and
attempt phase. The composition therefore does not substitute its early client
check for the raw adapter's provenance checks.

## Issuer-bound nonce loan and exact proof

The ready profile's exact issuer is passed to
`OAUTH2-DPOP-NONCE-WITH`. A malformed owner, busy owner, or exact issuer
mismatch fails before POST configuration. The guarded callback receives the
current nonempty nonce and keeps its borrow active while it:

1. configures the fresh POST for the profile's exact normalized token target;
2. re-admits external ownership through that configured POST;
3. constructs and signs one fresh durable-key DPoP proof; and
4. delegates protected form construction to `AT-OAUTH-TOKEN-BUILD`.

The proof input is exactly:

```text
htm          POST
htu          configured POST's exact OAUTH2-HTTP-POST-HTU$ value
iat          caller-supplied trusted time
nonce        current value from the exact issuer-bound nonce owner
access token absent
destination private wrapper proof staging
capacity     OAUTH2-DPOP-ES256-MAX-PROOF-BYTES
```

An authorization-code token request has no access token, so the proof contains
no `ath`. The wrapper does not read a clock and does not decide whether to
claim a retry. The durable owner generates the proof identifier and signature
while the authenticated private scalar remains confined to its vault borrow.
Only the finished compact proof is published into wrapper-private staging.

`AT-OAUTH-TOKEN-BUILD` copies that proof into the request arena while it
borrows the protected code and verifier. It constructs the public-client
authorization-code form, binds the exact authorization state as POST
correlation, seals with DPoP and canonical Authorization absence, and advances
the protected request to the appropriate awaiting phase. The wrapper never
publishes the nonce or proof borrow to application code.

On success, the POST is sealed but not started. The caller binds a cooperative
TLS transport to the exact target and drives
`OAUTH2-HTTP-POST-START` / `OAUTH2-HTTP-POST-POLL` under its own deadline.
Nonce-challenge and successful-response acceptance remain the raw
`oauth-token.f` operations; this wrapper does not hide their evidence or
automate the sole retry.

## Cleanup and failure ownership

Complete caller geometry and vault exclusion are checked before the first
write. Rejection at that boundary leaves the wrapper workspace, POST, and all
POST arenas unchanged. The admitted operation then wipes and snapshots the
descriptor before client admission and the nonce loan.

Every admitted ordinary result wipes the complete wrapper workspace. A throw
also wipes it: the outer wrapper catch reports `AT-OAUTH-TOKEN-S-INTERNAL`,
while a throw inside the guarded nonce callback is first contained by the
nonce owner and reports `AT-OAUTH-TOKEN-S-CALLBACK`. The staged DPoP proof,
DPoP descriptor, copied binding, descriptor snapshot, and child workspace are
therefore removed on every admitted exit. The nonce owner always releases its
borrow through its own guarded callback boundary.

A failure after POST configuration can leave a truthful configured or
partially advanced POST lifecycle according to the subordinate operation that
failed. The wrapper does not reset that caller-owned owner or erase its
diagnostics. The caller must inspect and release it before disposal. The
configuration, profile, vault, protected token request, nonce owner, POST, and
arenas otherwise remain owned by their respective callers and modules.

## Status model

The wrapper reuses the closed `AT-OAUTH-TOKEN-S-*` vocabulary and
`AT-OAUTH-TOKEN-STATUS-VALID?`; it defines no parallel P-256 status set. Raw
`AT-OAUTH-TOKEN-BUILD` results pass through after validation.

Composition-specific mappings are:

- malformed canonical binding shape becomes `AT-OAUTH-TOKEN-S-BINDING`;
- key capacity, alias, range, protected-memory, and platform failures preserve
  their corresponding token classes;
- key-owner internal or callback failure becomes
  `AT-OAUTH-TOKEN-S-INTERNAL`;
- all other durable-key lifecycle, entropy, cryptographic, method, `htu`,
  nonce, and time failures become `AT-OAUTH-TOKEN-S-DPOP`;
- nonce-owner capacity, alias, callback, range, protected-memory, and platform
  categories preserve their token equivalents, while its binding, state,
  busy, generation, and other policy failures become
  `AT-OAUTH-TOKEN-S-NONCE`;
- `CVAULT-EXTERNAL-SPAN-STATUS` intentionally reports `CVAULT-S-INVALID` for
  malformed geometry and overlap with vault-owned/private storage, so both
  become `AT-OAUTH-TOKEN-S-INVALID`; and
- checked configuration, AT client, profile, and POST outcomes map to the
  corresponding token configuration, profile, POST, capacity, alias,
  callback, caller-memory, or internal class.

This checkpoint intentionally adds no broad retry or response edge-case
matrix. Focused qualification should cover one exact-issuer, proof-bearing
public-client build and record broader challenge, persistence, and recovery
coverage as remaining landing work.
