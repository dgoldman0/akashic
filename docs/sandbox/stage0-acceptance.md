# Stage 0 adversarial acceptance contract

**Status:** Stage 0 ratified design; implementation has not begun
**Scope:** qualification requirements derived from
[`threat-model.md`](threat-model.md)

This document fixes the negative-test oracle before implementation. It does
not claim that any current ITC or contract test satisfies these cases.

`org.akashic.sandbox.pure-compute` is the permanent production
least-authority profile and the baseline qualification profile. It provides
pure value-to-value computation with zero bound imports, zero effects, and
zero proposal surface. It is not a toy or transitional runtime.

The shared artifact format, verifier, profile representation, executor, and
typed-import dispatch machinery are general production architecture from the
beginning. The pure-compute profile uses that complete architecture with an
empty import set. Additional profiles add concrete adapters and capability
sets; they never replace or reduce the common core.

The same Stage 1 core includes the profile's production typed counted-loop
instructions and verifier state. `DO`, `LOOP`, `+LOOP`, and `R` execute over
separate invocation-local loop frames. `R` is the current innermost lexical
loop counter. Loop frames never reuse or alias call frames or the host return
stack.

## Interpretation

Each case is a required observable property, not a prescription for one test
function. Qualification may use tables, generated cases, bounded fuzzing,
fault injection, or deterministic unit fixtures as appropriate.

The gates are:

- **Stage 1 — neutral core:** compiler, canonical profile and artifact,
  independent verifier, generic import binding, typed loop machinery, value
  codec, executor, and invocation-local cleanup.
- **Stage 2 — Akashic host:** exact module declaration and schema resolution,
  capability-empty child Context, copied input/output, Practice policy, and
  host lifecycle.
- **Stage 3 — Desk and Agent:** package-class admission, Desk release, and
  Agent-facing compile/verify/test/invoke adapters.

Within Stage 1, **verified-artifact runtime** cases execute an ordinary
artifact accepted by the verifier. **Executor defense-in-depth** cases use a
trusted fault-injection seam to corrupt a sealed plan or runtime state that an
ordinary verified artifact cannot construct. Defense-in-depth fixtures MUST
NOT be mislabeled as verifier-accepted hostile artifacts.

For every rejection or trap:

- no native exception may escape the relevant public compiler, verifier,
  executor, host, Desk, or Agent boundary;
- the relevant compiler, verifier, host, or invocation API must return its
  own bounded status/result without claiming that one invocation result
  taxonomy covers every phase;
- no semantic success result may be published;
- no out-of-bounds read, write, or execute may occur;
- no allocation, callback, hook, or invocation state may remain live; and
- host stack and dictionary state must match the documented API contract.

Fuzzing and generated cases MUST remain bounded. Repository resource-safety
rules continue to apply: heavyweight suites run sequentially, and
worker-spawning or unusually memory-intensive tests require approval.

## Stage 1 — source compiler

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| SRC-01 | Unmatched `ELSE`, `THEN`, `REPEAT`, or another backpatch terminator | Reject without writing through zero, a sentinel, or an uninitialized patch address; host state remains unchanged |
| SRC-02 | Unterminated definition or unbalanced conditional/loop/control frame | Reject before candidate artifact publication |
| SRC-03 | Top-level literals, malformed constant-like declarations, or compile-time stack operations | Use only compiler-owned semantic state or reject; caller stack delta exactly matches the API |
| SRC-04 | Maximum-plus-one identifier, token, nesting, definition, entry, literal, source, or emitted-code size | Bounded deterministic rejection with no leak |
| SRC-05 | Pathological token stream intended to cause superlinear or unbounded parsing | Complete or reject within the fixed source-token, control-depth, unresolved-reference, workspace, emitted-code, and source-byte ceilings; no restart loop, unbounded rescan, or unbounded allocation is permitted |
| SRC-06 | Source spelling a native word, address, XT, callback, or dictionary operation | Treat as an unknown/restricted token; never execute or resolve it through the host dictionary |
| SRC-07 | Bounded random and mutation-generated source corpus | No uncaught throw, host mutation, allocation leak, or nondeterministic acceptance |
| SRC-08 | Repeated failure followed by valid compilation | Valid compilation is unaffected by prior partial compiler state |
| SRC-09 | `DO`, `LOOP`, `+LOOP`, or `R` with missing, crossed, or mismatched lexical nesting | Reject before candidate publication; no compiler control state leaks |
| SRC-10 | Nested valid counted loops using `R` | Emit the canonical lexical loop-frame references; `R` binds to the innermost lexical loop |

