# Streams SR4 — AT Protocol/PDS participation

**Prepared:** 2026-07-29; updated 2026-07-30

**Status:** active; landings 1 and 2 are complete, landing 3 is in progress;
the interim public-AT-plus-syndication Streams vertical is wired and awaiting
its combined live witness

**Continuation authority:**
[Streams architectural reset handoff](../../../../../STREAMS_ARCHITECTURAL_RESET_HANDOFF.md)

This is the tracked continuation record for SR4. It records the settled
architecture, landing sequence, completed evidence, current dirty work, and
the next safe actions. A fresh implementation session should read this file
before interpreting the older `atproto/xrpc.f`, `atproto/session.f`,
`atproto/repo.f`, or rejected Streams L13 code as the target architecture.

## Fixed decisions

1. OAuth is generic Akashic infrastructure. Provider-neutral OAuth, JOSE,
   credential, and session mechanisms belong under `akashic/security/` (with
   neutral HTTP encoding/transport helpers under `akashic/net/`). They must
   not depend on AT Protocol or Streams.
2. General client-side AT Protocol/PDS participation belongs under
   `akashic/atproto/`. That layer applies AT identity, OAuth, XRPC, repository,
   blob, sync, and subscription policy over the generic libraries.
3. Streams owns only configured AT Protocol connector instances and their
   event, queue, retry, cursor, cleanup, and delivery composition. General
   OAuth and AT Protocol libraries must remain usable without Streams.
4. The raw AT Protocol sync/subscription stream is normative. Jetstream is a
   separately qualified convenience adapter over that model, not the core
   event or durability contract.
5. The repository is unreleased. Replace the process-global prototype
   `xrpc.f`, `session.f`, and `repo.f` surfaces directly with caller-owned
   production contracts, port their callers/tests/docs in the same landing,
   and remove displaced implementations. Do not add `v2`, compatibility
   aliases, dual implementations, or a deprecation ladder.
6. Durable credentials are referenced by opaque RIDs resolved by the generic
   credential-vault/session owner. Sessions are designed to survive reboot
   when their credential root and retained records are available. Revocation,
   lost recovery material, an unusable refresh grant, or a failed binding
   check must become truthful reauthorization rather than credential
   resurrection.
7. Deterministic fake-PDS qualification is required and must cover exact
   protocol, restart, retry, cancellation, corruption, cleanup, and
   indeterminate-effect behavior. Optional live-account evidence is useful but
   does not replace deterministic qualification. A live witness will require
   the user to provide or authorize an account, endpoint, client deployment,
   and credential handoff when that capstone is ready; no such input is needed
   for the current implementation work.
8. SR4 should use the machine's existing cryptographic facilities through the
   generic checked security libraries. AES, entropy, P-256/ECDSA, JWS, DPoP,
   HMAC, sealing, and credential ownership were built as neutral components;
   AT Protocol must compose them rather than duplicate them. RTL changes and
   new chip design are outside this phase.
9. The SR4 output acceptance target is a generic repository/blob operation.
   Bluesky post and reply behavior are adapters above that primitive and are
   not the definition of a production AT Protocol write.

## Six-landings ledger

A landing is a coherent review boundary and may contain several independently
useful commits. Meaningful generic-library or protocol milestones should be
committed when qualified instead of accumulating until the landing closes.

| Landing | Scope | State |
| --- | --- | --- |
| 1 | Generic checked crypto, JOSE, OAuth transactions/token handling, durable credential vault, and reboot-capable provider-neutral session ownership | Complete |
| 2 | Production AT syntax, DID documents, handle/DID/PDS discovery, generic DNS/HTTPS composition, and shared network ownership | Complete |
| 3 | AT OAuth discovery, client deployment selection, authorization/token composition, durable session install/recovery/refresh/logout | In progress |
| 4 | Caller-owned XRPC, structured protocol errors, pagination/rate/retry evidence, repository operations, blob upload/reference, and atomic/batch writes; hard-replace the old global APIs | Not started |
| 5 | Raw sync/repository export and subscription input, durable cursors, reconnect/cancellation/backpressure, then a Jetstream adapter | Not started |
| 6 | Streams ingress/egress connectors over SR2/SR3, cold-restart qualification, generic record/blob output, and deterministic fake-PDS capstone; optional live evidence afterward | Not started |

Landing 1 is represented by the production security/OAuth sequence beginning
at `f6bfec4` and reaching the durable generic session qualification at
`46cf857`, with later generic additions where demanded by AT composition.
Landing 2 begins with the identifier replacement at `601c322` and reaches
shared KDOS network ownership at `b5729e1`.

Landing 3 currently includes:

- `e5cd4a4` — generic OAuth protected-resource metadata;
- `caf50fb` — AT identity-to-OAuth discovery profile;
- `561d5d0` — AT OAuth discovery over generic HTTP resources;
- `e3d43c7` — AT token-grant admission against a ready profile;
- `c47e829` — immutable generic OAuth client configurations;
- `6a5f176` — AT OAuth client-selection policy;
- `b1bb0ad` — generic single-validation OAuth client views;
- `3cedab0` — single-validation AT OAuth client selection;
- `a88a655` — structural OAuth Client ID Metadata Document parsing;
- `ff5bbbd` — caller-owned AT OAuth deployment binding;
- `73ba6a3` — checked public P-256 JWK Set selection;
- `66e603f` — credential-vault external composition-span admission;
- `9e518e5` — compact SR4 security module-key normalization;
- `2ae49bc` — durable OAuth client-authentication and DPoP P-256 key
  ownership;
