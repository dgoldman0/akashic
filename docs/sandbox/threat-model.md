# Sandbox threat model

**Status:** Stage 0 ratified threat model; Stage 1 implementation is tracked in
[`stage1-implementation.md`](stage1-implementation.md)
**Scope:** neutral sandbox compilation, artifact admission, verification,
profile-bound execution, Akashic hosting, and consumer boundaries

This document defines the security claim and trust boundary for Akashic's
shared production sandbox runtime. It is normative for the implementation
and for every execution profile built over that runtime.

The current `utils/itc.f` implementation and its serialized image are
prototype material. They are not a supported predecessor, security boundary,
or compatibility target. The production-directed sandbox replaces or
generalizes the useful ideas in that prototype without retaining an old
loader, raw-host-word ABI, parallel evaluator, or compatibility facade.

The contract VM is an eventual consumer of the neutral runtime. Contract and
chain hardening is not on the current critical path.

## Permanent least-authority profile

`org.akashic.sandbox.pure-compute` is the permanent production
least-authority profile and the baseline qualification profile for the shared
runtime. It is not a bootstrap profile, toy evaluator, temporary subset, or
disposable architecture.

The profile provides pure value-to-value computation:

- input consists only of copied, bounded, typed values;
- output consists only of copied, bounded, typed values;
- the profile exposes zero host imports;
- the profile exposes zero effects or proposals;
- execution has no VFS, network, persistence, UI, credential, clock,
  randomness, capability, Context, endpoint, or native callback access.

The shared artifact format, verifier, profile representation, executor, and
typed-import dispatch machinery are nevertheless general from the beginning.
An artifact carries a canonical import declaration table, a profile carries
typed import signatures and deterministic costs, the verifier binds the two,
and each invocation owns an immutable resolved dispatch table. The
`org.akashic.sandbox.pure-compute` profile binds an empty import set.

The shared verifier and executor also include typed counted-loop machinery
from the beginning. `org.akashic.sandbox.pure-compute` enables
`DO`, `LOOP`, `+LOOP`, and `R`. Every invocation owns a separate bounded loop
frame region. Loop index, limit, continuation, and lexical nesting state
never reuse the call stack or a host return stack. `R` reads the current
innermost lexical loop counter; it is not a general return-stack operation.

Additional production profiles add exact typed interface sets. Trusted host
activation bindings supply adapters and any externally authorized capability;
the profile itself supplies no permission. These profiles and bindings MUST
NOT replace, fork, bypass, or reduce the shared artifact parser, verifier,
executor, isolation state, checked ABI, instruction accounting, trap model, or
cleanup path.

The security claim is:

> Given hostile source, hostile artifact bytes, and hostile input, the
> neutral sandbox admits only an independently verified artifact and executes
> it within invocation-local memory, stack, control-flow, and resource
> bounds. The guest receives no host pointer, native execution token, ambient
> service, authority, or effect surface.

The data flow is:

```text
hostile restricted source                 hostile precompiled artifact
           |                                           |
           v                                           |
bounded non-evaluating compiler                       |
           |                                           |
           +----------> untrusted candidate artifact <-+
                                      |
                                      v
                 independent verifier + exact profile
                                      |
                                      v
                         sealed verified module
                                      |
                           copied typed input
                                      |
                                      v
                 invocation-local profile executor
                                      |
                                      v
                       untrusted typed result
```

Compilation is part of the hostile-input attack surface. The compiler is
trusted to parse and emit without corrupting the host, but it is not trusted
to certify its own output. Every artifact, including one emitted by the
bundled compiler, passes the independent verifier.

Successful output remains untrusted data. It MUST NOT become native Forth,
UIDL callbacks, trusted markup, Agent instructions, a capability request, or
host control flow merely because sandbox execution succeeded.

## Isolation dimensions

The word “sandbox” covers three separate obligations:

1. **Hostile-code isolation.** Guest source and artifacts cannot inspect or
   corrupt host memory, stacks, dictionary state, instruction pointers,
   execution tokens, allocator state, or native control flow.
2. **Authority and effect isolation.** Successful guest execution grants no
   VFS, network, persistence, UI, credential, capability, or domain
   authority. Consequential work remains owner-mediated outside the guest.
3. **Lifecycle and instance isolation.** One invocation cannot leak state,
   budgets, callbacks, traps, outputs, profiles, or recycled memory into
   another invocation.