## Stage 1 — artifact parser and verifier

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| ART-01 | Artifact truncated at every byte boundary | Verification failure before execution with no out-of-span read |
| ART-02 | Counts, offsets, or lengths whose addition or multiplication wraps | Verification failure before allocation or table walk |
| ART-03 | Misaligned, overlapping, reordered, duplicate, or trailing undeclared sections | Canonical-format rejection |
| ART-04 | Unknown opcode, reserved flag, invalid tag, or noncanonical encoding | Verification failure |
| ART-05 | Function-local branch index outside its function or direct-call index outside the function table | Verification failure; fixed-width index targets cannot represent an operand byte |
| ART-06 | Duplicate or ambiguous entries, imports, names, or identifiers | Verification failure |
| ART-07 | A path with data-stack underflow, inconsistent control-flow join, or wrong return shape | Verification failure |
| ART-08 | Invalid call/loop frame shape or an instruction that could reinterpret guest data as a return IP or loop frame | Verification failure |
| ART-09 | Missing selected entry or entry signature mismatch | Invocation refused before execution state is created |
| ART-10 | Artifact profile digest differs from the exact resolved descriptor, or the host declaration pairs the artifact digest with a different profile ID | Exact profile mismatch at the owning boundary; no alias or fallback |
| ART-11 | Unsupported opcode, import declaration, or signature for the exact profile | Verification failure |
| ART-12 | Artifact bytes mutated after verification | Execute the sealed accepted representation or reject; changed bytes never run under prior acceptance |
| ART-13 | Integer literal numerically equal to a host address or XT | It remains inert integer data; no instruction dereferences or executes it |
| ART-14 | Artifact from the current prototype ITC image format | Reject as unsupported; no compatibility loader or fallback evaluator |
| ART-15 | Bounded random and mutation-generated artifact corpus | No uncaught throw, out-of-span access, allocation leak, or execution before acceptance |
| ART-16 | Backedge whose data-stack height grows or differs at the merge | Verification failure rather than a runtime stack-growth fixture |
| ART-17 | `LOOP`, `+LOOP`, or `R` without a matching lexical `DO` | Verification failure |
| ART-18 | Branch into, out of, or across an incompatible lexical loop scope | Verification failure |
| ART-19 | Control-flow merge with different loop-frame depth or identity | Verification failure |
| ART-20 | `R` occurs where the verifier's current lexical loop identity is absent or differs from the innermost active counted loop | Verification failure |

## Stage 1 — profiles and typed-import machinery