- `5ea452f` — confidential inline AT OAuth deployment/key composition;
- `79c2c03` — retained Client Identifier Metadata provenance for the inline
  deployment;
- `bcb04b4` — provider-neutral published P-256 key ownership extracted from
  the AT inline composition;
- `18d5e72` — retained two-resource provenance and remote `jwks_uri`
  composition over that generic owner;
- `0194dc0` — provider-neutral durable P-256 DPoP proof construction;
- `2f5c887` — provider-neutral POST correlation and authorization-transaction
  PAR provenance;
- `e992c5e` — focused raw AT public-client PAR/PKCE composition through
  strict successful-response acceptance;
- `d302ccb` — configuration-bound durable P-256 proof composition for public
  AT PAR;
- `c389e2c` — provenance-bound AT browser authorization through strict
  generic callback acceptance and the one-shot grant loan; and
- `2000c30` — issuer, issuer-policy, state, binding, code, and verifier
  provenance carried together through that terminal grant loan.

These commits do not close landing 3. `ff5bbbd` completes the local
AT-specific deployment binder: one validated immutable client configuration,
one ready AT OAuth profile, and one structural Client ID Metadata Document are
bound under a single callback-scoped view. The binder enforces byte-exact
client identity, application defaults, exact grant and response sets,
selected and all-declared redirects, scope subsets, explicit authentication,
ES256, DPoP, and inline-versus-remote key-source policy.

`73ba6a3` completes the generic checked JWK Set boundary. It validates the
complete bounded set, rejects private, symmetric, certificate-linked, and
uninterpreted time/revocation metadata, enforces the public ES256 profile,
selects one globally unique decoded `kid`, and publishes the public key plus
RFC 7638 thumbprint from caller-owned scratch.

`66e603f` gives higher-level owners a checked way to reject caller spans that
alias a live credential vault or any of its private dependencies before a
borrow begins. `2ae49bc` uses that boundary to provision role-bound P-256
records, publish canonical RID/generation/thumbprint slots, reconstruct those
slots after reboot, and resolve copied public identity only after the
credential-vault borrow has ended. Client-authentication and DPoP keys have
distinct kinds and authenticated roles; their binding requires distinct RIDs
and RFC 7638 thumbprints.

`5ea452f` closes the local confidential inline-key boundary. Its state-free
wrapper admits the complete outer workspace and every caller input before the
first write, requires the exact two-role durable binding, selects the client
key from the deployment binder's borrowed inline `jwks`, compares both the
public point and RFC 7638 thumbprint with authenticated local ownership, then
resolves the distinct DPoP identity through a completed second owner call.
The final callback runs only after both vault borrows have returned and
retains no private scalar or process-global operation state.

`79c2c03` closes the retained-HTTP-resource path for the Client
Identifier Metadata Document. `AT-OAUTH-INLINE-HRES-WITH` binds the configured
`client_id` to exact requested and effective targets, status 200, zero
redirects, accepted JSON media, complete response-storage ownership, and the
existing confidential inline composition. The shared state-free HRES policy
now lives in `atproto/oauth-hres.f`; the profile and inline adapters consume it
without moving generic transport ownership into AT-specific code.

`bcb04b4` moves checked published-key selection, durable
client-authentication ownership, sequential DPoP ownership, public-identity
comparison, and final callback containment into the provider-neutral
`security/oauth2/published-key-p256.f` module. The AT inline composition now
retains only deployment and inline-source policy before delegating to that
generic owner. Its public status/API and 111,928-byte workspace remain stable;
the reusable 58,056-byte key owner is shared by both AT key-source paths
without duplicating selector or vault logic.

`18d5e72` closes the AT-side retained-result boundary for remote
`jwks_uri`. `AT-OAUTH-REMOTE-HRES-JWKS-TARGET!` transactionally exports a
normalized HTTPS target from exact retained Client Identifier Metadata, and
`AT-OAUTH-REMOTE-HRES-WITH` freshly reparses that metadata before binding a
second exact retained JSON result to both requested and effective targets.
Only remote-only `private_key_jwt` metadata is admitted; there is no fallback
to inline `jwks`. The used set, configuration binding, checked client key,
durable local public identity, and distinct DPoP identity are delegated to
the generic published-P256 owner.

`0194dc0` adds proof construction to the provider-neutral durable P-256 key
owner. The operation authenticates the exact DPoP slot and generation, keeps
the private scalar and proof staging inside its exclusive workspace, releases
the vault borrow, then publishes the compact proof to caller-owned storage
under complete cleanup and throw preservation.

`2f5c887` gives the generic HTTP POST owner a bounded opaque correlation slot
and a public way for composition code to qualify storage against its complete
descriptor and request/form/response arenas. O2CODE now loans its retained
issuer policy with state and challenge, and accepts a PAR result only when the
returned issuer policy and constant-time correlation match the still-prepared
transaction before mutation.

