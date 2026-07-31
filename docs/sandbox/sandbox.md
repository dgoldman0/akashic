# Akashic sandbox architecture

**Status:** Stage 0 architecture reference; Stage 1 is implemented and
qualified on the isolated `sandbox-stage1` branch

**Active implementation boundary:** [`stage1-implementation.md`](stage1-implementation.md)
controls the current critical path. Where the older Stage 0 documents make
canonical profile codecs, digests, typed value graphs, or production import
hardening part of Stage 1, those items are now later architecture reference
rather than prerequisites for the pure neutral runtime.

**Selected production baseline profile:** `org.akashic.sandbox.pure-compute`
**Security scope:** hostile source, hostile artifacts, hostile typed input, and
resource-exhausting guest behavior inside a pure invocation

This document is the entry point for Akashic's production-directed sandbox
architecture. It records the boundary selected before implementation. The
detailed contracts are:

- [Threat model](threat-model.md)
- [Artifact format and verifier](artifact-format.md)
- [Canonical profile descriptor](profile-format.md)
- [Pure-computation profile and typed ABI](profile-and-abi.md)
- [Canonical typed-value codec](value-codec.md)
- [Restricted production source language](source-language.md)
- [Stage 0 adversarial acceptance matrix](stage0-acceptance.md)

These documents specify the intended boundary. They do not claim that the
current implementation meets it.

## Executive decision

Akashic will have one neutral sandbox library and multiple separately owned
consumers:

```text
                         neutral sandbox library
                         /                     \
                        v                       v
          contract/chain adapter        Akashic sandbox host
                                                |
                                  +-------------+-------------+
                                  |             |             |
                                  v             v             v
                                Desk          Agent        Practice
                              lifecycle      requests       binding
```

The neutral library owns artifact validation and bounded execution. It does
not own installation, resource identity, lifecycle, authority, effects,
persistence, UI, Agent policy, Practice policy, or contract semantics.

The current
[`itc.f`](../../akashic/utils/itc.f)
is useful prototype material. It is not the sandbox boundary and is not a
supported predecessor. The current
[`contract-vm.f`](../../akashic/store/contract-vm.f)
is a chain-specific experimental consumer, not the owner of the generalized
runtime.

## No artificial predecessor

The first deliberately ratified sandbox artifact format is a clean format.
It is not “version 2” of ITC.

Do not add:

- an ITC compatibility loader;
- a `sandbox-vm-v2` beside a retained original;
- a raw-host-word compatibility profile;
- conversion of old images into trusted new images;
- a permanent alternate evaluator for the contract prototype.

During staged implementation, the old ITC/contract pair may remain as a
temporary, explicitly named bridge. Architectural closure ports the contract
adapter to the common runtime and removes the obsolete path. No compatibility
promise follows from the bridge.

## Selected package boundary

The neutral implementation belongs in its own top-level Akashic library:

```text
akashic/sandbox/
    format.f
    compiler.f
    verifier.f
    profile.f
    vm.f
    abi.f
```

Exact file grouping may follow implementation pressure, but the dependency
boundary is fixed:

- neutral sandbox code may depend on low-level checked spans, bounded buffers,
  integer primitives, hashing, and allocation mechanisms;
- it must not depend on `store/`, `tui/`, `agent/`, Practice, Desk, Library,
  VFS, the capability bus, or semantic resource owners;
- runtime integration with Akashic Contexts belongs above the neutral
  library;
- Desk and Agent adapters belong with their owning subsystems;
- the contract adapter remains under `store/`.

A likely integration surface is:

```text
akashic/runtime/sandbox-host.f
akashic/interop/sandbox-capability.f
```

Those files are host adapters, not part of the neutral execution core.

## Three separate isolation properties

“Sandbox” is not one undifferentiated claim.

### Hostile-code isolation

Guest source and artifacts cannot inspect or mutate host stacks, dictionary
state, native memory, execution tokens, callbacks, allocator metadata,
instruction pointers, or another invocation.

The compiler is part of the hostile-input surface. Its output is always an
untrusted candidate until the independent verifier accepts it.

### Authority and effect isolation

Verifier success, installation, visibility, a digest match, an import
declaration, or a Practice binding grants no authority.

The production pure-computation profile has no imports, proposals,
persistence, VFS, network,
credentials, UI, resource resolution, clock, or randomness. Later effect
work remains outside the VM and must use the ordinary exact-target,
review/grant, request-bus, and semantic-owner path.

### Lifecycle and instance isolation

