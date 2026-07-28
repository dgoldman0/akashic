# Canonical sandbox artifact and verifier contract

**Status:** Stage 0 architecture contract
**Scope:** neutral executable artifact bytes, mechanical and semantic
verification, and the sealed verified plan consumed by the sandbox runtime

This document defines the deliberately ratified executable artifact for the
Akashic sandbox. It is a canonical, address-free byte format. It carries
only information needed to verify and execute one module under one exact
execution profile.

The artifact is not a package manifest, authority declaration, persistence
record, publisher statement, or domain schema container. Those concerns
remain outside the neutral sandbox library.

The current `akashic/utils/itc.f` image is disposable prototype material. It
has no supported predecessor relationship to this format. Implementations
must not add an ITC reader, converter, compatibility flag, legacy opcode
surface, or fallback evaluator to this artifact path.

The pure-computation profile is a permanent production least-authority
profile and the baseline used to qualify the sandbox boundary. It is not a
toy evaluator intended to be gutted when imports or additional profiles are
needed. The artifact, verifier, sealed plan, executor state, and profile
binding defined here support generic typed import declarations from the
start. Profiles with a wider surface use the same architecture with exact
profile data and trusted adapters; they do not replace the format, verifier,
or runtime boundary.

## Boundary summary

The artifact contains:

- an exact execution-profile digest;
- one requested linear-memory size;
- private function signatures in machine cells;
- declared profile imports;
- named executable entries bound to profile-owned machine signatures;
- optional initial-memory bytes; and
- fixed-width instructions containing only integers and table indices.

The artifact does not contain:

- a host address, pointer, execution token, callback, or dictionary word;
- a native import handler;
- an artifact self-digest;
- source, source paths, timestamps, debug information, or build identity;
- package identity, publisher, provenance, signature, or revocation state;
- Practice roles or bindings;
- Desk, Agent, UI, VFS, network, credential, or persistence concepts;
- invocation budgets or authority;
- domain input/output schemas; or
- contract storage, caller, gas, log, return, or revert semantics.

The exact domain schemas for an entry live in a separately owned module
declaration. That declaration binds its schema identities to an exact
artifact digest, profile digest, entry name, and profile-owned machine
signature ID. It is itself digest-pinned by the semantic owner. The executable
artifact does not duplicate or interpret those schemas.

## Canonical integer encoding

All integers use the stated fixed width and little-endian byte order.
Implementations must decode bytes explicitly. They must not use native
`CELL`, `@`, structure casting, alignment-dependent reads, or host byte order
as wire semantics.

`u16`, `u32`, and `u64` mean unsigned wire integers. An instruction literal
uses the complete `u64` bit pattern as a two's-complement 64-bit integer under
the selected profile.

Lengths, offsets, counts, and memory sizes are admitted only when they fit the
platform's nonnegative signed-length domain and the applicable hard and
profile ceilings. On the current 64-bit platform, a wire value with bit 63
set therefore cannot become a length or offset.

Arithmetic is checked before it is performed:

- To validate a product, first require `count <= maximum / element-size`.
- To validate a subspan, first require `offset <= container-size`, then
  require `length <= container-size - offset`.
- To align a value, first require that adding the alignment mask cannot
  overflow.
- Never validate geometry by first calculating an unchecked
  `offset + length`.

## Exact file layout

The artifact starts with a 64-byte fixed header followed by exactly six
32-byte section-directory records. The complete fixed prefix is therefore
256 bytes.

```text
0                         64                       256
+-------------------------+------------------------+
| fixed header            | six directory records |
+-------------------------+------------------------+
                                                   |
                                                   v
          functions, imports, entries, names, initial data, code
```

No byte may precede the header or follow the advertised artifact extent.

### Fixed header

