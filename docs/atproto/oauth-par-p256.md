# AT Protocol public PAR with durable P-256 DPoP

`akashic/atproto/oauth-par-p256.f` is the state-free public-client composition
for constructing one AT Protocol pushed authorization request with the DPoP
identity retained by an immutable OAuth client configuration.

The module is deliberately narrow:

- `security/oauth2/key-p256.f` remains the provider-neutral owner of durable
  credential-vault records, configuration bindings, private-key confinement,
  and generic DPoP proof construction;
- `atproto/oauth-par.f` remains the raw AT PAR/PKCE form and successful-result
  policy adapter; and
- this wrapper applies the AT public-client policy that joins those two
  boundaries and configures the generic form POST.

The wrapper owns no credential-vault implementation, cryptographic primitive,
clock, entropy source, transport port, TLS connection, deadline, browser,
nonce cache, automatic retry, authorization response, token exchange,
session, XRPC, repository, or Streams state.

## Public API and geometry

The implementation exposes one caller-filled input descriptor and one
caller-owned operation workspace. The exact public words and descriptor
fields are:

```forth
AT-OAUTH-PAR-P256-INPUT-SIZE  \ 128 bytes

AT-OAUTH-PAR-P256-I.LOGIN-A
AT-OAUTH-PAR-P256-I.LOGIN-U
AT-OAUTH-PAR-P256-I.NONCE-A
AT-OAUTH-PAR-P256-I.NONCE-U
AT-OAUTH-PAR-P256-I.IAT
AT-OAUTH-PAR-P256-I.VAULT
AT-OAUTH-PAR-P256-I.CONFIG
AT-OAUTH-PAR-P256-I.PROFILE
AT-OAUTH-PAR-P256-I.TRANSACTION
AT-OAUTH-PAR-P256-I.POST
AT-OAUTH-PAR-P256-I.REQUEST-A
AT-OAUTH-PAR-P256-I.REQUEST-CAP
AT-OAUTH-PAR-P256-I.FORM-A
AT-OAUTH-PAR-P256-I.FORM-CAP
AT-OAUTH-PAR-P256-I.RESPONSE-A
AT-OAUTH-PAR-P256-I.RESPONSE-CAP

AT-OAUTH-PAR-P256-INPUT-CLEAR
  ( input -- status )

AT-OAUTH-PAR-P256-WORKSPACE-SIZE  \ symbolically derived

AT-OAUTH-PAR-P256-WORKSPACE-CLEAR
  ( workspace -- status )

AT-OAUTH-PAR-P256-BUILD
  ( input workspace -- status )
```

All capacities remain represented by their exported symbolic words. The proof
arena is derived from `OAUTH2-DPOP-ES256-MAX-PROOF-BYTES`, and the serial child
region is derived from the largest subordinate workspace used by client
admission, durable P-256 proof construction, and raw AT PAR composition.
Callers must allocate the complete advertised input and workspace objects;
they must not depend on private layout offsets or current numeric sizes.

The workspace contains one proof-length cell, a complete 128-byte input
snapshot, one `OAUTH2-P256-KEY-BINDING-SIZE` binding snapshot, one
`OAUTH2-P256-KEY-DPOP-INPUT-SIZE` descriptor, one
`OAUTH2-DPOP-ES256-MAX-PROOF-BYTES` proof arena, alignment padding, and a
serial child sized as:

```forth
AT-OAUTH-CLIENT-WORKSPACE-SIZE
OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE MAX
AT-OAUTH-PAR-WORKSPACE-SIZE MAX
```

The caller supplies:

- one optional login hint using canonical `(0,0)` absence;
- one optional authorization-server DPoP nonce using canonical `(0,0)`
  absence;
- one trusted nonnegative `iat`;
- the live credential vault;
- one immutable client configuration, ready AT OAuth profile, prepared O2CODE
  transaction, and generic HTTP POST owner;
- and bounded request, form, and response arenas for that POST.

The descriptor, workspace, vault, configuration, profile, transaction, and
POST are complete eight-byte-aligned fixed objects. Request, form, and
response capacities must each be positive; login and nonce are the only
optional byte spans. The descriptor is snapshotted after complete geometry
admission. The caller must not access the lent objects or arenas concurrently,
and the immutable configuration, profile, transaction inputs, login, and
nonce must remain byte-stable for the synchronous BUILD call.

This surface is public-client specific. It does not accept or synthesize a
`private_key_jwt` client assertion.