`e992c5e` adds the state-free `atproto/oauth-par.f` policy adapter. Its public
path prepares O2CODE from one admitted immutable AT client and ready profile,
serializes exact AT PAR fields into the generic POST owner, retains the
outgoing state as local request provenance, accepts only an exact terminal
201 JSON result with a DPoP nonce, and moves the same transaction to
`PAR-READY`. Its focused vertical uses real production entropy, PKCE, form,
HTTP, parser, profile, client, transaction, and response-decoder code; only
the deterministic server bytes and the then-opaque compact DPoP proof are
fixture inputs.

`d302ccb` adds the state-free public-client composition in
`atproto/oauth-par-p256.f`. It revalidates one admitted public AT client,
requires its canonical DPoP-only durable binding, configures the generic POST
against the ready profile's exact PAR target and caller-owned request, form,
and response arenas, and constructs the mandatory `POST` proof through the
provider-neutral durable P-256 owner before delegating form policy to
`atproto/oauth-par.f`. The proof uses caller-supplied trusted time, an optional
authorization-server nonce, the exact normalized post `htu`, and no access
token or `ath`. Proof staging is wiped after the raw adapter has sealed its
copy. The wrapper accepts only all-zero POST storage or the canonical `EMPTY`
owner before its first write, so a live descriptor cannot hide an old arena
outside the vault-exclusion graph. Transport, deadlines, nonce
retention/retry policy, and response acceptance remain caller-owned
continuations. The public BUILD takes one 128-byte caller descriptor and one
symbolically sized workspace whose child region is the maximum of AT-client
admission, durable DPoP proof, and raw PAR workspaces. It reuses the closed
`AT-OAUTH-PAR-S-*` vocabulary: invalid canonical key shape is `BINDING`,
selected durable-key lifecycle/proof-policy failure is `DPOP`, and capacity,
alias, entropy, crypto, and platform-memory classes remain distinct.

`c389e2c` extends the provider-neutral O2CODE launch loan with
the exact retained issuer policy and adds the state-free
`atproto/oauth-authorization.f` adapter. The generic transaction continues to
own the `PAR-READY`/`AWAITING`/`CODE-READY`/`SPENT` lifecycle, issuer and state
checking, PKCE material, and callback/grant containment. The AT-specific layer
freshly revalidates the selected immutable client and ready profile, matches
their binding and issuer inside the one-shot loan, and writes only the exact
form-encoded `client_id` and opaque `request_uri` against the profile's
authorization endpoint. Its destination honors any positive caller-provided
bound; the symbolic 19,480-byte allocation is sufficient for every admitted
input rather than a required exact capacity. An undersized destination
discovered after the loan begins is terminal because O2CODE has already
published `AWAITING` and consumed the request URI.

Browser launch, redirect-route admission, durable ordering, and token
transport remain explicit caller continuations. The focused vertical passes
the raw redirect query directly to generic `O2CODE-ACCEPT-CALLBACK` and then
uses `O2CODE-WITH-GRANT`; there is no AT-specific duplicate parser or token
owner hidden in this checkpoint.

`2000c30` completes the grant-loan provenance needed by that token
continuation. `O2CODE-WITH-GRANT` now lends the retained issuer bytes,
issuer-required policy, attempt-unique state, exact client binding, code, and
PKCE verifier together before publishing `SPENT` and wiping the transaction.
This remains provider-neutral under `security/oauth2/`; it neither sends an AT
token request nor installs a Streams session.

The immediate next boundary is the DPoP-aware token request and explicit
authorization-server nonce owner. Durable generic session installation and
cold recovery, refresh rotation, logout, revocation/reauthorization,
cancellation, and complete cleanup follow.

## Accelerated visible Streams vertical

The first visible multiprotocol slice no longer waits for all six landings.
Commit `d503a84` changes the focused Desk profile from the offline
`STREAMS-ENTRY` to `STREAMS-ONLINE-ENTRY`. A launched instance therefore owns
the existing production public-AT provider factory and the configured
syndication-provider seam while remaining empty until the user selects an
actor or creates a source.

The working vertical adds two qualification profiles:

- `streams-multiprotocol-composition` registers the reviewed trust
  contributions, admits one exact RSS endpoint, constructs and configures the
  production syndication provider, and constructs and configures the
  production public Bluesky provider without doing network I/O.
- `desktop-streams-vertical` supplies the same exact host policy to
  `STREAMS-ONLINE-ENTRY-WITH-CONFIGURED`. Its one Desk-hosted TAP journey
  creates and refreshes the reviewed RSS source, proves a retained observation
  is visible in Sources, refreshes a public Bluesky actor through
  `app.bsky.feed.getAuthorFeed`, proves timeline rows are visible, returns to
  Sources to prove the RSS result remains visible, and closes the instance.

This is an honest interim product vertical: real RSS over HTTPS plus real
credential-free Bluesky AppView XRPC in one Streams applet. It does not claim
authenticated PDS participation, a raw AT repository/sync connector, a
unified cross-protocol event timeline, or completion of landing 3 or landing
6. The exact-host demo authorization remains in the qualification
composition; no provider-specific trust or demo policy was moved into the
general Streams, HTTP, syndication, or AT libraries.