The permanent pure-compute profile binds zero imports, but the general
profile/import mechanism is part of baseline core qualification. Synthetic
qualification descriptors and trusted test adapters may exercise nonzero
import tables without adding product authority to
`org.akashic.sandbox.pure-compute`.

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| PRF-01 | Resolve `org.akashic.sandbox.pure-compute` by exact ID and digest | Resolve the permanent profile with an empty immutable import table |
| PRF-02 | Use a different ID spelling, an added suffix, or the correct ID with a different digest | Exact profile mismatch; no alias or fallback |
| PRF-03 | Artifact declares any import under `org.akashic.sandbox.pure-compute` | Verification failure |
| PRF-04 | Synthetic artifact declares an unknown or duplicate import under a qualification profile | Verification failure |
| PRF-05 | Artifact import signature differs from the exact profile import in arity, value kinds, slice mode, or result shape | Verification failure before dispatch |
| PRF-06 | Profile import count, descriptor length, signature table, or cost arithmetic overflows | Profile/admission rejection before table construction |
| PRF-07 | Profile or resolved dispatch table is mutated after verification | The invocation uses its sealed exact table or refuses to start |
| PRF-08 | Two invocations resolve different import tables | Each uses only its immutable invocation-local table |
| PRF-09 | Import argument contains an invalid guest slice boundary | Trap before trusted adapter entry |
| PRF-10 | Import cost equals remaining budget and then exceeds it | Exact cost is charged before dispatch; excess prevents adapter entry |
| PRF-11 | Trusted qualification adapter returns its declared failure, returns `IMPORT.CANCELLED`, or throws natively | Declared failure becomes the exact `IMPORT_FAILURE` detail, `IMPORT.CANCELLED` becomes `CANCELLED / ADAPTER_CANCELLED`, and native throw becomes `HOST_FAILURE / IMPORT_ADAPTER_FAULT`; all execute common cleanup |
| PRF-12 | Adapter attempts to return a native pointer or XT through the typed ABI | ABI encoding rejects it; no native value reaches guest state |
| PRF-13 | Runtime binding is missing a required handler or has an extra/duplicate handler, wrong signature, or wrong profile digest | Refuse invocation before adapter dispatch |
| PRF-14 | Hash the exact 8,416-byte pure-compute descriptor fixture | Raw and domain-separated SHA3-256 values equal the published golden digests |
| PRF-15 | Change line endings, spacing, number spelling, record order, table order, count, enum, reserved field, or one semantic byte in a profile descriptor | Canonical profile rejection or a different digest; never normalization to the golden profile |
| PRF-16 | Profile opcode has zero cost, unknown cost/effect/operand kind, inconsistent fixed stack effect, or an absent semantic implementation | Reject before sealing the profile |
| PRF-17 | Qualification import receives writable slices, then returns failure, cancellation, malformed success, or throws after modifying its views | Guest memory remains at the pre-call bytes; staging is scrubbed and the exact failure class/detail is returned |
| PRF-18 | Qualification import supplies overlapping writable slices or exceeds staging/copy capacity | Trap on overlap or exhaust the exact resource before adapter entry; no guest byte changes |

## Stage 1 — verified-artifact executor behavior

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| RUN-01 | Branch-only infinite loop | Deterministic `RESOURCE_EXHAUSTED / INSTRUCTION_UNITS`; every iteration is charged |
| RUN-02 | Recursive call whose depth exceeds the invocation call-frame budget | Typed call-frame resource exhaustion with no native return-stack effect |
| RUN-03 | Valid counted `DO`/`LOOP` over representative lower, upper, equal, and boundary values | Result and instruction usage match the exact profile semantics |
| RUN-04 | Valid positive and negative `+LOOP` boundary crossings | Termination, final index, and usage match the exact profile semantics |
| RUN-05 | Nested counted loops using `R` | `R` returns the current innermost lexical loop counter; after inner exit the outer counter is current |
| RUN-06 | Function calls and recursion executed inside a counted loop | Call frames remain independent and cannot consume, reveal, or alter the caller's loop frames |
| RUN-07 | Valid recursion/nesting that dynamically exceeds the invocation loop-frame budget | Typed loop-frame resource exhaustion without call-stack reuse or partial frame publication |
| RUN-08 | Instruction cost equal to remaining budget and one greater | Equal cost may execute; excess produces `RESOURCE_EXHAUSTED` before instruction effects |
| RUN-09 | Instruction counter or cost arithmetic near its numeric maximum | Checked exhaustion; no wrap into additional budget |
| RUN-10 | Cancellation before start, during a branch loop, during a counted loop, and repeated cancellation | Distinct cancellation result and exactly one effective cleanup |
| RUN-11 | Divide by zero, minimum integer divided by negative one, and oversized shifts | Behavior matches the fixed arithmetic specification and is deterministic |
| RUN-12 | Same artifact/profile/input/instruction budget repeated cold and warm | Identical semantic class/detail, trap coordinates, usage, and canonical output bytes/digest, absent external cancellation or host failure |
| RUN-13 | Verified `+LOOP` executes with step zero | `GUEST_TRAP / LOOP_ZERO_STEP` before loop index, frame, stack, or continuation is mutated |
| RUN-14 | Verified `LOOP` advances `INT64_MAX`, or verified positive/negative `+LOOP` advances beyond `INT64_MAX`/`INT64_MIN` | `GUEST_TRAP / LOOP_ARITHMETIC_OVERFLOW` before loop index, frame, stack, or continuation is mutated |