Akashic's Context, capability, facet, Mandate, request-bus, and component
lifecycle layers are useful host-side mechanisms for the second and third
obligations. They do not make native code safe and they are not exposed as
guest APIs.

## Trust zones

### Untrusted origins

The following are hostile regardless of provenance:

- source written by a package author, user, Agent, or model;
- source influenced by prompt injection or external content;
- precompiled artifact bytes;
- package and module declarations, entry selectors, schema bytes, and profile
  references;
- invocation inputs;
- guest results and diagnostics;
- catalog or durable-store bytes that may be stale, corrupt, truncated, or
  replaced.

A digest establishes byte identity under the stated cryptographic
assumption. It does not establish verifier acceptance, publisher trust,
installation authority, invocation authority, or permission to perform
effects.

### Artifact resolution

Artifact and profile resolution is trusted host orchestration over untrusted
stored data. Resolution MUST bind an invocation to exact artifact and profile
digests. Lookup by a human-readable ID alone is insufficient.

The same immutable bytes, or a runtime-owned canonical representation derived
from those bytes, MUST be used for verification and execution. A mutable
caller buffer cannot remain the execution authority after verification.

### Neutral compiler

The compiler is in the trusted computing base for host-safe parsing and
emission. It MUST:

- treat source as data rather than evaluate it as native Forth;
- use bounded source, token, identifier, nesting, definition, entry, emitted
  code, allocation, and work limits;
- keep guest compile-time semantics separate from caller stack state;
- preserve its documented host stack contract on every return;
- publish no candidate artifact until all source-level structural checks
  succeed; and
- release or invalidate every partial allocation on failure.

Independent verification limits the damage of a compiler that emits an
incorrect artifact. It cannot repair host corruption performed while parsing,
so compiler input handling remains security-critical.

### Neutral verifier

The verifier is the artifact admission oracle. It consumes only:

- one explicitly bounded artifact span; and
- one exact immutable execution profile.

It MUST NOT consult ambient dictionary state, raw native imports, compiler
entry tables, the most recently compiled module, process-global whitelist
state, or a mutable current profile.

Verifier acceptance MUST cover the complete artifact, including checked
arithmetic for all counts, lengths, offsets, alignment, and section extents;
canonical instruction decoding; entry and signature validation; branch and
call targets; data, call, and loop-frame shapes; lexical loop nesting and
merge rules; imports; and profile identity.

### General profiles and typed imports

Typed-import support is part of the shared production architecture, not a
later replacement for a simplified evaluator. The neutral core owns:

- the canonical artifact import-declaration representation;
- immutable profile identity and digest binding;
- import IDs, typed signatures, and deterministic cost declarations;
- verifier matching between artifact declarations and the exact profile;
- invocation-local resolved import tables;
- charge-before-dispatch accounting;
- checked value and guest-slice marshalling;
- structured import success and failure results; and
- exception-safe return to the common cleanup path.

The neutral core does not own the meaning or authority of a concrete
capability. A Desk, Agent, Practice, contract, or other consumer profile adds
its import descriptors and trusted adapters outside the neutral library.
Where an adapter uses opaque handles, their scope and generation are
invocation-local and the guest never receives a native pointer.

`org.akashic.sandbox.pure-compute` exercises the same artifact, verifier,
profile, executor, result, and cleanup architecture while resolving an empty
import table. It remains the production least-authority choice after richer
profiles exist.

### Verified representation

The executor consumes a runtime-owned verified representation. It MUST:

- contain no host address, native XT, callback, or service pointer;
- retain the exact artifact and profile identities under which it was
  accepted;
- be immutable for the duration of every invocation; and
- prevent mutation between verification and execution from changing
  admitted behavior.

A verified-representation cache is rebuildable optimization state, not
authority. Cache keys MUST include exact artifact and profile identity, and a
cache hit MUST NOT bypass current admission rules.

### Neutral executor

The executor is in the trusted computing base for confinement. Each
invocation owns:

- its data stack;
- its call stack;
- its separate typed loop frames;
- its bounded linear memory;
- its input and output value arenas;
- its instruction and resource counters;
- its cancellation state;
- its candidate root handle until successful result transfer; and
- its trap record.