Current evidence for this checkpoint is deliberately narrow:

- the focused online-entry and dependency-boundary packaging checks pass;
- both new linked images build successfully;
- the no-network composition smoke reached 355,500,000 guest steps at its
  180-second wall bound without reaching autoexec or emitting guest output, so
  it is recorded as **not yet executed to its marker**, not as a pass or a
  product failure; and
- the combined TAP journey has not yet been run. The prior separate public-AT
  and configured-syndication live witnesses remain useful component evidence
  but do not substitute for the combined product witness.

The combined witness command is:

```text
python3 local_testing/akashic_tui.py smoke \
  --profile desktop-streams-vertical --nic-tap mp64tap0 \
  --max-steps 9000000000 --timeout 300
```

### Work still required after this slice

The following debt is explicit so it can be sequenced without blocking the
first visible slice:

1. **Close landing 3:** retain and update the authorization-server DPoP nonce,
   perform the exact protected token request and one authorized nonce retry,
   admit the token response, install/recover the durable generic session, and
   qualify refresh rotation, logout, revocation/reauthorization,
   cancellation, and cleanup.
2. **Build landing 4:** hard-replace the process-global `atproto/xrpc.f`,
   `atproto/session.f`, and `atproto/repo.f` prototypes with caller-owned
   XRPC, structured error, pagination/rate/retry, repository-operation, blob,
   and atomic/batch-write contracts.
3. **Build landing 5:** implement raw repository export/sync and subscription
   input, CAR/DAG-CBOR handling where required, durable cursors, reconnect,
   cancellation, backpressure, and only then the separately qualified
   Jetstream convenience adapter.
4. **Complete landing 6:** add authenticated AT ingress and generic
   record/blob egress as real Streams connector instances with event, queue,
   retry, cursor, cleanup, cold-restart, and deterministic fake-PDS
   qualification. A live-account capstone remains optional and requires
   explicit account/credential handoff.
5. **Converge the applet presentation:** project durable configured-source
   observations and AT items through a common bounded row/event view with
   truthful source attribution, ordering, search, context/thread behavior,
   and refresh state. The interim slice intentionally shows AT on Timeline and
   syndication in Sources instead of delaying the slice for that convergence.
6. **Review deferred qualification:** complete the recorded broad parser,
   alias/canary, subordinate-status, retry, corruption, cancellation, and
   cleanup matrices at the landing that claims the corresponding production
   boundary. They are documented debt, not silently covered behavior.

## Current repository handoff

At this checkpoint:

```text
repository: /home/kir/Documents/Projects/fantasy-computing/akashic
branch:     main
code base:  2000c30 grant provenance plus d503a84 online launcher composition
record:     updated with the interim multiprotocol vertical and explicit debt
upstream:   origin/main at bcb04b4
tests:      focused packaging checks pass; both new images build
pending:    composition marker and combined TAP product witness
```

The latest SR4 and vertical-acceleration commits are:

```text
2ae49bc Add durable OAuth P-256 key ownership
baa640b Advance SR4 to deployment key composition
5ea452f Compose confidential inline AT OAuth keys
79c2c03 Bind retained client metadata to inline OAuth
bcb04b4 Extract generic OAuth published P-256 ownership
18d5e72 Bind retained remote AT OAuth keys
0194dc0 Bind durable OAuth DPoP proofs to P-256 keys
2f5c887 Bind generic PAR results to initiating requests
e992c5e Compose AT OAuth pushed authorization requests
d302ccb Compose durable DPoP proofs into public AT PAR
c389e2c Bind AT browser authorization to PAR provenance
2000c30 Carry token provenance through the grant loan
d503a84 Launch focused Streams through its online composition
this checkpoint: add the reviewed multiprotocol Desk vertical
```

`2ae49bc` added `OAUTH2-P256-KEY-PROVISION-*`,
`OAUTH2-P256-KEY-SLOT-LOAD-*`, and `OAUTH2-P256-KEY-WITH-*` over a
caller-owned 17,879-byte workspace. Its canonical 192-byte binding fits the
immutable generic client configuration, retains no private scalar, pins each
role to one credential RID/generation/thumbprint, snapshots caller identity
before durable access, and invokes application code only after the exact
vault borrow has returned and wiped. The deployment binder still does not
invoke this owner or the JWK Set selector by itself.

`5ea452f` added `AT-OAUTH-INLINE-WITH` over one 111,928-byte caller-owned
workspace. It composes the deployment binder, checked P-256 JWK Set selector,
and durable client/DPoP owner for confidential inline deployments, performs
the owner calls sequentially, copies only public identity into outer scratch,
and rejects public or `jwks_uri` deployments as a separate key-source
boundary.

`79c2c03` adds the state-free shared AT OAuth HRES policy and
`AT-OAUTH-INLINE-HRES-WITH`. The adapter independently rechecks status,
redirect, requested/effective URI and JSON-media provenance, admits the
complete caller-owned response storage before any workspace write, and then
borrows the exact retained body into the existing inline deployment. It does
not own DNS, sockets, TLS, deadlines, leases, or response cleanup.