## Stage 1 — executor defense-in-depth fault injection

The `DEF-*` cases deliberately bypass ordinary verifier guarantees through a
trusted test seam. No `DEF-*` fixture is evidence that a malformed artifact
was admitted.

| ID | Injected invalid state | Required oracle |
| --- | --- | --- |
| DEF-01 | Execute an instruction with an empty data stack despite a verified pop requirement | Typed data-stack underflow trap; host stack unchanged |
| DEF-02 | Corrupt a plan's required data-stack maximum or force a push past allocated capacity | Typed data-stack resource-exhaustion result; no adjacent write |
| DEF-03 | Corrupt the current instruction pointer or branch target beyond verified code | Typed instruction/target trap before fetch |
| DEF-04 | Corrupt a call target, return frame, or result shape | Typed call/return trap; native return stack unchanged |
| DEF-05 | Corrupt loop-frame kind, lexical identity, depth, index, limit, or continuation | Typed loop-frame trap before control transfer |
| DEF-06 | Execute `LOOP`, `+LOOP`, or `R` with no matching live lexical loop frame | Typed loop-frame trap |
| DEF-07 | Make a loop frame alias or overlap a call frame | Executor refuses the state; neither frame region is read or written through the other |
| DEF-08 | Corrupt local or memory metadata after verification | Typed local/memory trap before access |

## Stage 1 — linear memory

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| MEM-01 | Load/store at base minus one, base, end minus valid width, and end | Only exact in-range spans succeed |
| MEM-02 | Zero, maximum, negative-encoded, and overflowing offset-plus-length values | Checked deterministic rejection/trap with no host access |
| MEM-03 | Attempt to write code, stacks, profile data, or another invocation | Operation is unrepresentable or traps before access |
| MEM-04 | Attempt to treat an integer as a native pointer | No ABI or intrinsic performs the conversion |
| MEM-05 | Fresh invocation after an allocation was filled with recognizable secret bytes | Every readable byte has ABI-defined initialization; prior bytes are absent |
| MEM-06 | Read-only initial-data prefix touched by store, fill, or overlapping move destination | Trap before any byte is changed |
| MEM-07 | Bulk move/fill at exact copy-byte budget and one byte over | Exact budget succeeds; excess is rejected before mutation |
| MEM-08 | Trap after a validated source read but before a bulk destination write | Destination remains unchanged |