| Offset | Bytes | Field | Canonical value or meaning |
| ---: | ---: | --- | --- |
| 0 | 8 | magic | ASCII `AKSBX64` followed by one zero byte |
| 8 | 2 | format | exactly `1` |
| 10 | 2 | header extent | exactly `256` |
| 12 | 4 | flags | exactly zero |
| 16 | 8 | artifact bytes | exact complete supplied byte length |
| 24 | 8 | memory bytes | exact guest linear-memory allocation requested |
| 32 | 32 | profile digest | exact SHA3-256 profile digest |

Format discriminator `1` identifies this canonical sandbox artifact. It is
not a renaming or continuation of the ITC image format.

The header contains no self-digest. The semantic artifact owner records
SHA3-256 over the exact complete canonical artifact bytes. The verifier
computes and publishes the same content digest after successful validation.
A storage layer may provide its own checksum or checked-record envelope
without changing the executable bytes described here.

### Section-directory record

Each section-directory record is exactly 32 bytes:

| Offset | Bytes | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 4 | kind | exact section kind |
| 4 | 4 | flags | exactly zero |
| 8 | 8 | offset | byte offset from artifact byte zero |
| 16 | 8 | byte length | logical section length, excluding alignment padding |
| 24 | 4 | element count | exact number of section elements |
| 28 | 4 | element bytes | exact size of one element |

Exactly these six records occur at header offset 64, in this order:

| Kind | Section | Element bytes | Empty allowed |
| ---: | --- | ---: | --- |
| 1 | functions | 16 | no |
| 2 | imports | 16 | yes |
| 3 | entries | 16 | no |
| 4 | entry-name bytes | 1 | no |
| 5 | initial-memory bytes | 1 | yes |
| 6 | instructions | 16 | no |

For every section:

```text
byte length = element count * element bytes
```

The verifier rejects a missing, duplicate, reordered, unknown, or
wrong-sized section.

### Physical section placement

Sections occur physically in directory order. The first section offset is
exactly 256. Every subsequent section offset is exactly:

```text
ALIGN16(previous section offset + previous logical byte length)
```

All bytes between a logical section end and the next aligned section start
are zero. An empty section still carries the one canonical offset derived by
this rule; consecutive empty sections may therefore share an offset.

The instruction section is last. Its offset and byte length are multiples of
16, so its logical end is already aligned. That end must equal the advertised
artifact length exactly. Trailing padding or appended bytes are invalid.

These rules provide one physical representation and make overlap, hidden
payloads, and alternative padding encodings invalid rather than ignorable.

## Function section

Each function record is exactly 16 bytes:

| Offset | Bytes | Field | Rule |
| ---: | ---: | --- | --- |
| 0 | 4 | instruction count | positive |
| 4 | 2 | parameter cells | within profile ceiling |
| 6 | 2 | result cells | within profile ceiling |
| 8 | 2 | local cells | within profile ceiling |
| 10 | 2 | flags | zero |
| 12 | 4 | reserved | zero |

A function index is its zero-based record index.

Function instruction ranges are derived by prefix-summing their instruction
counts. No instruction offset is serialized in a function record. The first
function begins at instruction zero, each later function begins immediately
after the previous function, and the final function ends exactly at the
instruction count from the code directory.

The verifier must reject a zero instruction count, count-sum overflow, a
count sum that does not equal the code-section count, or any signature or
local extent above the exact profile ceiling.

Function parameter and result counts describe the private machine-cell
calling convention used by direct module calls. They do not describe domain
values or schemas.

## Import section

Each import record is exactly 16 bytes:

| Offset | Bytes | Field | Rule |
| ---: | ---: | --- | --- |
| 0 | 4 | profile import ID | must exist in the exact profile |
| 4 | 4 | profile machine-signature ID | must exactly match that import |
| 8 | 4 | flags | zero |
| 12 | 4 | reserved | zero |

An artifact import index is its zero-based record index. Import records are
strictly increasing by profile import ID and therefore unique.

An import record declares an execution requirement. It grants no authority.
The verifier resolves only the declarative profile import and its machine
stack effect. It does not resolve or retain a native handler.