`bcb04b4` adds `OAUTH2-P256-PUBLISHED-WITH` under
`akashic/security/oauth2/` and refactors `AT-OAUTH-INLINE-WITH` to consume it.
The generic module has no AT, HTTP, token, session, XRPC, Streams, or
application-state dependency. AT remains responsible for exact Client
Metadata source selection and deployment policy; the generic owner proves
that one checked published set agrees with durable local client ownership and
then lends distinct client/DPoP public identity.

`18d5e72` adds the state-free
`akashic/atproto/oauth-remote-hres.f` adapter over one 115,336-byte
caller-owned workspace. The AT-specific layer owns only metadata/source
policy, transactional target export, and two-resource canonical provenance.
Generic HRES retains transport and response ownership, `HTARGET` retains URI
normalization, and `security/oauth2/published-key-p256.f` retains checked set
and durable P-256 ownership.

`0194dc0` extends `security/oauth2/key-p256.f` with a provider-neutral durable
DPoP proof operation. `2f5c887` extends only the generic OAuth transaction and
HTTP POST owners needed to correlate one returned PAR result with its
initiating issuer and state. Neither module depends on AT Protocol or Streams.

`e992c5e` adds `akashic/atproto/oauth-par.f`, its focused documentation, and a
staged public-client fixture. The raw adapter owns AT form and successful
response policy only; generic O2CODE retains state/PKCE/issuer lifecycle,
generic HTTP owns form serialization and transport evidence, and the generic
PAR decoder owns successful-response schema validation.

`d302ccb` adds `akashic/atproto/oauth-par-p256.f` and its focused
documentation and fixture. The wrapper owns only the AT public-client
composition: exact PAR POST setup, immutable configuration revalidation,
selection of the configuration-bound durable DPoP identity, exact proof
inputs, and prompt proof cleanup. Credential-vault, P-256 key, and generic
DPoP ownership remain under `akashic/security/oauth2/`; the raw AT form and
response policy remains in `akashic/atproto/oauth-par.f`; transport remains
with the caller.

`c389e2c` changes the generic
`security/oauth2/authorization-code.f` callback loan only by adding its
already-retained issuer bytes and policy. Exact AT endpoint, client, and
profile binding stays in the new `akashic/atproto/oauth-authorization.f`
adapter. That adapter owns no provider-neutral transaction, browser, redirect
listener, token request, nonce cache, or application state. Its focused
fixture continues the existing durable public PAR transaction through one
exact browser URI, strict generic callback acceptance, and a grant callback;
the generic and AT layers remain usable without Streams.

`2000c30` extends the same terminal loan with exact issuer, issuer policy,
state, binding, code, and verifier provenance so a protected token attempt can
retain everything it needs before O2CODE wipes the spent transaction.

The following remaining dirty paths are preserved user/old-L13 work. The
vertical touches separate, selectively staged hunks in
`local_testing/akashic_tui.py`; do not stage, restore, rewrite, or delete the
other hunks merely because that file also carries the vertical profiles:

```text
 M README.md
 M akashic/tui/applets/streams/runtime-owner.f
 M akashic/tui/applets/streams/streams.f
 M local_testing/akashic_tui.py
 M local_testing/streams-refresh-owner.f
?? local_testing/streams-cold-l13-test.f
?? local_testing/streams_l13_two_boot.py
```

## Qualification and accelerator facts

### Vertical-slice qualification policy

Until SR4 reaches actual AT OAuth/PDS integration, qualification effort is
intentionally weighted toward the shortest production-shaped vertical slice.
Each new boundary is gated now by static and compile checks, one deterministic
happy path, and the failures that protect transport provenance, security,
ownership, callback containment, and truthful cleanup. Tests remain
sequential, and checked-in resource ceilings remain authoritative.

Exhaustive edge-case matrices are not gating the next vertical step. Broad
media and parser permutations, every subordinate-status permutation, repeated
alias/canary variants, and other non-gating combinatorics may be deferred when
the focused gates establish the boundary needed by the end-to-end path. Each
deferral must be recorded beside the affected boundary rather than silently
treated as covered.

This is a sequencing decision, not a relaxation of the production contract.
Before landing 3 or the corresponding production boundary is declared closed,
the recorded deferrals must be reviewed and either qualified or explicitly
assigned to a later acceptance boundary with rationale. Deterministic fake-PDS
integration and the security, cancellation, corruption, and cleanup behavior
required by the six-landings ledger remain final acceptance requirements.

The staged MegaPad tests already use the compiled native C++ accelerator.
`MachineSession` constructs `MegapadSystem`; positive run batches reach
`_mp64_accel.SystemState.run_full_core_batch()`. Runtime inspection on this
machine reported the CPython 3.13 `_mp64_accel` shared object and
`ACCEL_AVAILABLE=True`. The earlier description of the run as
“instruction-by-instruction Python emulation” was wrong. Python orchestrates
native batches and exceptional/MMIO continuations; it is not the normal CPU
interpreter.

The guest Forth compiler JIT is a separate mechanism. KDOS enables it while
compiling KDOS and disables it at the end. The staged AT OAuth runner enters
userland and loads Akashic modules without re-enabling that JIT. Enabling it
could change compilation and guest-step cost, but it is not an emulator
backend switch and must be measured and qualified before changing the runner.
Do not claim a JIT speedup without evidence.