## Stage 1 — typed-value codec, handles, and graphs

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| VAL-01 | Decode `NULL`, canonical `BOOL`, `I64`, `BYTES`, `UTF8`, `LIST`, and `MAP` at their ordinary and empty forms | One canonical invocation-owned graph is produced and round-trips byte-for-value deterministically |
| VAL-02 | Supply BOOL payload other than canonical false or true | Input rejection or value trap; no node is published |
| VAL-03 | Use handle zero, an out-of-range index, the wrong arena selector, or an unallocated forward output handle | Invalid-handle trap on every accessor and constructor |
| VAL-04 | Reuse a stale handle from a completed invocation or a handle belonging to a live sibling | Invalid-handle trap without reading the other invocation |
| VAL-05 | Apply each typed accessor to every wrong value tag | Deterministic type-mismatch trap; arena remains unchanged |
| VAL-06 | Decode or construct truncated, overlong, surrogate, invalid-continuation, and otherwise invalid UTF-8 | Reject before publishing a UTF8 value or MAP key |
| VAL-07 | Decode a MAP whose keys are descending, otherwise unsorted, or duplicate | `REQUEST_REJECTED / INPUT_CODEC_INVALID`; no input root or partial arena is published |
| VAL-08 | Construct valid nested LIST/MAP DAGs that reuse one immutable child handle | Sharing is preserved as immutable DAG structure and expanded accounting charges each parent occurrence as specified |
| VAL-09 | Attempt self-reference, forward-reference, or a multi-node output cycle | Invalid-handle/cycle rejection before publishing the node that would close the cycle |
| VAL-10 | Graph depth exactly at the ceiling and one level beyond | Exact ceiling succeeds; excess is rejected without partial output |
| VAL-11 | Construct a MAP with a non-UTF8 key, duplicate key bytes, or keys not in strict raw-UTF8 byte order | The exact type, duplicate, or `GUEST_TRAP / MAP_KEY_ORDER` failure occurs atomically; no partial MAP handle is published and preexisting children remain unchanged |
| VAL-12 | Expanded input/result node, output-arena node, LIST-count, and MAP-count limits at the exact bound and bound plus one, using fixtures that satisfy every other simultaneous limit | Every reachable exact bound succeeds; excess is rejected at its owning boundary before partial publication |
| VAL-13 | `value_ops` budget at exact cost and one operation short | Exact budget succeeds; exhaustion occurs before the next value operation |
| VAL-14 | `copy_bytes` budget at exact copy cost and one byte short for blob copy or constructor | Exact budget succeeds; exhaustion leaves memory/output arenas unchanged |
| VAL-15 | Output constructor fails after validating some children because of node, byte, uniqueness, UTF-8, or budget failure | No handle or partial immutable node becomes visible |
| VAL-16 | Returned root is zero, stale, wrong-arena, or has an invalid reachable child | Non-success with no copied output |
| VAL-17 | Host input adapter attempts to bypass the canonical tree codec with a shared, forward, or cyclic native object graph | Refuse the adapter input before arena publication; canonical input bytes contain no references, sharing, or cycles |
| VAL-18 | UTF8/BYTES payload, expanded input/result bytes, and cumulative output-arena bytes at the exact bound and bound plus one, using fixtures that satisfy every other simultaneous limit | Every reachable exact bound succeeds; excess is rejected before copy or publication with the owning result detail |
| VAL-19 | Publish output nodes that become unreachable, then approach arena node/byte bounds with a small returned root | Unreachable nodes remain charged to both output-arena counters; final-result counters describe only the returned expanded root |
| VAL-20 | Successful output transfer followed by invocation cleanup and repeated result release | Canonical bytes remain valid after invocation state is scrubbed; result release invalidates and scrubs the disjoint result-owned buffer exactly once |
| VAL-21 | `V.MAP.FIND` searches present and absent keys across empty, odd, even, prefix, and raw-byte-order MAPs, then receives invalid UTF-8 | Midpoint trace and exact query/stored-key charge follow the fixed algorithm; absence returns `0 0`; invalid UTF-8 traps before stack mutation |

## Stage 1 — instance and profile isolation

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| ISO-01 | Two live invocations of the same artifact with distinct inputs | No cross-observation; stacks, memory, results, traps, and counters are independent |
| ISO-02 | Two live invocations using different exact profiles | No shared dispatch, profile, budget, or verification state |
| ISO-03 | Invocation A traps while invocation B remains live | B's state, result, budget, and cleanup are unchanged |
| ISO-04 | Repeated invocation after success, trap, exhaustion, and cancellation | No residual memory, output, trap, budget, or cancellation state |
| ISO-05 | Alternate execution of two live instances under the current owner-serialized scheduler | Isolation does not depend on a process-global current VM or hook |
| ISO-06 | Attempt to identify another invocation through values, addresses, or deterministic allocator reuse | No guest-visible identity or address grants access |
| ISO-07 | Alternate two live invocations while each holds nested counted-loop frames | Index, limit, lexical `R`, continuation, depth, and loop budget remain invocation-local |