No mutable execution state may be stored in a process-global current
invocation, whitelist, dispatch hook, entry table, or profile pointer.
On structural success, the host copies canonical output into a disjoint
result-owned object and seals that object privately before invocation cleanup.
No invocation handle or arena reference enters the result. Cancellation and
the private seal have one atomic ordering, and transfer polls within the exact
profile byte interval. Transfer failure publishes no success. The invocation
cleanup scrubs all invocation-owned candidate state; only cleanup success
publishes `OK`. A cleanup fault suppresses and disposes the private result and
quarantines storage not proved safe to reuse. After public success, the result
owner later invalidates and scrubs the transferred copy through its own
idempotent release path.

### Akashic sandbox host

The trusted sandbox host owns:

- exact artifact/profile resolution;
- creation of the activation-local host state;
- copied typed input;
- trusted budget selection;
- cancellation;
- result collection;
- failure translation; and
- deterministic teardown.

The host uses a **fresh and capability-empty child Context**, not a literally
empty Context. The current `CTX-CHILD-NEW` retains Practice identity,
owner-core/token, policy, and budget metadata while omitting bindings,
facets, authority, queues, wordsets, and VFS reachability. The guest never
receives the Context pointer or a serialization of its retained host fields.
The host MUST NOT expose those fields through the value ABI.

A trusted Desk adapter may receive a native `CINST`, endpoint, and lifecycle
callbacks. None of those values crosses into guest memory or input. The
adapter MUST catch guest failures and convert them to typed sandbox results;
guest traps MUST NOT escape as native applet callback throws.

### Authority and semantic owners

Practice binding, capability facets, Mandates, review, grants, the request
bus, and semantic-owner dispatch remain outside the neutral runtime.

The following are declarations or identity facts, not grants:

- artifact installation or visibility;
- a content digest;
- verifier acceptance;
- an execution profile;
- a requested import;
- a Practice binding; and
- a capability or service descriptor.

`org.akashic.sandbox.pure-compute` has no proposal channel. A profile that
adds proposals may only produce bounded typed proposal values through a
trusted adapter. Proposals remain inert until that adapter validates them
against exact facets and Mandates and the normal review/grant/owner path
performs the operation.

### Trusted native packages

Native source evaluation, MF64 loading, `APP-DESC`, raw lifecycle XTs, and
native service callbacks are a separate process-trusted execution class.

A sandbox package MUST NOT:

- enter through the native source builder or MF64 loader;
- provide an `APP-DESC`;
- provide an XT, service getter, widget handler, or callback;
- execute code in order to discover its manifest or descriptor; or
- be promoted to native trust because it is installed, visible, signed, or
  content-addressed.

Compromise of process-trusted native code is outside the in-process sandbox
claim.

## Attackers and attack goals

The threat model includes:

- a deliberately malicious module or package author;
- an Agent or model producing malicious code through prompt injection,
  compromised context, or ordinary generation error;
- a caller supplying malformed source, artifacts, module declarations, entry
  selectors, schemas, or values;
- a catalog or store returning stale, mismatched, truncated, or mutated
  artifact/profile data;
- a guest attempting arbitrary read, write, control-flow, or native-call
  escape;
- a guest attempting denial of service through free loops, recursion, stack
  growth, compiler/parser complexity, memory growth, or output flooding;
- a guest attempting to observe prior allocations or another invocation;
- a guest attempting to convert installation, binding, requested imports, or
  result data into authority; and
- a faulting or cancelled invocation attempting to leave callbacks, hooks,
  state, handles, or allocator contents behind.

## Protected assets

The sandbox protects:

- host data and return stacks;
- host dictionary, `HERE`, `LATEST`, instruction pointers, and XTs;
- callbacks, service endpoints, allocator metadata, and native memory;
- verified code integrity and control-flow boundaries;
- every other invocation's memory, stacks, inputs, outputs, counters,
  profile, traps, and Context;
- previously freed allocator contents and undisclosed caller data;
- Desk and owner-core availability within declared resource ceilings;
- exact artifact, profile, entry, ABI, and input identity;
- facets, Mandates, grants, credentials, VFS/network access, UI authority,
  and semantic-owner state; and
- truthful failure classification and bounded audit evidence.

The deterministic claim applies to a fixed artifact, exact profile, copied
input, and semantic instruction budget when external cancellation and host
failure are absent. Wall-clock cancellation or host failure is an additional
invocation condition and MUST be reported distinctly.