The permanent least-authority pure-computation profile admits no imports.
Under that profile, the import section must be empty and no instruction may
name an import. Other profiles use these same generic import records and
profile bindings; adding a typed import does not create a different artifact
or executor architecture.

## Entry section and entry-name bytes

Each entry record is exactly 16 bytes:

| Offset | Bytes | Field | Rule |
| ---: | ---: | --- | --- |
| 0 | 4 | name offset | relative to the entry-name section |
| 4 | 2 | name length | 1 through 63 |
| 6 | 2 | flags | zero |
| 8 | 4 | function index | valid function record |
| 12 | 4 | profile machine-signature ID | exact profile entry signature |

An entry is selected by its name. Entry records are strictly ordered by their
raw name bytes, and names are unique.

Entry names are canonical machine keys matching:

```text
[a-z][a-z0-9._-]{0,62}
```

The entry-name section is exactly the concatenation of entry names in entry
record order. The first name offset is zero and each later offset is the
previous offset plus the previous length. The last name ends exactly at the
name-section length. There are no terminators, gaps, aliases, unreferenced
bytes, or alternate Unicode encodings.

The entry's machine-signature ID belongs to the exact profile. The verifier
looks up that signature and requires its declared machine lowering to match
the selected function's parameter-cell and result-cell counts exactly.

The machine signature is not a domain schema. In
`org.akashic.sandbox.pure-compute`, signature ID 1 lowers to one
invocation-local input-value handle and one returned value handle. The value
arenas are distinct from guest linear memory. The separate module declaration
binds that machine signature to exact domain input and output schema digests.
Changing a domain schema changes the declaration identity, not the executable
artifact format.

## Initial-memory section

The initial-memory section contains arbitrary bytes copied to guest linear
memory offset zero before invocation.

The header's memory size must be zero or a multiple of eight and must satisfy
the exact execution profile and implementation ceiling. The initial-memory
section length may not exceed it.

Runtime initialization has one exact order:

1. Allocate the complete requested guest-memory extent.
2. Zero every byte of that extent.
3. Copy the initial-memory section to guest offset zero.
4. Apply the exact profile's access rule to that prefix. The permanent
   pure-computation profile makes it read-only.

Code, stacks, verified-plan metadata, host memory, another invocation, and
recycled allocator bytes are never mapped into guest linear memory.

The pure-computation profile places copied typed input in a separate immutable
value arena and passes only its checked numeric handle. It does not append
input bytes to this memory section. Other profiles must specify any different
invocation-owned ABI layout in their exact profile without changing the
artifact geometry.

An artifact does not request a persistent heap. Guest memory belongs to one
invocation and is scrubbed before allocator reuse or release.

## Instruction section

Every instruction is exactly 16 bytes:

| Offset | Bytes | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 2 | opcode | profile-admitted sandbox opcode |
| 2 | 2 | flags | zero |
| 4 | 4 | operand A | opcode-defined integer or index |
| 8 | 8 | operand B | opcode-defined integer |

Each opcode has one exact operand shape in the execution profile:

- no operand;
- one 64-bit literal in operand B;
- one function-local instruction index in operand A;
- one function-table index in operand A;
- one import-table index in operand A;
- one local-cell index in operand A; or
- one profile-defined trap/reason value in operand A.

Every operand field unused by that opcode is zero. The verifier rejects
unknown opcodes, opcodes not enabled by the exact profile, nonzero instruction
flags, and noncanonical unused operands.

The instruction width is not negotiable within format 1. There are no
continuation words, inline variable-length operands, relocations, or
instruction padding.

### Address-free references

Instruction references have only these meanings:

- A branch target is a zero-based instruction index local to the current
  function.
- A direct call target is a function-table index.
- An import target is an import-table index.
- A local target is a cell index inside the current function's local extent.
- A literal intended as a memory coordinate is a guest linear-memory offset,
  not an artifact or host address.

There are no indirect branches, indirect calls, computed returns, raw return
stack operations, native execution tokens, or host-memory addresses.