Every invocation owns its mutable execution state. Stacks, locals, memory,
typed values, counters, cancellation, traps, and output cannot survive or
cross an invocation.

Desk's component-instance and child-Context machinery supplies host lifecycle
and defense in depth. It does not make native Forth safe.

## Package classes

Akashic keeps three explicit package classes:

1. **Trusted native components.** Existing source, MF64, and `APP-DESC`
   behavior. These execute with process trust.
2. **Sandbox executable modules.** Address-free artifacts admitted by the
   independent verifier and executed under an exact immutable profile. They
   never join the host dictionary.
3. **Content or declarative packages.** Data, templates, and later a
   restricted declarative UI vocabulary requiring no arbitrary native code.

The existing trusted-local applet path does not become a sandbox package path.
A sandbox package cannot supply a native lifecycle callback, service getter,
widget handler, UIDL XT, drawing XT, host pointer, or dictionary import.

## Production baseline security claim

The permanent baseline qualification use is deliberately least-authority:

> Given hostile source, artifact bytes, entry selection, and typed input, the
> neutral runtime executes only an independently verified pure-computation
> module within invocation-local code, memory, stack, value, output, and work
> bounds, without exposing host pointers, native XTs, ambient services,
> authority, or effects.

The claim does not include:

- semantic correctness of the guest algorithm;
- native Forth or MF64 containment;
- graphical custom applets;
- persistent module heaps;
- synchronous guest service calls;
- consequential proposals or effects;
- contract deployment, storage, gas economics, logs, return, or revert;
- compromised trusted native code, verifier, runtime, or administrator;
- hardware or microarchitectural side-channel resistance.

Successful output remains untrusted data. It must not become native source,
UIDL callbacks, trusted markup, Agent instructions, capability requests, or
host control flow merely because execution succeeded.

## Production pure-computation profile

The permanent least-authority profile is:

```text
org.akashic.sandbox.pure-compute
```

It is:

- deterministic for an exact artifact, profile, entry, input, and
  deterministic budget;
- fresh-invocation;
- integer-only;
- typed value-to-value;
- import-free and effect-free;
- fixed-memory;
- typed counted-loop and direct-call control state;
- instruction-metered;
- cancellation-aware at bounded instruction intervals.

This profile is not a temporary VM generation, reduced interpreter, or
prototype that later profiles replace. It is one permanent configuration of
the complete production runtime. The shared artifact, verifier, executor,
typed-import records, profile binding, cleanup, and instance-isolation
machinery are designed and implemented once. The permanent profile exercises
the shared typed loop-frame region with `DO`, `LOOP`, `+LOOP`, and lexical
counter `R`, and it binds an empty import set.

Later hosted-module or contract profiles may bind other exact typed imports
and adapters. They must not require a second evaluator, a new host-pointer
ABI, a different isolation model, or replacement of the verifier/runtime
core. If a proposed later consumer would require gutting the baseline core,
the baseline architecture is incomplete and must not land.

The neutral value set is:

```text
NULL
BOOL
I64
BYTES
UTF8
LIST
MAP
```

`RESOURCE` is excluded because a semantic identifier must not imply resource
resolution or authority. `F32` is excluded until deterministic floating-point
semantics receive a separate decision.

The machine-level entry signature is:

```forth
( input-value-handle -- result-value-handle )
```

Handles are invocation-local numeric indices validated by typed intrinsics.
They are not pointers, capabilities, resource handles, or durable
identifiers. Zero is invalid.

Concrete entry schemas are not executable artifact sections and are not
embedded in the generic profile. They belong to a separately owned,
digest-pinned module declaration. Stage 0 fixes the following logical binding;
Stage 2 must ratify the declaration/schema codecs and canonical digest domains
before host invocation:

- exact semantic artifact owner and artifact digest;
- exact profile identifier and digest;
- entry name and artifact entry identity;
- input and output schema descriptors and digests;
- requested budget ceilings;
- provenance and applicable trust evidence.

The executable entry binds only the profile-owned physical signature
identity. The trusted host resolves the exact module declaration, validates
the copied input against its schema, invokes the matching verified entry,
then validates and deep-copies the returned graph against the output schema.

This separation allows many module-specific schemas to use one immutable
execution profile without making domain schemas part of the VM.

## Artifact and verifier boundary

The executable artifact is a canonical, address-free byte format with:

- an exact fixed header and section directory;
- a SHA3-256 binding to the exact canonical profile descriptor;
- function, import, entry, name, initial-memory, and fixed-width instruction
  sections;