## Stage 1 — authority-free neutral boundary

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| AUTH-01 | Artifact declares any import under `org.akashic.sandbox.pure-compute` | Verification failure |
| AUTH-02 | Guest returns bytes shaped like a pointer, XT, capability request, UIDL, markup, or Agent tool call | Returned only as untrusted value data; no action occurs |
| AUTH-03 | Guest attempts to identify a Context, endpoint, component, facet, Mandate, grant, owner token, VFS, or service table | No value type, instruction, or import exposes it |
| AUTH-04 | Caller attempts to raise a trusted activation budget through guest input or artifact metadata | Effective budget does not increase |

## Stage 1 — neutral failure and lifecycle containment

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| LIFE-01 | Allocation failure injected at every compiler, verifier, executor-setup, value-arena, and result-copy stage | The relevant Stage 1 API reports failure; every earlier allocation and publication is reversed |
| LIFE-02 | Trusted neutral helper throws during verification, setup, execution, or result copying | Public neutral boundary contains it, reports host failure where invocation began, and completes cleanup |
| LIFE-03 | Release or cleanup invoked twice | Second call performs no duplicate callback, publication, wipe-dependent read, or free |
| LIFE-04 | Snapshot host data/return stacks, dictionary state, and global hooks before and after each failure class | State matches the documented public API contract after return |
| LIFE-05 | Failure immediately before candidate-result publication | No success result becomes visible |
| LIFE-06 | Malformed guest diagnostic bytes | Diagnostics remain bounded and are rendered/transported as untrusted data |
| LIFE-07 | Cancellation arrives before each transfer poll, in each transfer block, and on both sides of the final cancel-versus-seal race | Poll gaps never exceed `cancel_poll_bytes`; cancellation wins only when its atomic transition linearizes first, otherwise the private result seal wins subject to successful cleanup |
| LIFE-08 | Cleanup faults before result transfer, during ordinary failure cleanup, and after a private result is sealed | Public result is `HOST_FAILURE / CLEANUP_FAULT` with no output; the private result is invalidated/scrubbed and every allocation not proved safely scrubbed is quarantined from reuse or release |

## Stage 1 exit criteria

The shared neutral runtime and its permanent
`org.akashic.sandbox.pure-compute` baseline are not qualified until:

- every Stage 1 `SRC-*`, `ART-*`, `PRF-*`, `RUN-*`, `DEF-*`, `MEM-*`,
  `VAL-*`, `ISO-*`, `AUTH-*`, and `LIFE-*` case above has an executable
  deterministic oracle;
- bounded parser/verifier/compiler fuzzing has no escaping native throw,
  out-of-bounds access, or leaked live allocation;
- host stack/dictionary restoration is checked across every public failure
  class;
- branch and counted loops prove that no opcode is free;
- typed loop-frame isolation, lexical `R`, nesting, calls, and `+LOOP`
  semantics pass both verified-artifact and defense-in-depth cases;
- value handles, codec, UTF-8, maps, DAG sharing, graph bounds, and value/copy
  budgets pass the `VAL-*` cases and every mandatory case in
  [`value-codec.md`](value-codec.md) section 12;
- two-instance and recycled-memory tests prove lifecycle isolation;
- exact artifact/profile verify-to-execute binding is demonstrated;
- the generic typed-import/profile machinery passes the `PRF-*` cases even
  though the pure-compute production profile binds zero imports; and
- compiler and verifier statuses remain separate from the neutral run result,
  while the host invocation result preserves its specified request, profile,
  verification, trap, exhaustion, output-rejection, import-failure,
  cancellation, and host-failure distinctions.

Tests whose expected result preserves known unsafe prototype behavior MUST be
rewritten or removed rather than cited as compatibility requirements.

## Stage 2 — Akashic host integration