Fixed-width records make every instruction boundary mechanical. A target
cannot name an operand byte or the first instruction of another function
through branch arithmetic.

### Permanent least-authority pure-computation profile

The exact least-authority pure-computation opcode set is ratified by the
corresponding profile contract. It may include fixed-effect:

- literal and basic operand-stack operations;
- deterministic 64-bit integer arithmetic, logic, and comparison;
- direct conditional and unconditional branches;
- direct function call and return;
- fixed local get/set operations;
- checked guest-memory load/store operations;
- guest-memory size observation; and
- explicit structured traps.

The profile defines every arithmetic corner case, stack effect, dynamic trap,
and positive instruction cost. It enables no arbitrary host import.

Counted-loop machinery is enabled and qualified in this permanent profile.
`LOOP.ENTER`, `LOOP.NEXT`, `LOOP.NEXT.BY`, and `LOOP.INDEX` use function-local
body/exit indices and a separate typed loop-frame region. The verifier proves
their reciprocal targets, structured nesting, and identical frame shapes at
merges. Loop index, limit, and continuation state never reuse the call stack
or a host return stack. Source `DO`, `LOOP`, `+LOOP`, and `R` map to these
instructions; on this project `R` inside a `DO` loop is the current lexical
loop counter.

## Execution-profile binding

The 32-byte header field is the SHA3-256 digest of one canonical declarative
execution profile. The exact descriptor codec, pure-profile bytes, and
published digest are defined in
[`profile-format.md`](profile-format.md). The hash is domain-separated:

```text
SHA3-256(
  ASCII("akashic.sandbox.profile") ||
  0x00 ||
  exact canonical profile bytes
)
```

The canonical profile defines:

- its semantic profile identity;
- the instruction semantics and enabled opcode set;
- each opcode's fixed operand shape and machine stack effect;
- deterministic arithmetic and trap behavior;
- a positive cost for every enabled instruction;
- import IDs and machine signatures;
- entry machine-signature IDs and their machine lowering;
- artifact, table, code, memory, stack, local, and call ceilings;
- whether recursion is permitted;
- canonical typed-value ABI rules; and
- deterministic execution requirements.

The artifact verifier accepts one sealed immutable declarative profile. It
validates that profile and compares its exact digest with the artifact header
before accepting profile-owned IDs or instruction semantics.

Native import handlers, execution tokens, service pointers, authority,
activation Context, and per-invocation selected budgets are not canonical
profile bytes. Profile hard ceilings are canonical descriptor fields.
A separate trusted runtime binding supplies implementations and is sealed
against the same exact profile digest. The executor refuses a runtime binding
whose digest does not match the verified plan.

The profile digest proves only which semantics the artifact names. It does
not prove publisher identity, verifier acceptance, installation policy, or
authority.

## Independent verifier

The compiler is an artifact producer. The verifier is the admission boundary.
Every artifact, including output from the bundled compiler, is independently
verified before execution.

### Inputs and state ownership

One verification operation accepts only:

- one complete caller-qualified artifact byte span;
- one sealed immutable declarative profile;
- one caller-owned verification workspace; and
- one disjoint caller-owned verified-plan destination.

The verifier:

- owns no process-global current operation;
- uses no compiler symbol or entry table;
- performs no ambient dictionary lookup;
- sees no native import handler or XT;
- invokes no artifact- or profile-supplied callback;
- performs no I/O or package lookup;
- does not mutate the artifact or profile;
- contains dependency throws as a verifier fault; and
- publishes no partial result.

The artifact, profile, workspace, and complete plan destination must have
valid nonwrapping caller geometry and satisfy the verifier's alias policy.
The plan destination may not overlap the artifact, profile, or workspace.

### Fixed mechanical validation order

Mechanical validation occurs in this order:

1. Validate caller spans, sealed profile shape, workspace state, capacities,
   and aliases.
