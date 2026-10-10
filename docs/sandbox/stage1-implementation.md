# Stage 1 implementation ledger

**Status:** landed on `main`. Later work replaced the candidate with the
canonical artifact format and added the identity, declaration and host layers
this gate deferred; [`sandbox.md`](sandbox.md) records where the sandbox stands
now.

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
infrastructure before implementing this route. That digest work stayed out of
Stage 1; it later returned as `sandbox/digest.f`.

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
project remains unreleased and no predecessor runtime is preserved. Stage 2
replaced the candidate with the canonical artifact format of
[`artifact-format.md`](artifact-format.md); the route is otherwise the same.

The executor runs a decoded program rather than re-reading the artifact.
When the verifier seals a plan it also writes one 32-byte record per
instruction ([`plan.f`](../../akashic/sandbox/plan.f) describes it): the
opcode, stack effect and base cost, the resolved operand (absolute branch and
loop targets, a callee's parameters, results, locals and first instruction),
the literal, and the exact operand height and loop depth its proofs found
before the instruction. `RUN-SLICE` admits the instance once, checks that the
continuation agrees with the record at the instruction pointer (the IP lies
in the current function, and the operand height and open-loop count are
those the verifier proved there), and then dispatches each record through one
handler table that is filled when `vm.f` loads and only read afterwards.
`STEP` is a slice of one step.

Handlers skip only what the verifier proved for every record: the opcode,
branch and call targets, fall-through, the instruction pointer's range,
operand underflow, a loop entry's exit lying past its body, and a loop
instruction having an open frame. The per-step cancellation check is gone,
because only the owner cancels, and only between slices. Everything that
depends on guest values or instance memory is still checked before anything
changes, in the order the instructions always used: division and shift
operands, lengths, memory bounds, alignment and writability, then the budget,
operand room for instructions that grow the stack, call and loop frames, loop
steps and their arithmetic, value handles, and the contents of call and loop
frames. RETURN checks that the frame it resumes holds a continuation the
verifier proved, because the owner may change frames between slices. A native
caller racing writes into a sealed plan or live instance during one slice is
outside the object contract; guest code has no path to either native span.

The golden corpus in `local_testing/sandbox-vm-golden.f` froze every
observable result of the executor before this change (per-step state, sliced
runs, budget and limit sweeps, and every trap and exhaustion point) and still
matches. `local_testing/sandbox-vm-bench.f` measures MegaPad cycles per VM
instruction: a four-instruction counted loop costs 775 cycles per
instruction, against 11,577 before; stack shuffles 585 (13,103); guest
memory traffic 724 (14,982); calls 955 (11,828); and a typed-value read loop
7,754 (22,068), most of it spent validating the value handle. One NOP costs
about 350 cycles and one LOOP.NEXT about 1,000.

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

The three bounded VM profiles qualify the same runtime contracts without
raising the checked-in step limits or running test suites concurrently.

On 2026-10-09, after Stage 2 moved every limit out of the profile, the groups
pass with 150, 126, 148 and 36 assertions, and the aggregate
`sandbox-stage1-contracts` profile passes 571. They run their scalar entries
under the scalar-qualification profile, because the production profile now
enables no scalar entry. The hot-loop slice takes 848,103
emulator cycles against 1,442,583 for the code just before that change,
because entering a slice no longer re-measures the instance through the
profile. Each profile now finishes in about 28 seconds of wall time, mostly
image startup. That wall-time drop since July came from earlier harness and
emulator work: the code before the change also finished the scalar group in
28 seconds.

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