## Adversarial entry points

Every item below is a hostile-input boundary:

- restricted source bytes;
- compiler tokenization, integer parsing, identifiers, nesting, control
  structures, and code emission;
- artifact headers, section tables, counts, offsets, names, and instruction
  bodies;
- separately owned module declarations and their input/output schemas at the
  host integration boundary;
- artifact/profile lookup and verified-cache lookup;
- entry-point selection and entry signature;
- typed input decoding, especially aggregate counts and byte lengths;
- instruction decoding and every control transfer;
- guest stack and linear-memory operations;
- instruction and resource budget arithmetic;
- cancellation and component release;
- typed result encoding; and
- profile import, handle, proposal, and effect adapters.

The shared runtime includes the general typed-import boundary. The
`org.akashic.sandbox.pure-compute` profile binds no adapter at that boundary;
other profiles must qualify each concrete adapter and capability set.

## Assumptions

The security claim assumes:

- the host Forth runtime, allocator primitives, trusted compiler
  implementation, verifier, executor, and host adapter are not already
  compromised;
- execution profiles are admitted by trusted code;
- exact profile identity does not substitute for review of profile semantics;
- resource budgets are supplied by trusted host policy and cannot be raised
  by guest data;
- digest collision resistance is adequate for artifact/profile identity;
- guest addresses are offsets into guest linear memory, never native
  addresses;
- the caller applies disclosure policy before copying input into the guest;
- a guest may intentionally reproduce any input it was actually given; and
- current owner serialization may constrain scheduling, but isolation does
  not rely on shared mutable execution globals.

## Non-goals

The shared runtime and `org.akashic.sandbox.pure-compute` milestone do not
attempt:

- general native Forth or MF64 sandboxing;
- compatibility with the current ITC image or raw whitelist ABI;
- arbitrary native or graphical applets;
- guest drawing, UIDL, lifecycle, or service callbacks;
- synchronous access to Akashic services;
- persistent VM heaps or module-owned domain persistence;
- binding product host imports, effects, or proposal adapters into
  `org.akashic.sandbox.pure-compute`;
- publisher PKI, marketplace policy, or remote distribution;
- protection against compromised trusted native code or host administration;
- hardware or microarchitectural side-channel resistance;
- formal proof of a guest algorithm's semantic correctness; or
- production qualification of contract/chain behavior.

## Required invariants

### Source and artifact admission

- Source tokens never execute as native Forth.
- Guest source cannot consume or leave caller stack values beyond the
  compiler API's documented stack effect.
- Malformed source cannot perform a host write while reporting an error.
- Candidate artifacts are published only after complete source structural
  validation.
- Every artifact passes the independent verifier before execution.
- The verifier performs checked arithmetic before every derived span,
  allocation size, or table walk.
- Truncated, overlapping, misaligned, overflowing, duplicate, unknown, and
  noncanonical artifact structures fail before execution.
- Every instruction boundary, branch, call, entry, stack shape, signature,
  import, and profile reference is verified.
- Artifacts contain no host addresses or execution tokens.
- The executed representation is exactly the representation accepted under
  the recorded artifact and profile digests.

### Execution

- Every invocation has an independent data stack, call stack, typed
  loop-frame region, and input/output value arenas.
- Counted-loop frames are typed, bounded, verifier-visible, and distinct from
  call frames; guest data cannot become a return IP or loop frame.
- `DO`, `LOOP`, and `+LOOP` preserve verified lexical nesting at every
  control-flow merge.
- `R` is valid only in a lexical counted-loop scope and returns the current
  innermost lexical loop counter.
- Calls and recursion cannot expose, alias, consume, or reinterpret caller
  loop state.
- All stacks have checked underflow and overflow behavior.
- Code is immutable and disjoint from writable guest memory.
- Fresh readable guest memory has ABI-defined initialization and cannot
  expose recycled bytes.
- Every instruction fetch and transfer target remains on a verified
  instruction boundary inside the admitted code extent.
- Every instruction is charged before it executes.
- Budget arithmetic cannot wrap, become negative, or be raised by the guest.
- Guest memory and aggregate operations use checked offset-plus-length
  arithmetic.