- table indices and function-local instruction indices instead of addresses;
- zero reserved fields and padding;
- no self-certifying maxima, native cells, XTs, pointers, provenance, grants,
  or persistence wrappers.

The verifier accepts only:

- one complete bounded artifact span;
- one exact sealed declarative profile;
- caller-owned workspace and plan destination.

It reconstructs section geometry, function ranges, control flow, stack
effects, locals, calls, entries, imports, and costs independently. It neither
consults the compiler nor resolves host dictionary names.

Successful verification publishes a sealed, owned execution plan. Execution
uses that plan rather than the caller's mutable artifact bytes. The plan
contains no native import handler; a separate activation-local binding
supplies trusted implementations for any separately ratified profile that
admits imports. The shared binding machinery exists in the production core
from the beginning, while the permanent pure-computation profile binds an
empty table.

Verifier acceptance proves structural executability under one profile. It
does not prove origin, installation policy, semantic correctness, or
authority.

## Pure-profile host execution flow

The baseline pure-profile host path is:

```text
resolve exact module declaration, artifact, and profile
                         |
                         v
verify or retrieve exact sealed verified plan
                         |
                         v
validate and deep-copy one typed input value
                         |
                         v
create capability-empty child Context and explicit budgets
                         |
                         v
allocate fresh VM stacks, values, memory, counters, and result
                         |
                         v
execute one exact entry under the pure profile
                         |
                         v
validate and deep-copy one typed output value
                         |
                         v
invalidate, scrub, release, and return structured result
```

“Capability-empty child Context” means it has no guest-reachable bindings,
facets, authority, queues, wordsets, or VFS. The current constructor retains
some parent ownership, Practice, policy, and budget metadata for trusted host
use. No Context pointer or serialization enters the guest.

The baseline integration is headless. Desk may host the trusted component and
Agent may request its typed capability, but neither receives an executor
pointer. A guest does not implement `APP-DESC`, tick, paint, event, or other
lifecycle callbacks.

## Ownership

| Concern | Owner | Boundary |
|---|---|---|
| Executable artifact bytes | Dedicated module/package owner, potentially using Library storage | Exact semantic owner, domain revision, digest, and provenance |
| Artifact verification | Neutral sandbox library | Complete bounded span plus exact profile; no ambient dictionary |
| Module declaration and schemas | Module/package owner | Stage 2 canonical digest-pinned metadata; declaration is not authority |
| Practice binding | Practice | Pins relevance, exact module/profile, and policy; stores no live VM or grant |
| Execution instance | Trusted sandbox host | Owns child Context, VM state, budgets, cancellation, result, and teardown |
| Desk lifecycle | Desk/applet host | Owns component instance, hosting, close, and release |
| Agent invocation | Agent through an exact typed host capability | Receives no VM, pointer, import table, or automatic installation right |
| Persistent module state | A future separate semantic owner | Never VM memory or the Practice head |
| Domain observations | Each semantic owner | Copied exact snapshot, if a later profile admits observations |
| Domain effects | Each semantic owner | Guest proposal remains inert until external review/grant/dispatch |
| Contract behavior | Contract/chain adapter | Storage, gas, caller, deployment, logs, return/revert, and transaction semantics |

## Practice boundary

Practice binds semantic relevance and policy. It does not own artifact bytes,
VM memory, module state, handler XTs, live grants, or copied domain records.

A durable binding pins exact module-declaration, artifact, profile, entry,
schema, and budget identities. It does not invoke the module and does not
grant imports or effects.

An activation resolves that declaration to a verified plan and creates fresh
host state. Failure never falls forward to a newer artifact, another profile,
the current UI selection, or ambient VFS access.

## Agent boundary

Agent can eventually use typed operations such as:

- compile restricted source into a candidate artifact;
- independently verify an exact artifact/profile pair;
- run a bounded test case;
- invoke one verified pure entry;
- receive structured result, trap, and usage facts;
- propose a candidate module declaration for reviewed installation.

Agent-generated source remains inert until compilation and independent
verification succeed. Agent receives no VM object, Context pointer, host
callback, service endpoint, or implicit capability.

The pure guest profile itself has no observation effect. A trusted
Agent-facing wrapper may be classified as observation because it discloses a
derived result through the existing Agent authority path. That integration
classification does not add a guest import or authority.

The neutral ABI retains `BYTES`. If the current Agent JSON codec cannot
represent a selected entry's exact schema, that entry is unavailable through
that adapter until an explicit bounded encoding is added. The neutral ABI is
not narrowed to fit one current adapter.

## Desk and custom applets