Completed evidence:

- The committed `6a5f176` AT client-policy lifecycle passed all staged groups
  before the current scan optimization: about 1.1909 billion guest
  instructions in 16 minutes 52 seconds, one core, 116,924 KiB peak RSS, and
  no test-attributed swaps.
- The final generic view implementation committed at `b1bb0ad` passed its
  bounded linked suite in 144,652,928 guest steps with zero test-attributed
  swaps.
- The optimized AT adapter committed at `3cedab0` passed its static gate and
  completed all 17 linked load stages, 14 contract groups, and the finish
  marker in 979,786,924 guest steps and 13 minutes 17.81 seconds. The
  monitored process reached 117,120 KiB peak RSS and incurred no
  process-attributed swaps. Host-wide `vmstat` changed by +336 `pswpin` and
  +5,205 `pswpout` pages during the run, so do not misstate that result as a
  system-wide no-swap interval.
- The generic Client ID Metadata parser committed at `a88a655` passed its
  static gate and a 480-assertion linked matrix in 366,109,694 guest steps and
  286.94 seconds, below its checked-in 500,000,000-step ceiling and the
  300-second test wall.
- The final AT client regression for `ff5bbbd` passed its static gate and all
  17 staged loads, 15 contract groups, and finish marker in 1,022,855,732
  guest steps and 871.78 summed stage seconds. The new direct borrowed-view
  group covered semantic success and rejection, invalid spans and alignment,
  capacity, aliasing, preflight ownership, full cleanup, and source
  immutability. Every phase stayed below its checked-in 180,000,000-step
  ceiling.
- The final deployment lifecycle for `ff5bbbd` passed its static gate and all
  19 staged loads, 9 contract groups, and finish marker in 1,175,466,705 guest
  steps and 998.08 summed stage seconds on one core with 128 MiB of external
  machine memory. It covered public and confidential success, exact metadata
  policies and precedence, present-empty redirects, callback corruption and
  throws, exact borrowed config/JWKS spans, input immutability, workspace
  canaries, preflight contents, and full cleanup. Its largest phase was
  authentication/DPoP/key-source policy at 136,751,108 steps, below the same
  checked-in ceiling.
- The exact source committed at `73ba6a3` passed the new JWK Set static gate,
  the existing JWK codec static gate, all 9 staged loads, 6 contract groups,
  and the finish marker in 584,366,923 guest steps and 498.30 summed stage
  seconds on one core with 128 MiB of external machine memory. It covered
  independent key/thumbprint vectors, first/middle/last and escaped-`kid`
  selection, nested JSON traps, full-set late rejection, current
  sensitive/unsupported parameter policy, decoded-`kid` ambiguity, alias and
  protected-span admission, input/output canaries, mandatory cleanup, exact
  32-key success, and 33-key capacity rejection. Every phase stayed below its
  checked-in 300,000,000-step ceiling.
- The exact credential-vault source committed at `66e603f` passed its static
  gate and 268-assertion lifecycle in 202,519,471 guest steps and 132.93
  seconds. The added cases covered complete external-span admission,
  dependency-private aliases, and a dynamic partial AES-GCM workspace
  overlap.
- The final P-256 owner source committed at `2ae49bc` passed the repository
  module-key gate, its static contract gate, all staged loads, six behavior
  groups, and the finish marker in 243,389,294 guest steps and 149.84 summed
  stage seconds on one core with 128 MiB of external machine memory. It
  covered canonical binding roles and distinctness, client and DPoP
  provisioning, reboot-style slot reconstruction, stale generation and
  thumbprint mismatch, role substitution, public callback timing, callback
  throw/stack containment, protected-span precedence, complete cleanup,
  staged-binding validation, and adversarial mutation of the caller RID after
  snapshot.
- The confidential inline composition committed at `5ea452f` passed its
  static gate, all 27 staged loads, nine behavior groups, and the finish marker
  in 1,297,257,153 guest steps and 972.60 summed stage seconds on one core with
  128 MiB of external machine memory. It covered exact inline JWK selection,
  public and remote key-source rejection, canonical binding failures,
  public-key and thumbprint mismatch, client and DPoP owner failures,
  identity distinctness, callback throw/stack containment, complete composed
  caller/vault admission, input immutability, child and outer workspace
  cleanup, and rejection-before-write preflight preservation. Its largest
  phase was callback containment at 96,802,324 steps, below the checked-in
  180,000,000-step ceiling.
- The retained Client Identifier Metadata adapter committed at `79c2c03`
  passed its static gate and the complete sequential staged lifecycle in
  1,326,867,836 guest steps and 856.64 summed stage seconds. Its focused
  adapter groups cover shared policy, one exact confidential-inline success,
  wrong target, redirect, media and HTTP-status provenance, and full
  response-storage alias preflight. The linked HRES, profile, deployment, and
  inline fixture loads also passed; their broader behavior remains supported
  by the separately recorded suites rather than being duplicated here.