The child Context in these cases is fresh and capability-empty, not literally
empty. It may retain trusted parent ownership, Practice, policy, and budget
metadata, none of which is serialized or exposed to the guest.

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| HST-01 | Resolve a stale, mismatched, or mutated module declaration, artifact, profile, entry, or schema digest | Refuse before invocation; never fall forward to a newer or ambient object |
| HST-02 | Supply malformed, open-map, wrong-type, excessive-depth, excessive-node, or oversized input under the pinned module schema | Host returns the applicable `REQUEST_REJECTED` detail before creating guest input state |
| HST-03 | Guest returns a structurally valid value that violates the pinned output schema | Host returns `OUTPUT_REJECTED / OUTPUT_SCHEMA_MISMATCH` and publishes no copied semantic output |
| HST-04 | Artifact is installed, visible, content-addressed, or bound in Practice but receives no explicit host run request | No invocation and no grant |
| HST-05 | Guest attempts to observe inherited child-Context ownership, Practice, policy, budget, endpoint, facet, authority, queue, wordset, or VFS fields | No value or result exposes them |
| HST-06 | Positive Context, Practice, declaration, and request ceilings disagree | Effective budget is the exact minimum applicable ceiling; guest input cannot widen it |
| HST-07 | Context release or cancellation occurs during branch loop, counted loop, value construction, or result copying | Cancel, drain, invalidate, wipe, and release exactly once according to the Stage 1 instruction-poll and transfer-seal linearization rules |
| HST-08 | One hosted module fails, then another is acquired and invoked | The second sees no stale Context, profile binding, VM state, value handle, trap, or endpoint state |

Stage 2 is not qualified until all `HST-*` cases pass in addition to the
already-qualified Stage 1 core.

## Stage 3 — Desk and Agent integration

| ID | Adversarial stimulus | Required oracle |
| --- | --- | --- |
| DSK-01 | Native package metadata is relabeled as a sandbox package, or vice versa | Admission rejects the execution-class mismatch before evaluating or loading code |
| DSK-02 | Sandbox package supplies an `APP-DESC`, lifecycle callback, service getter, widget/drawing XT, or native entry name | Admission rejects it; no native lookup or execution occurs |
| DSK-03 | Desk closes a sandbox component while execution is active | Desk triggers the Stage 2 cancel/drain path and destroys component/Context only after quiescence |
| AGT-01 | Agent-generated source, artifact, or result claims trusted status or asks to bypass verification | It follows the same compiler/verifier/host path as any hostile module |
| AGT-02 | Guest result bytes resemble markup, instructions, a capability call, or tool output | Agent adapter treats them as untrusted typed data and performs no implicit action |

Stage 3 is not qualified until all `DSK-*` and `AGT-*` cases pass in addition
to Stages 1 and 2.

## Additional profile qualification gates

The shared core is not redesigned for these features. Each additional
production profile supplies a typed interface set through the already-qualified
profile/import boundary; a trusted host activation supplies adapters and any
external authority. The profile, bindings, and adapters must pass the
applicable cases before that interface/capability combination is admitted.

### Concrete import adapters

- profile-specific semantic validation beyond the generic typed signature;
- scoped opaque-handle forgery, expiry, generation mismatch, and
  cross-invocation reuse;
- adapter-specific timeout, cancellation, and cleanup;
- capability-set attenuation and revocation; and
- proof that import declaration is not authority.

### Proposals and effects

- invalid or oversized proposal schema;
- forbidden effect class;
- stale target, generation, or owner-domain revision;
- proposal replay and idempotency-key collision;
- revocation between run and review;
- partial owner failure and uncertain external-effect truth; and
- proof that no proposal is dispatched before successful execution and
  trusted external acceptance.

### Persistent state

- exact snapshot identity and revision;
- state-write quota and schema bounds;
- optimistic conflict and retry behavior;
- transactional failure and recovery;
- migration and future-format refusal; and
- proof that VM memory is not silently reused as persistence.

### Declarative UI

- bounded view-tree depth, node count, text, and update rate;
- untrusted text rendering;
- rejection of guest callbacks, XTs, drawing pointers, and arbitrary UIDL;
- event input/result schema bounds; and
- release while events or rendering results are pending.

### Contract consumer

Contract-specific gas economics, deployment identity, caller/self values,
storage transactionality, logs, return/revert, durable cleanup, and chain
qualification remain in the contract subsystem. Passing the neutral sandbox
acceptance matrix does not qualify those semantics.
