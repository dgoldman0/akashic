# Stage 1 implementation ledger

**Status:** implemented and qualified on the isolated `sandbox-stage1` branch;
not yet merged

The critical path is one permanent route:

```text
restricted source
        |
        v
bounded compiler -> address-free candidate -> independent verifier
                                               |
                                               v
                                      owned sealed plan
                                               |
                           sealed binding + caller-owned instance
                                               |
                                               v
                                      metered executor
```

The initial failed sequencing spent effort on profile and value digest
infrastructure before implementing this route. That uncommitted digest work is
preserved in a named stash and is not a runtime dependency.

## Landed implementation

The implementation is divided into three reviewable commits:

- `c921cc0` implements checked byte geometry, the scalar instruction model,
  address-free candidates, immutable profiles, caller-owned plans, the empty
  pure binding, and focused format/core contracts.
- `ff48eb1` implements the bounded non-evaluating compiler and the independent
  verifier.
- `222a332` implements the caller-owned resumable executor and its bounded
  lifecycle/behavior contract groups.

These are concern boundaries, not format or compatibility versions. The
project remains unreleased and no predecessor runtime is preserved.

The subsequent bounded reduction pass keeps those boundaries but removes
their duplication from the instruction loop. `STEP` still validates the
instance and continuation at its public boundary. `RUN-SLICE` now performs
that admission once, uses private O(1) sealed-plan accessors, and executes
admitted internal steps while retaining all guest-dynamic stack, frame,
branch, memory, budget, cancellation, and trap checks. A native caller racing
writes into a sealed plan or live instance during one slice is outside the
object contract; guest code has no path to either native span.

## Corrected Stage 1 boundary

Stage 1 owns:

- one immutable internal profile representation;
- one bounded, non-evaluating restricted-source compiler;
- one address-free candidate representation;
- one independent semantic verifier that publishes an owned plan seal last;
- one immutable empty binding that proves the pure plan has no imports;
- one caller-owned instance with separate operand, call, and counted-loop
  state, linear memory, limits, cancellation, trap, and output; and
- deterministic qualification of malformed input, target and stack checks,
  instruction exhaustion, cancellation, cleanup, and interleaved instances.

The retained machine surface is structured control and locals, operand-stack
operations, 64-bit integer/bit operations, checked linear memory, and the
reserved generic import-call seam. The pure profile disables that instruction
and admits no import records. Nonempty adapter dispatch and its typed
qualification are later host work on the same plan/binding boundary, not part
of proving the Forth sandbox itself. Typed value graphs likewise remain a
later ABI layer rather than intrinsic Forth-machine state.

Canonical profile text, runtime hashing, direction-specific value digests,
durable artifact lookup/cache identity, package provenance, Desk, Agent,
Context, VFS, networking, persistence, UI, credentials, and contract-specific
hardening are outside this Stage 1 gate.

This correction does not authorize a toy evaluator.  Compiler, verifier,
profile, plan, binding, and instance interfaces are the permanent interfaces;
later codecs and hosts construct or transport those objects rather than
replacing them.

## Qualification evidence

The focused gates passed sequentially:

- `sandbox-format-contracts`: 101 assertions;
- `sandbox-core-contracts`: 66 assertions;
- `test_sandbox_stage1_structure.py`: 7 tests;
- `sandbox-stage1-vm-hotloop-contracts`: 32 assertions; the identical
  64-unit spin slice fell from 75,359,091 to 1,417,407 emulator cycles,
  a 53.17x speedup and 98.12% reduction;
- `sandbox-stage1-vm-scalar-contracts`: 138 assertions, 327,022,291 emulator
  steps, 197.88 seconds;
- `sandbox-stage1-vm-state-contracts`: 114 assertions, 321,083,262 emulator
  steps, 203.99 seconds; and
- `sandbox-stage1-vm-terminal-contracts`: 136 assertions, 325,092,822
  emulator steps, 210.39 seconds.

The original aggregate profile remains available as a whole-suite diagnostic,
but it is not the routine acceptance gate: repeated source compilation in one
interpreted guest run exceeds the five-minute development ceiling. The three
bounded VM profiles qualify the same runtime contracts without raising the
checked-in step limits or running test suites concurrently. The state group
now finishes comfortably below the wall-time boundary. The remaining
multi-minute duration is dominated by image startup, module loading, and
repeated compiler/verifier workspace initialization rather than guest
instruction execution; reducing those development-harness costs is not on the
Stage 1 critical path.

## Explicitly deferred consumers and layers

Stage 1 does not claim:

- nonempty import binding or trusted adapter dispatch;
- typed value graphs or canonical value codecs;
- canonical profile/artifact serialization, cryptographic identity, package
  provenance, or durable verified-plan caching;
- Desk, Agent, Practice, Context, VFS, network, persistence, UI, credential,
  or capability integration; or
- a production-qualified contract VM.

The current contract VM remains an experimental ITC consumer. A future port
must use this common sandbox core and remove that temporary evaluator path,
while separately qualifying chain gas, deployment identity, storage,
transaction rollback, logs, return/revert truth, and durable recovery.