2. Require the complete 256-byte fixed prefix.
3. Compare the eight magic bytes.
4. Classify the format discriminator.
5. Require exact header extent, zero header flags, exact supplied length, and
   admissible memory geometry.
6. Validate and compare the exact profile digest.
7. Validate all six directory records, exact element sizes, hard/profile
   counts, checked products, canonical offsets, and section containment.
8. Verify every inter-section padding byte is zero.
9. Validate function, import, entry, name, and initial-memory records.
10. Validate every instruction and its immediate table/target references.
11. Perform function reachability, control-flow, stack, local, call, entry,
    and exact-import-use analysis.
12. Compute the exact artifact content digest, build the immutable plan, and
    write the plan seal last.

A failure clears prior result fields and leaves the plan destination invalid.
The first failure classification and diagnostic location are deterministic
for fixed artifact/profile bytes.

### Function and control-flow validation

For each function, the verifier derives its exact instruction range from the
function table. It constructs successors using only profile-defined direct
control operations.

It requires:

- every branch target to be inside the current function;
- every call target to name an existing function;
- every import operand to name an existing import record;
- every local operand to be below the current function's local count;
- every non-control instruction to have its ordinary fallthrough inside the
  current function, and every explicit successor to be valid;
- no conditional fallthrough beyond the function;
- every instruction in a function to be reachable from that function's
  first instruction;
- every function to be reachable from at least one named entry; and
- every declared import to be referenced by reachable code.

Branches cannot cross function boundaries. No branch target may equal the
function instruction count; function exit is represented only by the
profile's return or trap semantics.

The verifier also builds the direct call graph. It identifies recursive
strongly connected components. A profile that forbids recursion rejects any
such component. A profile that permits recursion still relies on the
activation-local call-frame and instruction budgets for termination and
bounded execution.

Cycles are valid. A reachable return or trap need not exist: a branch-only
cycle is admitted and terminates dynamically by instruction exhaustion or
external cancellation. What is forbidden is falling off a function or
reaching an invalid successor.

The pure-computation CFG analysis carries exact typed loop-frame identities.
It requires properly nested enter/close pairs, reciprocal body/exit targets,
one current-call owner, and identical loop state at every control-flow merge.
`LOOP.INDEX` is valid only while the current function's abstract loop state is
nonempty. A call begins its callee analysis with no lexical loop frame; a
callee cannot inspect its caller's loop counter.

### Operand-stack, local, and call validation

Each function is analyzed independently from an abstract operand height equal
to its declared parameter-cell count. Each profile opcode and import machine
signature has one fixed pop/push effect.

The verifier rejects:

- an operation that consumes below the current function's frame base;
- an abstract operand height above the exact profile ceiling;
- different operand heights at one control-flow merge;
- a local index outside the declared local extent;
- a call site without the callee's declared parameter cells;
- a return whose operand height differs from the function result count;
- an entry function whose parameters or results differ from the selected
  profile machine signature; and
- any profile instruction whose verifier stack effect is not exact.

For a direct call, analysis removes the callee's parameter cells and adds its
declared result cells. This permits independent analysis of mutually
recursive functions without pretending recursion is statically bounded.

The verifier derives, rather than trusts from artifact bytes:

- maximum operand cells needed relative to each function frame base;
- maximum local cells;
- call-graph and recursion facts;
- reachable instruction and import sets; and
- exact per-instruction profile cost metadata.

The runtime preserves the same boundary defensively. Each call frame records
an operand-stack base. A callee cannot consume caller values below its
declared parameters even when those values remain in the physical
execution-owned stack.

### Import validation

For each import record, the verifier:

1. Requires strict ordering and uniqueness.
2. Resolves the profile import ID in the exact declarative profile.
3. Requires exact machine-signature ID equality.
4. Uses that profile signature for static stack analysis.
5. Requires at least one reachable reference to the import.

It does not bind native code. Runtime binding occurs only after verification
and only against a separately sealed activation-local binding for the exact
profile digest.