- The generic published-key extraction passed both inline-consumer static
  gates. A sequential diagnostic run compiled the full 28-module graph and
  passed contracts, success, key-source, binding, mismatch, owner, and
  distinctness groups before exposing a missing nested guard around the AT
  nine-argument callback. After that guard was restored, a focused
  success-and-callback run passed in 948,770,399 guest steps and 650.25 summed
  stage seconds, and a focused rejection-before-write preflight run passed in
  877,258,595 guest steps and 533.40 summed stage seconds. Both used one core,
  128 MiB of external machine memory, and the checked-in 180,000,000-step
  phase ceiling.
- The retained remote-JWKS adapter passed its static gate, all 42 sequential
  staged loads, four focused behavior groups, and the finish marker in
  1,399,394,735 guest steps and 869.79 summed stage seconds on one core with
  128 MiB of external machine memory. The groups covered the exact shared
  HRES policy, transactional normalized-target derivation, one remote-only
  checked-key and durable-identity success, public-identity mismatch, callback
  containment, wrong metadata and JWK Set targets, inline-source rejection,
  overlapping response storage, and an unused JWK-buffer tail containing the
  outer workspace. The largest phase was the HRES fixture load at 113,934,407
  steps; the focused remote success phase used 97,927,300. Every phase stayed
  below the checked-in 180,000,000-step ceiling.
- The durable P-256 DPoP operation committed at `0194dc0` passed its focused
  exact-vault lifecycle and a separate real production-dependency compile
  gate. It covered exact role/generation pinning, private-scalar confinement,
  internal proof staging, post-borrow publication, mapped failure, and
  complete owner-workspace cleanup without duplicating the constructor's
  cryptographic vector matrix.
- The generic provenance seam committed at `2f5c887` passed both static gates.
  The focused HTTP POST runtime loaded 15 modules and passed in 240,304,263
  guest steps across load and entry; the complete authorization-code
  lifecycle passed in 191,068,273 guest steps. Both ran sequentially on one
  core with 128 MiB of external machine memory and unchanged checked-in
  ceilings.
- The raw AT PAR checkpoint committed at `e992c5e` passed its static gate and
  all 34 sequential
  production-module loads, four fixture loads, four focused runtime groups,
  and the finish marker in 858,463,933 guest steps and 489.35 summed stage
  seconds on one core with 128 MiB of external machine memory. It covers one
  real public-client PREPARE/BUILD/201-plus-nonce/ACCEPT path through
  `PAR-READY`, exact wire bytes, binding and issuer cross-wire rejection, a
  POST-arena alias canary, correlation continuity, nonce borrowing, and
  workspace/request/form cleanup. Its largest phase was the first dependency
  load at 89,641,539 steps, below the checked-in 180,000,000-step ceiling.
- The durable public PAR checkpoint passed its static gate and all 34 raw AT
  production-module loads, four composition loads (the deterministic seam,
  exact vault, exact key owner, and exact wrapper), six fixture loads, three
  focused runtime groups, and the finish marker in
  1,152,238,842 guest steps and 645.21 summed stage seconds on one core with
  128 MiB of external machine memory. Its largest phase was the first raw
  dependency at 89,889,525 steps, below the unchanged 180,000,000-step
  ceiling. The deterministic proof-bearing gate uses the exact production
  credential-vault and durable P-256 key-owner bodies, with the independently
  qualified subordinate P-256/JWK/DPoP cryptographic seam made deterministic
  for composition assertions. It covers one client-only binding rejection
  before POST mutation or vault resolution and one exact configuration-bound
  proof flowing through the sealed request, fake 201-plus-nonce response, and
  correlated `PAR-READY` transition. Exact `POST`, `htu`, trusted time,
  absent initial nonce/token/`ath`, no Authorization header, and complete
  wrapper/key/request/form cleanup were observed. The fresh-or-`EMPTY` POST
  requirement and complete arena/vault admission order are also enforced by
  the static source gate. This does not claim another real-cryptography vector
  run.
- The authorization checkpoint passed both static gates. The generic
  authorization-code linked suite loaded 12 modules and passed in 191,292,455
  guest steps and 104.79 seconds. The combined durable public AT OAuth
  vertical then passed 54 sequential phases: 34 raw production-module loads,
  five composition loads, seven fixture loads, seven focused runtime groups,
  and finish. It completed in 1,205,055,297 guest steps and 677.68 summed stage
  seconds on one core with 128 MiB of external machine memory. Its largest
  phase used 90,150,958 steps, below the unchanged 180,000,000-step ceiling.
  Starting from the exact proof-bearing PAR success, the focused authorization
  groups cover the exact `client_id`/`request_uri` browser URI, transition to
  `AWAITING`, request-URI consumption, workspace and output cleanup, one
  wrong-issuer callback preserving the genuine attempt, one exact callback to
  `CODE-READY`, and one guarded grant loan exposing the exact durable binding,
  authorization code, and valid PKCE verifier before `SPENT` and secret
  cleanup. Browser launch, redirect routing, and token transport are not
  claimed by this state-free gate.

Recorded, non-gating deferrals for this retained-HRES boundary are the broad
HRES header/outcome/media cross-product, every inline-status pass-through
permutation, and canonical-target spelling/fuzz cases beyond the focused
provenance gate. Real DNS, public-address/SSRF, authenticated TLS, deadline,
cancellation and lease-cleanup evidence is deferred to the generic
transport-owner/fake-PDS vertical slice rather than duplicated in this
state-free retained-result adapter. Review these items before declaring the
affected production boundaries finally closed.