- Arithmetic edge cases have specified deterministic behavior.
- No intrinsic consumes an integer as a native pointer or XT.
- Every value handle is validated against the current invocation, arena,
  live index, and expected type on every use.
- Value construction is publish-last: invalid UTF-8, duplicate map keys,
  forged or forward handles, graph cycles, and resource exhaustion publish
  no partial node or handle.
- Value graphs enforce the profile's depth, expanded-node, container,
  payload, value-operation, copy-byte, input-byte, and output-byte limits.
- Reused child handles form bounded immutable DAG sharing, never mutable
  aliasing or an authority-bearing reference.
- Candidate output is bounded and becomes a semantic result only on success.

### Authority

- Verification, installation, visibility, binding, and import declaration
  grant no invocation or effect authority.
- `org.akashic.sandbox.pure-compute` exposes no imports, effects, proposals,
  Context, endpoint, facet, Mandate, grant, or owner handle.
- Guest output is treated as untrusted data.
- Every profile import accepts only typed values, checked guest slices, or
  scoped opaque handles.
- Import declarations bind to the exact profile signature and cost but grant
  no authority.
- Proposals remain inert until external trusted validation and owner-side
  dispatch.

### Failure and lifecycle

- Compilation, verification, and invocation retain separate public status
  contracts. A source diagnostic is not forced into the invocation result
  record, and an invocation result does not claim to classify compiler
  failures.
- Non-success never publishes a semantic success result.
- Guest trap, exhaustion, structured import failure, output rejection,
  cancellation, and native throw all reach the applicable common cleanup path.
- Cleanup is idempotent and invalidates the invocation before releasing
  memory.
- Mutable stacks, memory, output, and scoped state are wiped before allocator
  reuse or release.
- Cleanup failure returns `HOST_FAILURE / CLEANUP_FAULT`, publishes no private
  success candidate, and quarantines every allocation not proved safely
  scrubbed.
- A successful result survives only as a disjoint result-owned canonical copy;
  no invocation-owned candidate survives cleanup.
- No invocation changes a process-global whitelist, dispatch hook, current
  artifact, entry table, or profile.
- One failed invocation cannot change a sibling invocation.
- Desk close/release cancels and drains execution before destroying its
  Context and component instance.
- No guest callback can run after release.

## Failure containment

| Failure phase | Required containment |
| --- | --- |
| Source rejection | Publish no candidate; preserve host stacks and dictionary; return a bounded sanitized diagnostic |
| Artifact/profile rejection | Start no invocation and publish no verified-cache entry |
| Allocation/setup failure | Reverse partial initialization through one cleanup path; expose no half-instance |
| Guest trap | Stop at an instruction boundary; publish no success value; return a bounded typed trap and resource facts |
| Resource exhaustion | Check and charge before the operation that would exceed the limit |
| Cancellation | Return a distinct cancellation result and perform idempotent teardown |
| Host failure | Catch at the sandbox-host boundary, distinguish it from a guest trap, clean up, and quarantine any allocation whose wipe/release safety cannot be proved |
| Release during execution | Mark closing, cancel, drain, invalidate, wipe, and then free |
| Repeated release | Perform no duplicate callback, publication, or free |
| Trusted-runtime corruption | Outside the sandbox guarantee; do not claim successful containment |

`org.akashic.sandbox.pure-compute` performs no effects and therefore has no
effect rollback problem. A profile that adds proposal/effect adapters MUST
define retry, idempotency, revision, partial-failure, and uncertain-effect
behavior before that capability set is admitted.

## Contract consumer boundary

The contract VM remains an experimental future consumer. Adoption of the
neutral runtime does not production-qualify contract execution.

Only generic mechanisms belong in the neutral library:

- isolated invocation state;
- checked memory and typed slices;
- immutable profiles;
- instruction and import accounting mechanisms;
- structured traps and results;
- deterministic cleanup; and
- typed import dispatch.

The following remain contract/chain responsibilities and are outside the
current critical path:

- gas schedule and economic correctness;
- deployment and durable code identity;
- caller and contract-self representation;
- storage ownership, persistence, quotas, and transaction rollback;
- log publication and ordering;
- return and revert semantics;
- durable code/storage cleanup and recovery; and
- chain-specific adversarial qualification.

Porting the contract adapter to the common interface is later dependency
cleanup. It creates no promise to preserve the prototype ITC format or ABI.