Under the least-authority pure-computation profile, any import record or
import instruction is a verification failure. Profiles that admit typed
imports still use this verifier path and its exact import/signature analysis.

## Sealed verified plan

A successful verifier publishes an opaque immutable verified plan. Execution
must not accept a raw artifact span plus an `accepted` Boolean.

The plan owns a private exact copy of the executable artifact material or a
fully decoded equivalent with identical semantics. It must not retain a
borrowed dependency on caller-mutable artifact bytes.

The plan records at least:

- exact artifact SHA3-256 content digest;
- exact profile digest;
- exact requested guest-memory size;
- validated function instruction ranges and machine signatures;
- derived per-function operand and local requirements;
- direct call-graph and recursion facts;
- canonical entry lookup metadata;
- exact import ID and machine-signature mapping;
- validated instruction operands and target metadata;
- resolved positive instruction cost-rule IDs and parameters; and
- the owned initial-memory and code bytes needed by execution.

Plan-internal references use plan-relative offsets or validated table indices.
The plan contains no native import handler, XT, service pointer, authority, or
guest-visible host address.

The plan is:

- sealed only after every check and copy succeeds;
- bound to its own storage so a raw byte-copy is invalid;
- immutable through the public API;
- validated again by the executor before allocation;
- rejected if paired with a different runtime profile binding; and
- invalidated without partial publication on verifier error or throw.

Owning the executable bytes closes the verify-then-mutate gap. Mutation or
release of the caller's original artifact after successful verification
cannot change the plan.

A verified plan is an ephemeral runtime object. If cached, its key includes
both exact artifact and profile digests. It is not a second durable artifact
format and must be reconstructed through verification after durable reload.

Verifier acceptance establishes only that the bytes are executable under the
named profile. It does not grant an import, capability, VFS access, network
access, domain authority, installation right, or permission to perform a
proposal.

## Compiler and runtime separation

The restricted-language compiler:

- owns caller-scoped token, symbol, control, and output state;
- never uses the ambient host data or return stack as source-language
  storage;
- emits one canonical candidate artifact into a bounded caller buffer;
- emits table indices and guest offsets rather than addresses;
- may call the verifier as a convenience after emission; and
- cannot create or seal a verified plan.

The verifier:

- does not parse source;
- does not trust a compiler-produced target, stack maximum, reachability bit,
  or acceptance marker;
- reconstructs all executable invariants from artifact and profile bytes; and
- remains independently callable for artifacts produced elsewhere.

The executor:

- accepts only a sealed verified plan;
- accepts a separate exact-profile runtime binding;
- gives every invocation private data, call, and local storage;
- allocates and initializes private linear memory;
- charges every instruction before applying its semantics;
- checks stack, call, target, local, and memory boundaries defensively;
- contains traps, cancellation, resource exhaustion, and host failure;
- copies typed input in and typed result out through the profile ABI; and
- deterministically tears down the complete invocation.

Every pure-computation invocation instantiates a separate private typed
loop-frame region. A call frame records its loop-region base; a callee may
create only frames above that base, `LOOP.INDEX` observes only those
current-call frames, and return requires restoration to the base. Loop storage
may not overlay call frames or expose a general return stack.

## Absolute admission ceilings

The neutral parser and verifier impose implementation-wide ceilings before
profile-specific limits. The absolute ceilings are:

| Quantity | Absolute ceiling |
| --- | ---: |
| complete artifact | 1 MiB |
| instruction records | 65,536 |
| function records | 4,096 |
| import records | 256 |
| entry records | 256 |
| one entry name | 63 bytes |
| complete entry-name section | 16 KiB |
| initial-memory section | 512 KiB |

The exact profile may only tighten these values. Guest-memory, operand-stack,
local, call-frame, instruction, output, and time ceilings also come from the
profile and activation budget. Artifact verification checks profile maxima;
invocation admission may reject a verified artifact when the current
activation budget is smaller than its recorded requirement.

## Required malformed-artifact qualification