The POST storage must be either completely zeroed or the canonical `EMPTY`
descriptor produced by `OAUTH2-HTTP-POST-WIPE`. A configured, sealed, active,
result, or cleanup descriptor is rejected with `AT-OAUTH-PAR-S-POST` before
the wrapper workspace or any caller arena changes. The wrapper never accepts
replacement arena arguments for a live owner whose retained arenas could
differ from them.

## Public-client and key binding policy

The wrapper freshly admits the configuration and profile before proof
construction. The client must satisfy the AT public-client selection policy:
`token_endpoint_auth_method=none`, no client-assertion algorithm, native
application policy, and DPoP-bound access tokens.

The configuration's exact opaque binding must be the canonical
`OAUTH2-P256-KEY-BINDING-SIZE` form with the DPoP role present and the
client-authentication role absent. The durable key owner subsequently
authenticates the selected DPoP record, role, credential generation, and RFC
7638 thumbprint against that binding. A revoked, locked, stale, corrupt, or
otherwise unusable durable identity fails the DPoP composition; the wrapper
does not fall back to another key or silently reprovision one. The compact raw
PAR status vocabulary reports these durable lifecycle failures as
`AT-OAUTH-PAR-S-DPOP`; detailed vault/key diagnostics are not exposed by this
wrapper.

The raw PAR adapter independently revalidates the same configuration/profile
policy and compares the transaction's retained binding and issuer with the
current inputs. The composition therefore does not treat the earlier client
check as a substitute for the raw adapter's authorization-transaction
provenance checks.

## POST ownership and hidden-arena admission

Unlike the lower-level raw adapter, this wrapper accepts the caller's bounded
request, form, and response arenas and configures the generic
`OAUTH2-HTTP-POST` itself. The target is the ready profile's exact normalized
PAR target.

Owning that setup closes a cross-owner geometry problem. The durable key owner
can qualify spans against the credential-vault descriptor, backing store, VFS
descriptor, and dependency-private storage, but a previously configured POST
does not publicly expose its private arena addresses to an unrelated key
owner. This wrapper has both sets of public operands before either subordinate
operation begins. It checks the POST descriptor, all three complete arenas,
the outer workspace, fixed objects, and live source spans through the vault's
external-span boundary and through the generic caller-memory/overlap
boundaries before `OAUTH2-HTTP-POST-CONFIGURE` can clear an arena or a vault
borrow can start.

The arenas remain caller-owned. Their advertised capacities are the bounds;
the wrapper adds no smaller policy limit. Insufficient bounded storage is
reported by the appropriate checked configuration, form, proof, or raw-PAR
boundary.

## Exact DPoP proof inputs

After POST configuration, the wrapper builds one
`OAUTH2-P256-KEY-DPOP-INPUT-SIZE` descriptor with:

```text
htm          POST
htu          exact OAUTH2-HTTP-POST-HTU$ value
iat          caller-supplied trusted time
nonce        caller-supplied optional authorization-server nonce
access token absent
destination internal proof staging
capacity     OAUTH2-DPOP-ES256-MAX-PROOF-BYTES
```

No access token is sent on PAR, so the proof contains no `ath`. The wrapper
does not read a clock or decide whether an old server nonce should be retried;
those are caller policies. The durable P-256 owner generates a fresh proof
identifier and signature through its generic constructor while the
authenticated private scalar remains confined to its vault borrow and
owner-controlled workspace.

Only the finished compact proof is published into wrapper staging. The wrapper
passes that exact span to the raw public PAR `BUILD` with canonical `(0,0)`
client assertion. The raw adapter copies it into the generic POST request
during `SEAL`. The wrapper then wipes the staged proof and its complete
operation workspace before returning. It never publishes a proof borrow to
the application.

On success the POST is sealed but not started. The caller still binds a
cooperative TLS port to the exact target and drives
`OAUTH2-HTTP-POST-START` / `POLL` under its own deadline. Successful-result
admission remains `AT-OAUTH-PAR-ACCEPT`; this wrapper does not consume or hide
the returned `DPoP-Nonce`.

## Cleanup and failure ownership

Complete caller geometry, pairwise ownership, and vault-external admission are
checked before the first write. Rejection at that boundary leaves the
operation workspace, POST owner, and all POST arenas unchanged. The admitted
operation then wipes and snapshots the descriptor before configuration and
profile policy checks. A rejection before POST configuration wipes the
workspace and leaves the POST owner and arenas unchanged. Every admitted
ordinary result wipes the complete wrapper workspace. A caught subordinate
throw also wipes the workspace and returns `AT-OAUTH-PAR-S-INTERNAL`; this
wrapper does not reissue it.