Desk hosts a trusted sandbox component. It does not execute arbitrary code
through the native package loader.

The baseline Desk consumer should copy an exact snapshot into a headless compute
entry and render the copied validated result in trusted code. Full custom
applets come later through a restricted structured view model or declarative
UIDL subset.

Guest code must never supply:

- raw drawing or widget callbacks;
- UIDL execution tokens;
- native lifecycle XTs;
- service endpoints;
- component descriptors;
- host pointers or dictionary names.

Each sandbox applet instance may retain a trusted host component and private
capability-empty child Context for its host lifetime. It does not retain a
guest VM invocation. Every invocation creates fresh private data/call/loop
stacks, locals, linear memory, value arenas, handles, counters, cancellation,
trap, and candidate-result state, then scrubs and releases that state through
the common lifecycle. This is separate from ecosystem-wide native applet
reentrancy, which is not part of this work.

## Contract consumer

The contract VM eventually consumes the neutral runtime through a
contract-specific profile and adapter. That future port validates the
generality of the core; it does not drive baseline runtime qualification.

Generic concerns belong in the shared runtime:

- artifact validation;
- isolated stacks and memory;
- checked guest slices;
- every-instruction accounting;
- immutable profiles;
- typed traps and results;
- deterministic cleanup.

Deferred contract concerns remain outside the current critical path:

- gas schedule and economic correctness;
- deployment and code identity;
- caller and self representation;
- storage ownership, persistence, revisioning, and rollback;
- logs, return, and revert;
- transaction atomicity and failure truth;
- durable code/storage cleanup and recovery;
- chain-specific adversarial qualification.

Porting `contract-vm.f` to the common API is dependency cleanup. It is not a
request to production-harden all chain behavior during the Desk/Agent
sandbox work. Contract documentation must retain one concentrated ledger of
the remaining chain-specific work.

## Stage sequence

### Stage 0 — architecture ratification

Stage 0 consists of this document set:

- explicit threat model and trust zones;
- canonical artifact and independent verifier contract;
- exact permanent baseline execution profile and typed entry ABI;
- budget, trap, result, and deterministic-cleanup vocabulary;
- adversarial acceptance cases and exit criteria.

No production runtime implementation or contract hardening belongs in Stage
0.

### Stage 1 — production neutral runtime

Implement the bounded compiler, independent verifier, owned sealed execution
plan, immutable internal profile, empty pure binding, and resumable
caller-owned executor. Retain the generic import-call boundary in the machine
model, but do not put production import adapters, typed value graphs,
canonical profile codecs, or digest identity on this gate. Qualify malformed
source and candidates, instruction and target checks, bounds, budgets,
cancellation, cleanup, and cross-instance isolation. These are the permanent
runtime interfaces; later codecs and hosts construct or transport them rather
than replacing the pure runtime with a second evaluator.

### Stage 2 — exact artifacts and Akashic host

Add the module declaration/owner contract, exact resolution, verified-plan
cache, child-Context host, copied typed input/output, and Practice binding.

### Stage 3 — Desk and Agent

Add the trusted headless Desk component and explicit Agent
compile/test/verify/invoke operations. Do not silently add sandbox execution
to existing Agent presets.

### Stage 4 — mediated proposals

Define typed proposals, filtering, exact targets/revisions, review, sealing,
one-shot authority, dispatch, retry, idempotency, partial failure, and
uncertain-effect truth before enabling consequential operations.

### Later — persistent state and declarative UI

Persistent state receives a separate semantic owner. UI uses trusted
rendering of a restricted declarative model. Neither enlarges the neutral
VM's authority.

## Stage 0 stop conditions

Return for an explicit architecture decision if implementation would require:

- preserving the ITC image or raw whitelist ABI;
- adding a native address, XT, callback, dictionary import, service pointer,
  Context pointer, or live grant to an artifact or guest value;
- placing a module-specific schema or contract/domain type in the execution
  profile;
- letting compiler output bypass independent verification;
- executing borrowed artifact bytes after verification;
- treating profile/import declarations as authority;
- storing persistent state in VM memory or Practice;
- admitting effects before their external owner/retry/failure contract;
- blocking the pure sandbox on contract production hardening;
- adding contract, Desk, Agent, Practice, UI, or VFS dependencies to the
  neutral library.

## Qualification truth

These documents are the Stage 0 design oracle. They become an implementation
claim only after Stage 1 code and adversarial tests satisfy the acceptance
matrix.

No current ITC or contract test constitutes that evidence. Tests that
canonize unsafe behavior must be replaced rather than retained as a legacy
oracle.