Qualification must include deterministic rejection of at least:

### Caller geometry and extent

- null or wrapping nonempty input;
- protected or otherwise inadmissible caller spans;
- input overlapping the verifier workspace or plan destination;
- every truncation from zero through 255 bytes;
- advertised length smaller or larger than the supplied span;
- appended bytes after an otherwise valid artifact;
- a wire length, offset, or memory size outside the signed-length domain;
- product, alignment, or subspan overflow; and
- hard or profile capacity excess before allocation.

### Header and directory

- one-bit changes to magic;
- format zero or an unsupported format;
- wrong header extent;
- unknown header or section flag bits;
- missing, duplicate, unknown, or reordered directory kinds;
- wrong element sizes;
- count/byte-length mismatch;
- a section inside the fixed prefix;
- overlap, gap, noncanonical shared offset, or misalignment;
- nonzero alignment padding; and
- a code end that does not exactly equal artifact length.

### Functions, entries, names, and initial memory

- zero functions, entries, names, or instructions;
- zero-length function code;
- function instruction-count sum underflow, overflow, or mismatch;
- excessive parameter, result, or local counts;
- an invalid entry function index;
- unknown entry machine-signature ID;
- function/entry machine-signature mismatch;
- empty, overlong, invalid-grammar, duplicate, or unsorted entry names;
- name offset/length overflow, gap, overlap, alias, or unreferenced tail; and
- initial bytes larger than requested memory.

### Instructions and control flow

- unknown or profile-disabled opcode;
- zero-cost opcode in a supposedly executable profile;
- nonzero instruction flags or unused operands;
- branch target equal to or beyond the current function's instruction count;
- a cross-function branch attempt;
- invalid function, import, or local index;
- conditional fallthrough beyond function end;
- a reachable path that falls off the function;
- an unreachable instruction;
- a function unreachable from every entry;
- a declared but unreachable or unused import;
- direct recursion under a profile that forbids it; and
- malformed loop nesting, reciprocal targets, merge shape, or lexical
  `LOOP.INDEX` use.

### Stack and call shape

- operand underflow at function entry or after a branch;
- operand growth above the profile ceiling;
- different stack heights at one merge;
- call site with too few callee parameters;
- return with too few or too many result cells;
- import machine stack-effect mismatch;
- entry machine stack-effect mismatch; and
- a profile instruction without one exact verifier-known stack effect.

### Profile, plan, and cleanup

- malformed or unsealed declarative profile;
- profile digest mismatch;
- import ID/signature mismatch;
- any import under the least-authority pure-computation profile;
- verifier dependency throw during any validation phase;
- plan-capacity failure after successful mechanical parsing;
- a failed verification leaving a valid-looking prior plan;
- copying a sealed plan and accepting the copy;
- mutation of the original artifact affecting a successful owned plan; and
- two verifier workspaces or plans sharing mutable operation state.

Parser and verifier fuzzing must remain bounded by the checked-in case and
step ceilings. No malformed artifact may cause native execution, ambient
lookup, output, allocation beyond preflighted bounds, or partial plan
publication.

## Storage, ownership, and declarations

This artifact contract is a byte codec and execution-admission contract. It
does not select a path, store a blob, create a package row, publish a module,
or choose revision/recovery behavior.

A semantic module owner records at least:

- stable module resource identity;
- positive owner-domain revision;
- exact artifact SHA3-256 content digest;
- exact profile identity and digest;
- exact module-declaration digest;
- entry names and their profile machine-signature IDs;
- exact input/output domain schema digests;
- provenance and applicable trust evidence; and
- installation and revocation policy.

The host resolves those facts before verification and invocation. Practice
may bind a role to their exact identities, but that binding remains policy
and grants no execution authority.

An outer checked record, immutable blob, or package envelope may contain the
exact artifact bytes. Its checksum, generation, path, and recovery rules do
not alter this canonical executable format. Extracted bytes must still pass
the independent verifier against the exact profile on every uncached load.
