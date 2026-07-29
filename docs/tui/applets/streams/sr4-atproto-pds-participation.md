# Streams SR4 — AT Protocol/PDS participation

**Prepared:** 2026-07-29

**Status:** active; landings 1 and 2 are complete, landing 3 is in progress

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
- `ff5bbbd` — caller-owned AT OAuth deployment binding; and
- `73ba6a3` — checked public P-256 JWK Set selection;
- `66e603f` — credential-vault external composition-span admission;
- `9e518e5` — compact SR4 security module-key normalization; and
- `2ae49bc` — durable OAuth client-authentication and DPoP P-256 key
  ownership.

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

The next closeout applies the JWK Set selector to the deployment binder's
borrowed inline `jwks` token and compares its selected public key and
thumbprint with the new local owner. That composition must also resolve and
recheck the distinct DPoP identity without nesting credential-vault borrows.
Bounded remote `jwks_uri` acquisition follows with proof of Client Identifier
and transport provenance that a structural parser cannot establish. After
that, production composition must drive PAR/PKCE and the authorization
response, perform DPoP-aware token exchange and nonce retry, admit the grant
into the durable generic session, and prove cold recovery, refresh rotation,
logout, revocation/reauthorization, cancellation, and complete cleanup.
Existing generic pieces should be composed rather than reimplemented.

## Current repository handoff

At preparation time:

```text
repository: /home/kir/Documents/Projects/fantasy-computing/akashic
branch:     main
code base:  2ae49bc (Add durable OAuth P-256 key ownership)
record:     this handoff is committed immediately after that code base
upstream:   origin/main at 66e603f
ahead:      3 commits after committing this record
tests:      no test process running
```

There is no current SR4-owned uncommitted work. The latest SR4 commits are:

```text
66e603f Expose credential-vault composition span admission
9e518e5 Normalize SR4 security module keys
2ae49bc Add durable OAuth P-256 key ownership
```

`2ae49bc` added `OAUTH2-P256-KEY-PROVISION-*`,
`OAUTH2-P256-KEY-SLOT-LOAD-*`, and `OAUTH2-P256-KEY-WITH-*` over a
caller-owned 17,879-byte workspace. Its canonical 192-byte binding fits the
immutable generic client configuration, retains no private scalar, pins each
role to one credential RID/generation/thumbprint, snapshots caller identity
before durable access, and invokes application code only after the exact
vault borrow has returned and wiped. The deployment binder still does not
invoke this owner or the JWK Set selector; their AT-layer composition is now
the next production boundary.

The following files are preserved unrelated user/old-L13 work. Do not stage,
restore, rewrite, or delete them as part of SR4:

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

1. Read `AGENTS.md`, this record,
   `docs/atproto/oauth-deployment.md`,
   `docs/security/oauth2-client-metadata.md`, and
   `docs/security/jose-jwk-p256.md`, and
   `docs/security/jose-jwk-set-p256.md`. Treat `ff5bbbd` as local structural
   and semantic deployment admission and `73ba6a3` as checked public-set
   selection; neither proves transport provenance or private-key possession.
2. Apply the checked set boundary to inline `jwks` and bounded
   `jwks_uri` bodies. Resolve the configuration's opaque binding through the
   durable private-key owner, compare the recovered public identity or RFC
   7638 thumbprint with the selected published key, and keep the
   client-authentication and per-session DPoP key identities distinct.
3. Build the bounded HTTP-resource acquisition adapter around
   `AT-OAUTH-DEPLOYMENT-WITH`. Require exact requested/effective target
   equality, status 200, zero redirects, accepted JSON media type, response
   bounds, HTTPS hostname verification, public-address/SSRF admission,
   deadlines, and truthful lease cleanup for both the Client Identifier and
   `jwks_uri`.
4. Qualify the deployment/key-owner composition and acquisition with cheap
   static gates first, then sequential deterministic fixtures. Preserve exact
   preflight contents, borrowed-view lifetimes, source immutability, workspace
   canaries, cleanup, and explicit error precedence.
5. Close landing 3 with production PAR/PKCE, authorization-response,
   DPoP/token/nonce, durable install/recovery/refresh/logout, cancellation, and
   reauthorization composition. Do not begin XRPC, repository/blob,
   subscription, and Streams wiring simultaneously.
6. Return for a landing-boundary status report, then begin landing 4 by
   replacing—not wrapping—the global XRPC/session/repository prototypes.

No live credential, account, public client metadata deployment, redirect
registration, or user secret is needed for the next actions. Ask for those
only when optional live-account qualification becomes actionable.
