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
- `6a5f176` — AT OAuth client-selection policy; and
- `b1bb0ad` — generic single-validation OAuth client views.

These commits do not close landing 3. The remaining closeout is the
production composition that binds the selected client deployment to its
metadata and keys, drives PAR/PKCE and the authorization response, performs
DPoP-aware token exchange and nonce retry, admits the grant into the durable
generic session, and proves cold recovery, refresh rotation, logout,
revocation/reauthorization, cancellation, and complete cleanup. Existing
generic pieces should be composed rather than reimplemented.

## Current repository handoff

At preparation time:

```text
repository: /home/kir/Documents/Projects/fantasy-computing/akashic
branch:     main
code base:  b1bb0ad (Expose single-validation OAuth client views)
record:     this handoff is committed immediately after that code base
upstream:   origin/main at c47e829
ahead:      3 commits after committing this record
tests:      no test process running
```

The current SR4-owned uncommitted work is:

```text
 M akashic/atproto/oauth-client.f
 M docs/atproto/oauth-client.md
 M local_testing/at-oauth-client-test.f
 M local_testing/test_at_oauth_client.py
```

That change migrates the AT client-policy adapter to
`OAUTH2-CLIENT-CONFIG-WITH`, so the immutable 11,072-byte generic
configuration is validated once and callback-scoped view accessors supply the
selected fields. It removes repeated whole-record scans from one admission
and reduces redundant full-input copies in the fixture while retaining
representative success, rejection, preflight, and thrown-path immutability
checks.

One semantic difference must be reviewed deliberately before committing the
adapter: when both inputs are bad, the current diff checks a non-ready AT
OAuth profile before full generic configuration validation, so `PROFILE`
precedes `CONFIG`. Do not let that precedence change land merely as an
accidental consequence of the scan optimization. The current source also
needs a final stack/cleanup review around `_ATOC-ADMIT-OP` and
`_ATOC-WITH-CONFIG`.

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
- Static checks for the current AT adapter migration have passed, and
  `git diff --check` is clean. The optimized linked AT lifecycle has not yet
  been rerun, so no runtime reduction or final pass is claimed.

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

1. Read `AGENTS.md`, this record, and the current four-file AT adapter diff.
   Confirm stack and wipe behavior and decide the dual-invalid
   `CONFIG`/`PROFILE` precedence explicitly.
2. Run only the cheap static gate first:

   ```text
   python local_testing/test_at_oauth_client.py --static-only
   ```

3. Profile or otherwise inspect stage costs before launching the full checked-in
   lifecycle. Keep the native C++ backend. Treat guest Forth JIT experiments
   or linked/prebuilt image work as separately qualified harness changes, not
   as production AT OAuth work.
4. Run the optimized AT lifecycle sequentially with resource monitoring. If
   it passes, commit only the four SR4-owned adapter files with an informative
   multi-paragraph message recording exact steps, time, memory, and swap
   evidence.
5. Close landing 3 with the missing production authorization/session
   composition and deterministic recovery evidence. Do not begin XRPC,
   repository/blob, subscription, and Streams wiring simultaneously.
6. Return for a landing-boundary status report, then begin landing 4 by
   replacing—not wrapping—the global XRPC/session/repository prototypes.

No live credential, account, public client metadata deployment, redirect
registration, or user secret is needed for the next actions. Ask for those
only when optional live-account qualification becomes actionable.