The proof buffer, durable-key input descriptor, copied binding, and all
subordinate scratch are inside that wiped workspace. The configuration,
profile, transaction, vault, POST descriptor, caller arenas, login hint, and
nonce remain caller-owned. Generic HTTP cleanup continues to govern proof
bytes copied into the sealed request and retained transport diagnostics.

A failure after POST configuration can leave a truthful configured or
partially advanced generic POST lifecycle according to the subordinate
operation that failed. The wrapper does not silently reset that caller-owned
owner or erase its diagnostics. The caller must inspect and release it before
reuse.

## Status values

The wrapper deliberately reuses the closed `AT-OAUTH-PAR-S-*` vocabulary and
`AT-OAUTH-PAR-STATUS-VALID?`; it defines no parallel
`AT-OAUTH-PAR-P256-S-*` set. Raw `AT-OAUTH-PAR-BUILD` results pass through
after validation. The complete vocabulary is documented in [AT Protocol OAuth
pushed authorization requests](oauth-par.md#status-model).

Composition-specific mappings are:

- invalid canonical binding shape or key-record format becomes
  `AT-OAUTH-PAR-S-BINDING`;
- key capacity, alias, entropy, crypto, range, protected-memory, and platform
  failures preserve their corresponding raw PAR classes;
- key-owner internal or callback failure becomes
  `AT-OAUTH-PAR-S-INTERNAL`;
- all other durable-key lifecycle and proof-policy failures—including absent,
  revoked, busy, locked, authentication, corruption, recovery, rollback,
  generation/thumbprint mismatch, method, `htu`, nonce, and time—become
  `AT-OAUTH-PAR-S-DPOP`;
- `CVAULT-EXTERNAL-SPAN-STATUS` intentionally reports `CVAULT-S-INVALID` for
  both malformed vault geometry and overlap with vault-owned or
  dependency-private storage, so both become `AT-OAUTH-PAR-S-INVALID`; vault
  external range/protected/platform failures preserve those classes, while a
  busy or other vault-policy failure becomes `AT-OAUTH-PAR-S-DPOP`; and
- checked configuration, AT-client, profile, and POST outcomes map to the
  corresponding raw PAR configuration, profile, post, capacity, alias,
  callback, platform-memory, or internal class.

## Focused qualification and deferred matrices

The checkpoint gate is one deterministic proof-bearing public PAR build. It
uses the exact production credential-vault and durable P-256 key-owner bodies,
including canonical binding, role/generation/thumbprint checks, private-scalar
confinement, vault-borrow cleanup, and post-borrow proof publication. The
already independently qualified subordinate P-256/JWK/DPoP cryptographic seam
is deterministic in this composed fixture so the gate can assert exact
`POST`, `htu`, trusted `iat`, optional nonce, absent token/`ath`, proof
transport, and cleanup without repeating the standalone cryptographic vector
matrix. This is not a claim of another real-cryptography proof run.

The checked runner passed its static gate and 48 sequential staged phases:
34 raw AT production-module loads, the deterministic seam plus exact vault,
key-owner, and wrapper loads, six fixture loads, setup, the focused rejection,
the proof-bearing happy path, and finish. It used one core and 128 MiB of
external machine memory, completing in 1,152,238,842 guest steps and 645.21
summed stage seconds. The largest phase used 89,889,525 steps, below the
unchanged 180,000,000-step phase ceiling.

Broad request/form/response/vault alias and canary cross-products, every
subordinate status permutation, boundary-capacity matrices, nonce syntax and
400/401 challenge/retry combinations, repeated real-cryptography vectors,
live TLS, browser integration, and durable restart are recorded non-gating
follow-up work. Authorization-server nonce ownership and retry policy belong
to the DPoP-aware token/nonce continuation rather than hidden state in this
wrapper.

## Authorization continuation

After transport completion, callers use `AT-OAUTH-PAR-ACCEPT` exactly as
documented by [AT Protocol OAuth pushed authorization
requests](oauth-par.md). They copy the returned nonce into their explicit
authorization-server nonce owner, checkpoint the `PAR-READY` transaction, and
continue through browser launch and redirect acceptance. The next SR4
boundary composes that authorization response and then the DPoP-aware token
request; this module deliberately stops at the sealed public PAR request.