Recorded, non-gating deferrals for the provider-neutral published-key owner
are a standalone direct-API matrix, every subordinate-status permutation, the
full protected-alias/canary/capacity cross-product, and concurrent
caller-mutation experiments. A second complete nine-group inline rerun was
also not performed after the isolated callback-bridge correction: all
unchanged groups had already passed, while patched focused runs covered the
changed success/callback path and the security-relevant preflight/cleanup
path. The remote consumer must still gate two-resource provenance and body
ownership rather than treating these deferrals as remote-source evidence.

Recorded, non-gating deferrals for the durable P-256 DPoP operation are every
subordinate-status permutation beyond the focused HTU mapping, the full
capacity/alias/protected-span cross-product, injected terminal `MOVE` faults,
and concurrent caller-mutation experiments. The focused gate covers a real
production dependency compile plus deterministic role/generation pinning,
private-key confinement, internal proof staging, post-borrow publication, and
complete owner-workspace cleanup. The standalone DPoP constructor retains its
own direct cryptographic qualification; this owner seam does not duplicate
that matrix.

Recorded, non-gating deferrals for the remote retained-result adapter are the
full HRES outcome/status/media/redirect matrix, broad canonical-URI spelling
and parser fuzz, every published-key and vault subordinate status, the full
capacity/alias/canary cross-product, and concurrent caller-mutation
experiments. The focused fixture uses two separately acquired stable
retained-result snapshots to qualify the AT adapter without duplicating the
generic transport suite; simultaneous live-resource ownership, DNS and
public-address/SSRF admission, authenticated TLS, deadlines, cancellation,
and truthful lease cleanup remain gates for the deterministic fake-PDS
transport vertical slice.

Recorded, non-gating deferrals for the raw AT PAR adapter are the confidential
`private_key_jwt` path, broad login-hint and malformed-response matrices,
400/401 DPoP nonce-retry orchestration, the full media/header/capacity/
protected-alias/canary cross-product, durable restart, and live TLS/browser
integration. Direct durable-key proof composition is no longer deferred: the
current public-client wrapper supplies it while leaving the lower-level raw
BUILD usable for other admitted AT client-authentication profiles.

Recorded, non-gating deferrals for the durable public PAR composition are
every subordinate key/vault/raw-PAR status permutation beyond the focused
security-relevant gate, broad request/form/response/vault alias and canary
cross-products, small and boundary capacity matrices, nonce syntax and
challenge/retry combinations, and repeated real-cryptography vectors. The
focused gate composes the exact production vault and key-owner bodies with an
already-qualified deterministic subordinate crypto seam; the standalone
generic DPoP constructor retains its own real cryptographic qualification.
Authorization-server nonce ownership and retry orchestration remain part of
the DPoP-aware token/nonce continuation rather than hidden state in this
state-free wrapper.

Recorded, non-gating deferrals for the AT browser-authorization boundary are
authorization endpoints with preexisting query/separator variants, broad
percent-encoding and boundary-capacity matrices, cross-wired
configuration/profile/binding and expiry matrices, and the full alias,
protected-span, canary, subordinate-status, callback-denial, and
malformed-query cross-products. The generic O2CODE suite retains its broader
parser, denial, throw, and callback stack-containment evidence rather than
duplicating it here. Live browser and redirect-route integration, durable
restart, and token transport remain later vertical gates. A too-small caller
destination is already defined as a terminal post-loan result, but the broad
capacity matrix is not claimed by the focused success gate.

The 16-minute-52-second result is a complete staged module-load and contract
qualification, not the measured latency of one OAuth admission or one network
operation. Its cost exposed repeated full-record scans and heavy fixture
construction; it does not establish that the production API is intrinsically
that slow.

All smoke, integration, linked, and persistence tests remain sequential.
Before a heavyweight rerun, inspect available memory/swap, announce the run,
keep the checked-in step ceilings, and monitor elapsed time, RSS, CPU, and swap
delta. Do not run another suite or a test subagent concurrently.

## Exact next actions

1. Run the focused `streams-multiprotocol-composition` marker and the
   `desktop-streams-vertical` TAP journey when the required execution window
   and TAP access are available. Fix only blockers to the stated two-protocol
   acceptance; record broader UI/event convergence as debt.
2. Continue landing 3 with the DPoP-aware token request and explicit
   authorization-server nonce owner. Preserve the exact
   transaction/configuration/profile/key binding and keep transport,
   deadlines, nonce challenge/retry, and durable ordering explicit.
3. Continue with durable
   install/recovery/refresh/logout, cancellation, and reauthorization
   composition, using only the focused happy path and security/ownership
   failures needed to reach one authenticated PDS read.
4. Begin landing 4 by replacing—not wrapping—the global
   XRPC/session/repository prototypes, then place the first authenticated
   caller-owned read behind an AT connector seam that the visible Streams
   applet can consume.
5. Return for a landing-boundary status report before expanding into raw sync,
   subscriptions, general writes, or the deferred cross-protocol presentation
   work.

No live credential, account, public client metadata deployment, redirect
registration, or user secret is needed for the next actions. Ask for those
only when optional live-account qualification becomes actionable.
