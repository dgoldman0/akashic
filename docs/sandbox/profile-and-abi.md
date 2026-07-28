# Pure-computation sandbox profile and ABI

Status: long-term ABI reference. The scalar pure profile is implemented;
typed value graphs and production import adapters are deferred from the Stage
1 runtime gate. See
[`stage1-implementation.md`](stage1-implementation.md).

This document defines Akashic's permanent pure-computation execution profile:

```text
org.akashic.sandbox.pure-compute
```

The profile executes one fresh, deterministic, effect-free computation over
copied typed values. It is not compatible with the prototype ITC image or raw
host-word ABI. It admits no native execution tokens, host addresses, dictionary
imports, services, capabilities, persistent state, proposals, logs, VFS,
networking, UI, clock, randomness, or contract/chain behavior.

Normative requirements use **MUST**, **MUST NOT**, **SHOULD**, and **MAY** in
their usual sense.

## 1. Identity and ownership

The profile is identified by both:

- the exact UTF-8 identifier `org.akashic.sandbox.pure-compute`; and
- the exact profile digest
  `6e35c668e130473b9f2ef941da2c84941e6460f2b64bcce56526e31cd509e357`.

The digest is derived from the 8,416 normative bytes in
[`fixtures/pure-compute.profile`](fixtures/pure-compute.profile) under the
domain-separated codec in [`profile-format.md`](profile-format.md). That
descriptor carries every enabled opcode, semantic-rule identifier, cost rule,
limit, value tag, signature, and outcome code ratified here.

The identifier alone is not sufficient. An executable artifact binds the
exact profile digest; the separately pinned module declaration binds both the
profile identifier and digest. Changing any normative rule requires different
canonical descriptor bytes and therefore a different digest; implementations
MUST NOT silently reinterpret an artifact under a changed table. This is
content identity, not a named release boundary.

The neutral sandbox library owns the production runtime architecture:
canonical artifact parsing, compilation, independent verification, execution,
immutable profiles, generic typed-import declaration and dispatch, checked
guest slices and opaque handles, accounting, cancellation, structured results,
and deterministic cleanup. This profile binds that generic import machinery to
an empty import set. It is not a simplified evaluator intended to be gutted or
replaced when other consumers arrive.

Additional profiles and trusted host adapters reuse the same verifier, VM,
profile, ABI, accounting, and cleanup architecture. A profile may describe
separately ratified typed import interfaces and their deterministic costs.
Only a trusted activation binding may supply an implementation and whatever
external authority that implementation requires. Neither the profile nor an
artifact declaration grants permission. Additional profiles do not authorize
a parallel runtime or replacement VM.

The neutral library does not own module identity, domain schemas, Practice
binding, capability policy, Desk lifecycle, Agent behavior, or durable state.

## 2. Artifact, declaration, and entry separation

An executable artifact contains address-free code, read-only data, internal
function metadata, and an entry table. It contains no concrete domain input or
output schema.

Each public `ENTRY` carries:

- a unique canonical entry name of 1 through 63 bytes;
- an internal function index; and
- exactly one ABI signature identifier.

Its only ABI-contract field is the signature identifier. `ENTRY` MUST NOT carry
an input schema, output schema, capability, effect mask, Practice binding,
budget grant, handler, pointer, or authority claim.

Concrete domain schemas live in a separate, non-executable module
declaration owned above the neutral runtime. The Stage 0 sandbox boundary fixes
the declaration's required logical fields, but it does not ratify the
declaration or schema wire codecs. Stage 2 MUST ratify those codecs, their
canonical bytes, digest domains, bounds, and independent validators before an
Akashic host may install or invoke a declared module.

A declaration MUST logically bind:

- stable module identity and positive module revision;
- the exact executable-artifact SHA3-256 digest;
- the exact profile identifier and profile digest;
- for each exposed entry, its name and signature identifier;
- the eventual canonical input and output schema bytes and their SHA3-256
  digests;
- the module's requested execution ceilings;
- an empty import set and zero effect set for this profile; and
- an externally recorded SHA3-256 digest of the complete declaration bytes.

The eventual declaration format MUST be address-free, bounded, and
independently validated. Its digest is external identity metadata; the
declaration MUST NOT contain a circular self-digest. Every map schema
reachable from an entry schema MUST be closed:
declared keys are unique UTF-8 strings and unknown keys are rejected. A module
declaration is policy and validation input, not invocation authority.

Before invocation, the trusted host MUST resolve and pin one exact declaration,
artifact, profile, entry, and schema pair. It MUST validate the input against
the declared input schema before translating it into the neutral ABI and MUST
validate the returned value against the declared output schema before reporting
success.

An artifact digest proves byte identity. It does not prove verifier acceptance,
publisher trust, declaration validity, installation policy, or authority.

## 3. Execution model

The VM uses 64-bit two's-complement cells.

- False is `0`; true is `-1`.
- Addition, subtraction, multiplication, negation, increment, and decrement
  wrap modulo 2^64.
- Signed division and remainder truncate toward zero.
- Division by zero and `INT64_MIN / -1` trap.
- Signed comparisons return canonical booleans.
- Unsigned comparisons interpret the same cell bits as `u64`.
- Shift counts outside `0..63` trap.
- `SHR.U` is a logical right shift.
- Multi-byte immediates and guest-memory integers are little-endian.

Each invocation owns:

- one bounded data stack;
- one bounded call stack with per-call locals;
- one bounded typed loop-frame region disjoint from call frames;
- one fixed bounded linear memory;
- one immutable copied input-value arena;
- one append-only immutable output-value arena;
- one immutable reference to a sealed verified plan/profile pair;
- one budget record and usage record; and
- one cancellation flag.

Code, call frames, loop frames, value arenas, and linear memory are separate
address spaces.
Guest addresses are unsigned offsets into the current invocation's linear
memory. They are never host addresses. Linear memory is zero-initialized,
except for an artifact read-only-data prefix copied into its beginning. Loads
may read that prefix; stores, fills, and move destinations that overlap it trap.
The remainder is mutable scratch. There is no memory-grow operation.

All mutable invocation-owned storage MUST be scrubbed before allocator reuse
or release. No stack, loop or call frame, local, memory byte, handle,
invocation-owned candidate output, cancellation flag, or usage counter
survives an invocation. On `OK`, canonical output is first transferred into a
disjoint result-owned object as specified in sections 9 and 13. That object may
outlive invocation cleanup, but it contains no invocation handle or mutable VM
state and its owner MUST scrub it before allocator reuse or release. A shared
immutable verified plan/profile is not invocation-owned and is released under
its cache/reference policy; it contains no invocation input, output, authority,
adapter pointer, or mutable execution state.

## 4. Functions, locals, and verification

Every internal function record declares:

- parameter count, from 0 through 16;
- result count, from 0 through 16;
- local count, from 0 through 64; and
- its code span.

Locals are 64-bit cells initialized to zero on every call. They are addressed
only by the immediate indices of `LOCAL.GET`, `LOCAL.SET`, and `LOCAL.TEE`.
There are no mutable module globals. A compiler may reserve fixed mutable
linear-memory offsets for invocation-local source variables.

On `CALL`, the runtime records the caller's stack base after accounting for the
callee's declared parameters. On `RETURN`, exactly the declared results MUST
remain above that base. The verifier MUST prove compatible stack heights at
every control-flow merge and call site. Runtime checks remain mandatory as
defense in depth.

Branches use unsigned 32-bit function-local instruction indices. A branch
MUST stay inside its current function. `CALL` uses an unsigned 32-bit
function-table index. Fixed-width instructions make every possible target an
instruction boundary; no byte displacement or relocation is interpreted.

Recursion is allowed and is bounded by the call-frame and instruction budgets.

Counted loops are part of this permanent production profile, not a deferred VM
extension. A loop frame contains the owning call-frame depth, function index,
body target, exit target, signed index, and signed limit. It is stored in the
invocation's separate typed loop-frame region and never aliases the data stack
or call stack.

`LOOP.ENTER` consumes `( limit start -- )`. Operand A names the instruction
after its statically matching `LOOP.NEXT` or `LOOP.NEXT.BY`. When `start =
limit`, execution branches to that exit without publishing a frame. Otherwise
it pushes a frame and continues at the following instruction.

`LOOP.NEXT` uses signed step `+1`. `LOOP.NEXT.BY` consumes a nonzero signed
step. Both calculate the next index with checked signed 64-bit addition;
overflow traps. A positive step continues at operand A exactly when
`next-index < limit`; a negative step continues exactly when
`next-index > limit`. Otherwise the frame is popped and execution falls
through. A zero `+LOOP` step traps.

`LOOP.INDEX`, surfaced as source word `R`, returns the innermost loop counter
owned by the current call frame. A callee cannot observe a caller's loop
counter. This is the project-specific Forth rule: inside `DO` loops, `R` is
the loop counter. A return with an open loop frame is invalid.

The verifier proves properly nested pairs, exact reciprocal body/exit targets,
identical loop-frame shapes at control-flow merges, and `R` only within a
lexically active loop. `IF` and `BEGIN` forms still compile to ordinary
verified branches. Call and loop frame machinery is implemented and qualified
in the shared core from the beginning.

## 5. Instruction encoding

Every instruction is the same canonical 16-byte record defined by
[`artifact-format.md`](artifact-format.md):

| Offset | Bytes | Field |
|---:|---:|---|
| 0 | 2 | unsigned opcode |
| 2 | 2 | flags, exactly zero |
| 4 | 4 | operand A |
| 8 | 8 | operand B |

Unlisted opcode values are invalid. Every opcode below fixes which operand is
meaningful:

- `LIT.I64` uses the complete little-endian `u64` bit pattern in operand B as
  a two's-complement `i64`; operand A is zero.
- `BR`, `BR.ZERO`, and `BR.NONZERO` use operand A as a function-local
  instruction index; operand B is zero.
- `CALL` uses operand A as a function-table index; operand B is zero.
- `LOOP.ENTER` uses operand A as its matching exit target; `LOOP.NEXT` and
  `LOOP.NEXT.BY` use operand A as their matching body target; operand B is
  zero.
- `IMPORT.CALL` uses operand A as an artifact import-table index; operand B is
  zero.
- `ABORT` uses the low 16 bits of operand A as its bounded code; the high 16
  bits and operand B are zero.
- `LOCAL.GET`, `LOCAL.SET`, and `LOCAL.TEE` use operand A as a local-cell
  index; operand B is zero.
- Instructions with no immediate require both operands to be zero.

The verifier MUST reject unknown opcodes, nonzero flags, nonzero unused
operands, targets outside the current function, calls outside the function
table, local indices outside the current function, and entries whose function
signature does not match their ABI signature.

## 6. Profile opcode and cost table

`Cost` is charged against `instruction_units`. `V-op` means the instruction
also consumes one `value_ops` unit. `Copy n` means it also consumes `n`
`copy_bytes` units. A sealed plan records an exact cost-rule identifier and
its constant parameters for each instruction; it does not incorrectly reduce
a dynamic rule to one scalar.

Every instruction uses this deterministic sequence:

1. Poll cancellation when the fixed poll interval requires it.
2. Defensively validate the instruction, operand-stack arity, typed loop/call
   state, handles, complete guest spans, and other non-mutating arguments.
3. Perform any bounded read-only preflight needed to calculate the complete
   dynamic charge and resulting capacity requirements.
4. Reserve requirements in this priority: `instruction_units`, `value_ops`,
   `copy_bytes`, data-stack cells, call frames, loop frames,
   `import_staging_bytes`, `output_arena_nodes`, `output_arena_bytes`,
   `output_result_nodes`, and `output_result_bytes`.
5. Apply the instruction's guest-visible mutation or trusted import dispatch
   exactly once.

If validation fails, no usage is charged and the exact guest-trap detail wins.
If several reservations would fail, the first field in the stated priority
wins. A failed reservation changes neither usage counters nor guest state.
Successful reservation increments semantic usage before the operation is
applied; a later trusted host fault preserves that usage in the failure result.
No instruction may publish a partial stack effect, output node, memory write,
loop frame, or import result.

Read-only preflight is bounded by already-admitted table, map, value, and span
ceilings. For `V.MAP.FIND`, preflight determines the exact query bytes,
compared entries, and compared stored-key bytes before the charge; it does not
incrementally mutate the stack or counters.

### 6.1 Control and locals

| Opcode | Mnemonic | Stack effect | Operand | Cost | Semantics |
|---:|---|---|---|---:|---|
| `0x00` | `NOP` | `( -- )` | — | 1 | No operation |
| `0x01` | `LIT.I64` | `( -- n )` | B: `i64` | 1 | Push literal cell |
| `0x02` | `BR` | `( -- )` | A: local instruction index | 1 | Unconditional verified branch |
| `0x03` | `BR.ZERO` | `( flag -- )` | A: local instruction index | 1 | Branch when flag is zero |
| `0x04` | `BR.NONZERO` | `( flag -- )` | A: local instruction index | 1 | Branch when flag is nonzero |
| `0x05` | `CALL` | `( args -- results )` | A: function index | `2 + ceil(locals/8)` | Call declared function and zero its locals |
| `0x06` | `RETURN` | `( results -- results )` | — | 1 | Return after exact result-shape check |
| `0x07` | `ABORT` | `( -- )` | A: low `u16` | 1 | Trap with bounded guest abort code |
| `0x08` | `LOCAL.GET` | `( -- x )` | A: local index | 1 | Push current-frame local |
| `0x09` | `LOCAL.SET` | `( x -- )` | A: local index | 1 | Pop into current-frame local |
| `0x0A` | `LOCAL.TEE` | `( x -- x )` | A: local index | 1 | Store top cell without popping it |
| `0x0B` | `LOOP.ENTER` | `( limit start -- )` | A: matching exit target | 2 | Zero-trip on equality or push a typed loop frame |
| `0x0C` | `LOOP.NEXT` | `( -- )` | A: matching body target | 2 | Checked signed step `+1`, continue or close |
| `0x0D` | `LOOP.NEXT.BY` | `( step -- )` | A: matching body target | 2 | Require nonzero step, checked signed advance, continue or close |
| `0x0E` | `LOOP.INDEX` | `( -- index )` | — | 1 | Push current lexical loop counter |

Each successful `LOOP.ENTER` also consumes one `loop_frames` unit of live
capacity until its matching close. Closing a loop releases that live capacity;
it does not refund instruction usage. A failed zero-trip entry allocates no
frame. The verifier rejects a loop target or frame transition that is not the
exact structured pair described in section 4.

### 6.2 Data-stack operations

| Opcode | Mnemonic | Stack effect | Cost |
|---:|---|---|---:|
| `0x10` | `DROP` | `( x -- )` | 1 |
| `0x11` | `DUP` | `( x -- x x )` | 1 |
| `0x12` | `SWAP` | `( x y -- y x )` | 1 |
| `0x13` | `OVER` | `( x y -- x y x )` | 1 |
| `0x14` | `ROT` | `( x y z -- y z x )` | 1 |
| `0x15` | `NIP` | `( x y -- y )` | 1 |
| `0x16` | `TUCK` | `( x y -- y x y )` | 1 |
| `0x17` | `2DROP` | `( x y -- )` | 1 |
| `0x18` | `2DUP` | `( x y -- x y x y )` | 1 |
| `0x19` | `2SWAP` | `( a b c d -- c d a b )` | 1 |
| `0x1A` | `2OVER` | `( a b c d -- a b c d a b )` | 1 |

### 6.3 Integer, comparison, and bit operations

| Opcode | Mnemonic | Stack effect | Cost |
|---:|---|---|---:|
| `0x20` | `I64.ADD` | `( a b -- a+b )` | 1 |
| `0x21` | `I64.SUB` | `( a b -- a-b )` | 1 |
| `0x22` | `I64.MUL` | `( a b -- a*b )` | 1 |
| `0x23` | `I64.DIV.S` | `( a b -- quotient )` | 2 |
| `0x24` | `I64.REM.S` | `( a b -- remainder )` | 2 |
| `0x25` | `I64.DIVMOD.S` | `( a b -- remainder quotient )` | 3 |
| `0x26` | `I64.NEG` | `( n -- -n )` | 1 |
| `0x27` | `I64.ABS` | `( n -- abs )` | 1 |
| `0x28` | `I64.MIN.S` | `( a b -- min )` | 1 |
| `0x29` | `I64.MAX.S` | `( a b -- max )` | 1 |
| `0x2A` | `I64.INC` | `( n -- n+1 )` | 1 |
| `0x2B` | `I64.DEC` | `( n -- n-1 )` | 1 |
| `0x2C` | `I64.EQ` | `( a b -- flag )` | 1 |
| `0x2D` | `I64.NE` | `( a b -- flag )` | 1 |
| `0x2E` | `I64.LT.S` | `( a b -- flag )` | 1 |
| `0x2F` | `I64.LE.S` | `( a b -- flag )` | 1 |
| `0x30` | `I64.GT.S` | `( a b -- flag )` | 1 |
| `0x31` | `I64.GE.S` | `( a b -- flag )` | 1 |
| `0x32` | `I64.LT.U` | `( a b -- flag )` | 1 |
| `0x33` | `I64.LE.U` | `( a b -- flag )` | 1 |
| `0x34` | `I64.GT.U` | `( a b -- flag )` | 1 |
| `0x35` | `I64.GE.U` | `( a b -- flag )` | 1 |
| `0x36` | `I64.ZERO?` | `( n -- flag )` | 1 |
| `0x37` | `I64.NEGATIVE?` | `( n -- flag )` | 1 |
| `0x38` | `I64.POSITIVE?` | `( n -- flag )` | 1 |
| `0x39` | `I64.AND` | `( a b -- bits )` | 1 |
| `0x3A` | `I64.OR` | `( a b -- bits )` | 1 |
| `0x3B` | `I64.XOR` | `( a b -- bits )` | 1 |
| `0x3C` | `I64.NOT` | `( bits -- inverted )` | 1 |
| `0x3D` | `I64.SHL` | `( value count -- shifted )` | 1 |
| `0x3E` | `I64.SHR.U` | `( value count -- shifted )` | 1 |

`I64.ABS` wraps for `INT64_MIN`, consistently with `I64.NEG`. Division is the
only arithmetic operation with a separately trapped signed-overflow case.

### 6.4 Checked linear-memory operations

| Opcode | Mnemonic | Stack effect | Cost | Semantics |
|---:|---|---|---:|---|
| `0x40` | `MEM.SIZE` | `( -- bytes )` | 1 | Current fixed linear-memory size |
| `0x41` | `MEM.LOAD8.U` | `( offset -- byte )` | 2 | Checked unsigned byte load |
| `0x42` | `MEM.STORE8` | `( byte offset -- )` | 2 | Checked byte store |
| `0x43` | `MEM.LOAD64` | `( offset -- x )` | 2 | Checked aligned little-endian cell load |
| `0x44` | `MEM.STORE64` | `( x offset -- )` | 2 | Checked aligned little-endian cell store |
| `0x45` | `MEM.MOVE` | `( source destination length -- )` | `2 + ceil(length/8)` | Checked overlap-safe move; Copy `length` |
| `0x46` | `MEM.FILL` | `( destination length byte -- )` | `2 + ceil(length/8)` | Checked fill; Copy `length` |

Negative offsets or lengths, `offset + length` overflow, spans outside linear
memory, misaligned cell accesses, and writes overlapping read-only data trap.
Bulk operations validate complete source and destination spans and reserve their
complete costs before writing.

### 6.5 Shared typed-import instruction

The production runtime reserves one generic instruction used by profiles that
bind typed imports:

| Opcode | Mnemonic | Stack effect | Operand | Cost |
|---:|---|---|---|---:|
| `0x50` | `IMPORT.CALL` | profile import signature | A: artifact import index | `1 + exact declared import cost` |

Operand B is zero. The artifact import record names the exact profile import
ID and machine-signature ID. The verifier derives the pop/push effect from
that sealed profile signature; the artifact cannot declare its own effect.

Profile import signatures contain at most 16 parameters and 16 results and may
use only these explicitly checked machine kinds:

| Kind ID | Kind | Machine lowering |
|---:|---|---|
| `0` | `I64` | one cell |
| `1` | `BOOL` | one canonical `0` or `-1` cell |
| `2` | `VALUE` | one validated invocation-local value handle |
| `3` | `SLICE.RO` | offset cell followed by length cell; complete span read-only |
| `4` | `SLICE.RW` | offset cell followed by length cell; complete span writable |
| `5` | `OPAQUE` | one invocation-local `(kind, generation, index)` handle |

An `OPAQUE` signature item also names one nonzero profile-owned `u16` handle
kind. One opaque handle cell has this exact unsigned layout:

```text
bits 63..48  kind       nonzero u16, exact signature kind
bits 47..32  generation nonzero u16
bits 31..0   index      nonzero u32
```

The invocation owns a private opaque-handle table. Before adapter entry and on
every returned handle, the executor requires the exact kind, a live index, and
the table slot's current generation. Slot generation changes before reuse and
never wraps within an invocation; a would-be wrap permanently retires the
slot. A numeric handle from another invocation can resolve only against the
current invocation's table and therefore cannot name the sibling's object.

The descriptor fixes each parameter/result kind, slice mode, opaque kind, and
order. A result signature MUST NOT contain `SLICE.RO` or `SLICE.RW`; adapters
return scalar cells or validated invocation-local handles.

No signature kind can represent a host address, XT, callback, Context,
service pointer, grant, or native error buffer.

`SLICE.RO` admits any complete readable guest-memory span. `SLICE.RW` requires
the complete span to be writable and therefore rejects overlap with the
read-only initial-data prefix. Two `SLICE.RW` arguments in one call MUST be
pairwise nonoverlapping; ambiguous overlapping writeback traps as
`SLICE_OVERLAP` before adapter entry.

A read-only argument may expose a temporary trusted native view after complete
preflight. A writable argument never exposes guest memory directly. Before
adapter entry, the executor copies each writable span, in parameter order,
into a disjoint runtime-owned staging region initialized from the pre-call
guest bytes. The sum of staged lengths is checked against
`import_staging_bytes`, and the executor reserves `copy_bytes` equal to twice
that sum: one copy-in and one possible copy-out. It reserves the complete
amount even when the handler later returns failure.

The adapter receives only the staged writable views. On a structured failure,
cancellation, malformed result, or native throw, the executor discards and
scrubs staging without changing guest memory. Only after an `IMPORT.OK` result
has been completely validated does the executor commit every staged span to
guest memory in parameter order and atomically publish the result stack
effect. No guest instruction or adapter callback can observe an intermediate
commit. A trusted commit fault terminates the invocation as `HOST_FAILURE /
IMPORT_ADAPTER_FAULT`; invocation memory is then discarded, so no partial
write can become guest-visible or survive as a result.

Every temporary view is valid solely for the synchronous handler call. An
adapter MUST NOT retain it, invoke guest callbacks through it, or use it after
handler return. Slice offsets and lengths remain guest cells and never become
guest-visible host addresses.

Every profile import owns one cost-rule ID and fixed `u64` base charge. The
shared descriptor codec admits only these dynamic rules:

| Rule ID | Additional `instruction_units` |
|---:|---|
| `0` | zero |
| `1` | sum of `ceil(length/8)` for all slice parameters |
| `2` | sum of the canonical expanded value-byte measure for all VALUE parameters |
| `3` | both rule 1 and rule 2, added with checked arithmetic |

The instruction's own unit plus the import base and dynamic amount is reserved
before adapter entry. An artifact has no cost field and cannot override this
rule.

The trusted activation resolves exactly the imports declared by the verified
plan into an immutable table sorted by profile import ID. Every binding record
contains the exact profile digest, import ID, machine-signature ID, cost-rule
ID, a trusted handler, and handler-private host state. Handler addresses and
host state never enter the artifact, profile descriptor, verified plan, guest
memory, or guest values. Duplicate, missing, extra, out-of-order, or mismatched
records refuse invocation before VM state is created. A binding declares
availability; the host's external policy and Context determine whether the
handler actually has authority.

After complete preflight and charging, the executor calls one handler with a
runtime-owned request view containing the import ID and decoded, validated
arguments. A handler returns exactly one of:

- `IMPORT.OK` with the exact declared result kinds;
- `IMPORT.DENIED`;
- `IMPORT.UNAVAILABLE`;
- `IMPORT.REJECTED`; or
- `IMPORT.RESULT.INVALID`; or
- `IMPORT.CANCELLED`.

The executor validates every `IMPORT.OK` result before atomically pushing it.
The four structured failures become `IMPORT_FAILURE` with the corresponding
detail. `IMPORT.CANCELLED` becomes `CANCELLED / ADAPTER_CANCELLED`. A native
throw, malformed handler status, or failure after a claimed success becomes
`HOST_FAILURE / IMPORT_ADAPTER_FAULT`. No side channel or handler-defined
integer is reinterpreted as cancellation, a result class, pointer, or
execution token.

`org.akashic.sandbox.pure-compute` does not enable `IMPORT.CALL`, defines no
import IDs, and requires an empty artifact import section. Its verifier rejects
this opcode. The general instruction, verifier path, binding representation,
dispatcher, and qualification adapters are nevertheless part of the shared
production runtime rather than a later replacement.

## 7. Typed value ABI

The profile defines these numeric value tags:

| Tag | Type | Payload |
|---:|---|---|
| `0` | `NULL` | none |
| `1` | `BOOL` | canonical `0` or `-1` |
| `2` | `I64` | one 64-bit cell |
| `3` | `BYTES` | arbitrary bounded bytes |
| `4` | `UTF8` | bounded valid UTF-8 bytes |
| `5` | `LIST` | ordered value handles |
| `6` | `MAP` | ordered unique UTF8-key/value handle pairs |

`RESOURCE` and `F32` are not profile values. A string that happens to resemble a
resource locator remains UTF8 and receives no resolution or authority. Exact
host input/output bytes, canonical traversal, digests, and decoding rules are
defined in [`value-codec.md`](value-codec.md).

MAP entries are strictly increasing by unsigned lexicographic comparison of
their raw UTF-8 key bytes. Equality is exact byte equality. The codec and VM do
not apply Unicode normalization, case folding, locale comparison, or insertion
order. Consequently every structurally equal MAP has one observable index
order. Input decoding rejects unsorted or duplicate keys, and `V.NEW.MAP`
requires the supplied pair array to be in this order.

Every input map and every successful returned map MUST validate against a
closed concrete schema from the pinned module declaration. The generic value
arena enforces structural map validity and key uniqueness; the trusted host
enforces the declaration's exact allowed and required keys.

### 7.1 Invocation-local handles

A value handle is one 64-bit invocation-local number:

- `0` is always invalid;
- input handle `n` is `n` in the range `1..0x7fff_ffff_ffff_ffff`; and
- output handle `n` is `0x8000_0000_0000_0000 OR n`, where
  `1 <= n <= 0x7fff_ffff_ffff_ffff`.

Handles are indices, not addresses, capabilities, secrets, durable identities,
or authority tokens. Guest arithmetic can forge a numeric bit pattern, so every
value opcode and the final return boundary MUST validate the arena selector,
index, live invocation, expected value type, and requested range.

Input nodes are immutable. Output constructors publish immutable nodes only
after complete validation and budget reservation. Constructors may reference
already-existing input or output handles. Because a constructor's own handle
does not exist until publication, output construction cannot create a cycle.

### 7.2 Value opcodes

All opcodes in this section consume one `value_ops` unit in addition to their
instruction cost.

| Opcode | Mnemonic | Stack effect | Instruction cost | Semantics |
|---:|---|---|---:|---|
| `0x60` | `V.TYPE` | `( value -- tag )` | 2 | Return exact profile value tag |
| `0x61` | `V.BOOL.GET` | `( value -- flag )` | 2 | Read BOOL or trap |
| `0x62` | `V.I64.GET` | `( value -- n )` | 2 | Read I64 or trap |
| `0x63` | `V.LEN` | `( value -- n )` | 2 | Byte length or container count |
| `0x64` | `V.LIST.GET` | `( index list -- value )` | 3 | Checked list child lookup |
| `0x65` | `V.MAP.KEY` | `( index map -- utf8-value )` | 3 | Checked map key lookup |
| `0x66` | `V.MAP.VALUE` | `( index map -- value )` | 3 | Checked map value lookup |
| `0x67` | `V.MAP.FIND` | `( key-offset key-length map -- value found? )` | `4 + ceil(query bytes/8) + compared entries + ceil(compared stored-key bytes/8)` | Exact binary search by canonical raw-byte order |
| `0x68` | `V.BLOB.COPY` | `( value-offset memory-offset length value -- )` | `4 + ceil(length/8)` | Copy UTF8/BYTES payload into memory; Copy `length` |
| `0x70` | `V.NEW.NULL` | `( -- value )` | 2 | Publish NULL output node |
| `0x71` | `V.NEW.BOOL` | `( flag -- value )` | 2 | Require canonical flag and publish BOOL |
| `0x72` | `V.NEW.I64` | `( n -- value )` | 2 | Publish I64 output node |
| `0x73` | `V.NEW.BYTES` | `( memory-offset length -- value )` | `4 + ceil(length/8)` | Copy bytes and publish; Copy `length` |
| `0x74` | `V.NEW.UTF8` | `( memory-offset length -- value )` | `4 + ceil(length/8)` | Validate/copy UTF-8 and publish; Copy `length` |
| `0x75` | `V.NEW.LIST` | `( handles-offset count -- value )` | `4 + count` | Read `count` little-endian handles, validate, and publish |
| `0x76` | `V.NEW.MAP` | `( pairs-offset count -- value )` | `4 + 2*count + ceil(total-key-bytes/8)` | Read 16-byte key/value pairs, validate unique UTF8 keys, and publish |

`V.LEN` accepts only UTF8, BYTES, LIST, and MAP. `V.BLOB.COPY` accepts only
UTF8 and BYTES. `V.NEW.LIST` reads an array of `count` 8-byte handles.
`V.NEW.MAP` reads an array of `count` entries, each containing an 8-byte key
handle followed by an 8-byte value handle.

`V.MAP.FIND` is read-only. It first validates the complete query span, requires
its length not to exceed `blob_bytes`, and validates shortest-form UTF-8.
Invalid query UTF-8 traps as `INVALID_UTF8`; an invalid span or length uses the
ordinary memory/length trap. It then performs this exact binary search
over the MAP's canonical key array:

```text
low = 0
high = count
while low < high:
    middle = low + floor((high - low) / 2)
    order = unsigned-lexicographic(query, key[middle])
    if order == 0: found = key[middle]; stop
    if order < 0:  high = middle
    if order > 0:  low = middle + 1
absent
```

The checked subtraction and addition cannot wrap for an admitted MAP. Each
loop iteration counts one compared entry and the complete byte length of that
iteration's stored key, even if lexicographic order is known from an earlier
byte. Preflight records these exact totals, calculates and reserves the
complete charge, and only then changes the operand stack. On a match it pushes
the value handle followed by canonical true; when absent it pushes invalid
handle `0` followed by canonical false.

Constructors preflight all spans, handles, types, strict MAP ordering,
aggregate/blob bounds, output-arena capacity, expanded-result bounds, and
costs before publishing a handle.

## 8. Value graph bounds and charging

The hard value bounds are:

- maximum graph depth: 8;
- maximum expanded graph nodes: 4,096;
- maximum LIST count: 1,024;
- maximum MAP count: 256; and
- maximum individual UTF8 or BYTES payload: 65,536 bytes.

The exact descriptor fields are `value_depth`, `input_value_nodes`,
`output_result_nodes`, `output_arena_nodes`, `list_count`, `map_count`, and
`blob_bytes`. Their effective values apply simultaneously; no field suspends
another.

`input_value_bytes` and `output_result_bytes` are measured over the complete
expanded graph, counting a reused handle once for each parent occurrence:

- 16 bytes per value node;
- an additional 8 bytes for BOOL or I64 payload;
- padded-to-8 payload bytes for UTF8 or BYTES;
- 8 bytes per LIST edge; and
- 16 bytes per MAP entry.

`input_value_nodes` and `output_result_nodes` use that same expanded traversal.
For a DAG, every reference occurrence is charged again in both result measures.
These measures are canonical and independent of a host implementation's
structure padding or allocator overhead.

The append-only output arena has separate cumulative publication counters.
Publishing one new immutable node increments `output_arena_nodes` by exactly
one and increments `output_arena_bytes` by the node's own charge:

```text
ARENA-OWN(NULL)       = 16
ARENA-OWN(BOOL)       = 24
ARENA-OWN(I64)        = 24
ARENA-OWN(BYTES(n))   = 16 + PAD8(n)
ARENA-OWN(UTF8(n))    = 16 + PAD8(n)
ARENA-OWN(LIST(count)) = 16 + 8*count
ARENA-OWN(MAP(count))  = 16 + 16*count
```

`PAD8` is the checked padding function in
[`value-codec.md`](value-codec.md). Child payloads are not charged again to the
arena when a parent refers to them. Every successfully published node remains
charged until invocation teardown, including a node unreachable from the
returned root. Consequently the arena counters are monotonic and their final
values are also their peak values.

Before publishing an aggregate, a constructor computes and stores its
saturating expanded depth, node count, and value-byte measure from immutable
child metadata. Any result greater than the applicable effective
`value_depth`, `output_result_nodes`, or `output_result_bytes` ceiling rejects
that constructor before publication. Saturation occurs at limit plus one, so a
small arena cannot cause exponentially large traversal work through repeated
DAG references. The successful-return boundary recomputes or independently
validates the sealed metadata for the selected root and then charges the exact
`output_result_nodes` and `output_result_bytes` result measures. Returning an
input root is allowed, but it undergoes the same output-result checks.

The arena ceilings govern storage published during execution. The result
ceilings govern the final expanded root and its disjoint result-owned copy.
Neither counter refunds or substitutes for the other. Actual
invocation-owned allocation remains subject to the separate semantic
reservation.

Input codec excess is `REQUEST_REJECTED / INPUT_CODEC_INVALID`. A guest
constructor whose blob, LIST, or MAP count exceeds `blob_bytes`, `list_count`,
or `map_count` traps as `INVALID_LENGTH`. Arena publication exhaustion uses
`OUTPUT_ARENA_NODES` or `OUTPUT_ARENA_BYTES`; expanded constructor or return
exhaustion uses `OUTPUT_RESULT_NODES` or `OUTPUT_RESULT_BYTES`. All checks
precede node, stack, result, or byte publication.

## 9. Entry ABI

The only signature in this profile is:

| Numeric ID | Stable ID | Entry stack |
|---:|---|---|
| `1` | `org.akashic.sandbox.signature.value-to-value` | `( input-handle -- result-handle )` |

An entry function MUST declare one parameter and one result. At entry:

- the data stack contains exactly one valid input root handle;
- the call stack contains only the entry frame;
- all entry locals are zero; and
- usage counters begin at zero.

A normal return succeeds only when:

- the data stack contains exactly one cell above the entry base;
- that cell is a valid current-invocation input or output handle;
- no additional call frame remains;
- no loop frame owned by the entry call remains;
- the expanded returned graph satisfies profile bounds;
- the neutral value graph is structurally valid; and
- canonical encoding and transfer produce a disjoint result-owned candidate
  within `output_result_nodes` and `output_result_bytes`.

The result position accepts a current input-arena or output-arena handle, hence
the name `result-handle`; returning an input handle is allowed and the host
still copies it.

Result publication is a two-owner transaction with an explicit state machine.
After guest return, the executor atomically changes `RUNNING` to
`TRANSFERRING`, validates the selected root, and writes canonical bytes and
metadata into a private result-owned object disjoint from the input arena,
output arena, linear memory, stacks, and invocation record.

Transfer polls cancellation before its first byte, after each block accounting
for at most `cancel_poll_bytes` canonical bytes, and immediately before its
private seal. A cancellation request atomically changes `RUNNING` or
`TRANSFERRING` to `CANCELLED` and records the first cancellation detail. The
final transfer operation is one atomic compare-and-swap from `TRANSFERRING` to
`RESULT_SEALED`. If cancellation linearizes first, the seal fails and no output
is published. If the seal linearizes first, that completed computation wins
and later cancellation cannot replace it.

`RESULT_SEALED` is still private. The host next invalidates and scrubs every
invocation-owned object. Only successful cleanup permits an atomic transition
to publicly visible `OK`. If cleanup faults, the private result is invalidated
and scrubbed, the public result becomes `HOST_FAILURE / CLEANUP_FAULT`, and
every invocation or result allocation not proven safely scrubbed is
quarantined from allocator reuse or release. Thus no `OK` can escape and no
possibly secret-bearing allocation can reenter a pool after failed cleanup.

Allocation, encoding, or transfer failure before the private seal publishes no
`OK` object and becomes `HOST_FAILURE / OUTPUT_ADAPTER`. Releasing a public
result later is a separate idempotent operation that invalidates and scrubs its
owned buffer before reuse or release; a release scrub fault similarly
quarantines that buffer and cannot retroactively alter a result already
consumed by its owner.

Concrete output-schema validation is a Stage 2 host operation after structural
VM success. A domain validation failure produced deliberately by guest code is
an ordinary declared output, such as BOOL false or a closed result MAP. This
profile has no VM-level reject, revert, or commit result.

## 10. Budget vocabulary and profile ceilings

Static compiler/verifier admission ceilings and dynamic invocation budgets are
different records. They share names only where the same semantic quantity is
checked at both boundaries. A required positive limit MUST NOT be zero. Zero is
used only for a feature forbidden by the exact profile.

### 10.1 Static admission ceilings

| Admission field | Hard ceiling |
|---|---:|
| `source_bytes` | 65,536 |
| `artifact_bytes` | 65,536 |
| `code_bytes` | 49,152 |
| `readonly_data_bytes` | 16,384 |
| `source_token_bytes` | 63 |
| `source_tokens` | 16,384 |
| `functions` | 256 |
| `entries` | 32 |
| `function_parameters` | 16 |
| `function_results` | 16 |
| `locals_per_frame` | 64 |
| `compiler_control_depth` | 64 |
| `compiler_unresolved_references` | 3,072 |
| `compiler_workspace_bytes` | 1,048,576 |
| `linear_memory_bytes` | 262,144 |
| `imports` | 0 |
| `effects` | 0 |

`code_bytes` is exactly `16 * instruction-record-count`.
`readonly_data_bytes` is exactly the initial-memory section's logical byte
length. Source fields constrain the bundled compiler and are included in this
profile descriptor because the profile names its production source language;
an independently produced artifact is not required to retain source.

### 10.2 Dynamic invocation ceilings

| Runtime field | Hard ceiling |
|---|---:|
| `blob_bytes` | 65,536 |
| `call_frames` | 64 |
| `cancel_poll_bytes` | 4,096 |
| `cancel_poll_instructions` | 256 |
| `copy_bytes` | 1,048,576 |
| `data_stack_cells` | 256 |
| `guest_log_bytes` | 0 |
| `import_staging_bytes` | 0 |
| `input_value_bytes` | 131,072 |
| `input_value_nodes` | 4,096 |
| `instruction_units` | 1,000,000 |
| `list_count` | 1,024 |
| `loop_frames` | 64 |
| `map_count` | 256 |
| `outer_deadline_ms` | 1,000 |
| `output_arena_bytes` | 131,072 |
| `output_arena_nodes` | 4,096 |
| `output_result_bytes` | 131,072 |
| `output_result_nodes` | 4,096 |
| `persistent_write_bytes` | 0 |
| `proposal_bytes` | 0 |
| `proposal_count` | 0 |
| `semantic_reservation_bytes` | 1,048,576 |
| `value_depth` | 8 |
| `value_ops` | 16,384 |

Before allocation, the host calculates one platform-independent semantic
reservation:

```text
linear_memory_bytes
+ 8 * data_stack_cells
+ call_frames * (32 + 8 * verified_max_locals_per_frame)
+ 48 * loop_frames
+ import_staging_bytes
+ input_value_bytes
+ output_arena_bytes
+ output_result_bytes
+ 512
```

Every multiplication and addition is checked.
`verified_max_locals_per_frame` is the greatest local count in the sealed plan,
not an implementation allocation choice. The chosen effective capacities, not
native structure sizes, enter the formula. The fixed 512-byte semantic charge
covers the invocation record, counters, cancellation and trap records, and
candidate-result bookkeeping. Input, output-arena, and output-result byte
limits already include their own nodes and edges under section 8, so node
limits are not charged again.

An activation whose reservation exceeds its effective
`semantic_reservation_bytes` is refused before VM state exists. Native
allocators may use a different amount of storage; failure to allocate an
otherwise admitted reservation is `HOST_FAILURE`. Immutable verified plans
cached outside an invocation are excluded and remain subject to separate host
cache policy.

### 10.3 Baseline host preset

When no explicit trusted policy is present, the baseline host preset is:

| Runtime field | Baseline value |
|---|---:|
| `linear_memory_bytes` | 65,536 |
| `semantic_reservation_bytes` | 262,144 |
| `input_value_bytes` | 32,768 |
| `output_arena_bytes` | 4,096 |
| `output_result_bytes` | 4,096 |
| `input_value_nodes` | 1,024 |
| `output_arena_nodes` | 1,024 |
| `output_result_nodes` | 1,024 |
| `value_depth` | 8 |
| `blob_bytes` | 65,536 |
| `list_count` | 1,024 |
| `map_count` | 256 |
| `data_stack_cells` | 128 |
| `call_frames` | 32 |
| `loop_frames` | 32 |
| `import_staging_bytes` | 0 |
| `instruction_units` | 100,000 |
| `value_ops` | 4,096 |
| `copy_bytes` | 65,536 |
| `cancel_poll_bytes` | 4,096 |
| `cancel_poll_instructions` | 256 |
| `outer_deadline_ms` | 250 |

An explicit trusted host policy may select any value up to the hard ceiling;
it is not restricted to lowering the baseline preset. After defaults are
materialized, the effective invocation limit is the minimum applicable
positive value from:

1. the profile hard ceiling;
2. the selected trusted-host policy or baseline preset;
3. the declaration's requested ceiling;
4. Practice policy;
5. a positive child-Context ceiling;
6. a positive Agent Mandate ceiling where the units are semantically the same;
   and
7. the request-specific ceiling.

When a current higher-level field is zero or absent, it supplies no additional
ceiling; it never creates an unlimited VM field. Static artifact requirements
such as linear-memory extent must fit the resulting activation limits or the
request is refused before execution.

Agent model-token budget MUST NOT be reinterpreted as sandbox instructions.
Agent tool budget counts a sandbox invocation as one tool use. Agent disclosure
budget limits the provider-visible encoded result independently of neutral
output-value bytes.

`outer_deadline_ms` is a host cancellation boundary, not deterministic guest
input. For a fixed artifact, profile, entry, canonical input, and deterministic
budgets, and in the absence of external cancellation or host failure, the
result class, output, trap, and usage counters MUST replay exactly.

## 11. Result classes and detail codes

The public invocation result has one numeric class:

| Code | Class | Meaning |
|---:|---|---|
| `0` | `OK` | Valid typed output is present |
| `1` | `REQUEST_REJECTED` | Declaration, entry, input, activation binding, or effective-limit request was rejected before execution |
| `2` | `PROFILE_MISMATCH` | Requested, declared, artifact, verified-plan, or runtime profile identity does not match exactly |
| `3` | `VERIFICATION_REJECTED` | Independent verifier rejected the artifact |
| `4` | `GUEST_TRAP` | Guest semantics trapped |
| `5` | `RESOURCE_EXHAUSTED` | A deterministic execution ceiling was reached |
| `6` | `OUTPUT_REJECTED` | A structurally valid VM candidate failed the pinned external output schema |
| `7` | `IMPORT_FAILURE` | A trusted import returned one defined structured failure |
| `8` | `CANCELLED` | External caller, Context, deadline, adapter, or host shutdown cancelled |
| `9` | `HOST_FAILURE` | Trusted preparation, worker, adapter, cleanup, or invariant failed |

There is no contract revert, chain rejection, gas status, commit status, or
effect status.

`OK` always has detail zero. Every non-`OK` class has one nonzero detail from
its own namespace. Source compilation has a separate compiler result and never
masquerades as an invocation result.

### 11.1 Request-rejection details

| Detail | Name |
|---:|---|
| `1` | `MISSING_DECLARATION_OR_ARTIFACT` |
| `2` | `INVALID_DECLARATION` |
| `3` | `ENTRY_NOT_EXPOSED` |
| `4` | `INPUT_CODEC_INVALID` |
| `5` | `INPUT_SCHEMA_MISMATCH` |
| `6` | `ACTIVATION_LIMIT_MISMATCH` |
| `7` | `IMPORT_BINDING_INVALID` |
| `8` | `REQUEST_POLICY_REJECTED` |

Declaration- and schema-specific details become usable only after Stage 2
ratifies those external codecs. Artifact size, geometry, and profile ceilings
are verifier concerns, not request details.

### 11.2 Profile-mismatch details

| Detail | Name |
|---:|---|
| `1` | `UNKNOWN_PROFILE_ID` |
| `2` | `PROFILE_DESCRIPTOR_INVALID` |
| `3` | `ARTIFACT_PROFILE_DIGEST_MISMATCH` |
| `4` | `DECLARATION_PROFILE_MISMATCH` |
| `5` | `VERIFIED_PLAN_PROFILE_MISMATCH` |
| `6` | `RUNTIME_BINDING_PROFILE_MISMATCH` |

### 11.3 Guest-trap details

| Detail | Name |
|---:|---|
| `1` | `BAD_OPCODE` |
| `2` | `BAD_INSTRUCTION_POINTER` |
| `3` | `BAD_BRANCH_TARGET` |
| `4` | `BAD_CALL_TARGET` |
| `5` | `DATA_STACK_UNDERFLOW` |
| `6` | `CALL_STACK_UNDERFLOW` |
| `7` | `BAD_EXIT_SHAPE` |
| `8` | `DIVIDE_BY_ZERO` |
| `9` | `DIVIDE_OVERFLOW` |
| `10` | `SHIFT_RANGE` |
| `11` | `MEMORY_OUT_OF_BOUNDS` |
| `12` | `MEMORY_MISALIGNED` |
| `13` | `MEMORY_READ_ONLY` |
| `14` | `INVALID_VALUE_HANDLE` |
| `15` | `VALUE_TYPE_MISMATCH` |
| `16` | `VALUE_INDEX_RANGE` |
| `17` | `INVALID_UTF8` |
| `18` | `DUPLICATE_MAP_KEY` |
| `19` | `INVALID_RESULT_GRAPH` |
| `20` | `EXPLICIT_ABORT` |
| `21` | `LOCAL_INDEX_RANGE` |
| `22` | `INVALID_LENGTH` |
| `23` | `LOOP_STACK_UNDERFLOW` |
| `24` | `LOOP_ZERO_STEP` |
| `25` | `LOOP_ARITHMETIC_OVERFLOW` |
| `26` | `LOOP_STATE_INVALID` |
| `27` | `MAP_KEY_ORDER` |
| `28` | `SLICE_OVERLAP` |

Verifier-unreachable structural traps remain defense-in-depth runtime checks
and are qualified through sealed-plan/executor fault injection, never by
allowing an invalid artifact to bypass verification. `EXPLICIT_ABORT`
records the instruction's unsigned 16-bit guest abort code in a separate
bounded result field; it carries no guest pointer or string.

### 11.4 Resource-exhaustion details

| Detail | Name |
|---:|---|
| `1` | `INSTRUCTION_UNITS` |
| `2` | `VALUE_OPS` |
| `3` | `COPY_BYTES` |
| `4` | `DATA_STACK` |
| `5` | `CALL_FRAMES` |
| `6` | `LOOP_FRAMES` |
| `7` | `OUTPUT_ARENA_NODES` |
| `8` | `OUTPUT_ARENA_BYTES` |
| `9` | `OUTPUT_RESULT_NODES` |
| `10` | `OUTPUT_RESULT_BYTES` |
| `11` | `IMPORT_STAGING_BYTES` |

Stack/frame overflow, output-arena exhaustion, final-result expansion excess,
and import-staging exhaustion are resource exhaustion; underflow and invalid
typed state are guest traps. Static artifact excess is
`VERIFICATION_REJECTED / PROFILE_LIMIT_EXCEEDED`. Input, declaration, or
activation excess is `REQUEST_REJECTED`. Failure to allocate a request that is
within every admitted semantic limit is `HOST_FAILURE`, not guest exhaustion.

### 11.5 Output-rejection details

| Detail | Name |
|---:|---|
| `1` | `OUTPUT_SCHEMA_MISMATCH` |

The neutral executor does not produce this class. The Stage 2 host produces it
only after a structurally successful candidate fails the exact pinned external
schema. A host validator bug, throw, or allocation failure is `HOST_FAILURE`.

### 11.6 Import-failure details

| Detail | Name |
|---:|---|
| `1` | `DENIED` |
| `2` | `UNAVAILABLE` |
| `3` | `REJECTED` |
| `4` | `RESULT_INVALID` |

These details are the exact mapping of the four structured adapter statuses in
section 6.5. The pure-computation profile cannot produce this class because it
binds no imports.

### 11.7 Cancellation details

| Detail | Name |
|---:|---|
| `1` | `CALLER_CANCELLED` |
| `2` | `CONTEXT_RELEASED` |
| `3` | `DEADLINE` |
| `4` | `HOST_SHUTDOWN` |
| `5` | `ADAPTER_CANCELLED` |

During execution, cancellation is sampled before the next instruction charge
at least every `cancel_poll_instructions`. During result transfer it is sampled
at the `cancel_poll_bytes` boundaries and final atomic seal described in
section 9. Once cancellation wins either linearization, no further guest
instruction or output publication occurs. The first successfully recorded
cancellation detail wins over later cancellation causes.

### 11.8 Host-failure details

| Detail | Name |
|---:|---|
| `1` | `PREPARE_ALLOCATION` |
| `2` | `INPUT_ADAPTER` |
| `3` | `OUTPUT_ADAPTER` |
| `4` | `WORKER_FAULT` |
| `5` | `INTERNAL_INVARIANT` |
| `6` | `IMPORT_ADAPTER_FAULT` |
| `7` | `CLEANUP_FAULT` |

Native throw codes, addresses, execution tokens, and host error buffers MUST
NOT appear in the neutral result.

## 12. Verification-rejection groups

Verifier rejection details use this namespace:

| Detail | Name |
|---:|---|
| `1` | `MALFORMED_ARTIFACT` |
| `2` | `LENGTH_OR_ARITHMETIC_OVERFLOW` |
| `3` | `INVALID_FUNCTION_OR_ENTRY` |
| `4` | `INVALID_OPCODE_OR_OPERAND` |
| `5` | `INVALID_TRANSFER_TARGET` |
| `6` | `INCONSISTENT_STACK_MERGE` |
| `7` | `INVALID_CALL_SIGNATURE` |
| `8` | `INVALID_LOCAL_INDEX` |
| `9` | `INVALID_LOOP_SHAPE` |
| `10` | `INVALID_IMPORT_DECLARATION` |
| `11` | `PROFILE_LIMIT_EXCEEDED` |

The compiler is not a security oracle. Every artifact, including output from
the bundled compiler, MUST pass this independent verification before execution.

## 13. Result record

The neutral executor produces a structural run result. It can produce `OK`,
`GUEST_TRAP`, `RESOURCE_EXHAUSTED`, `IMPORT_FAILURE`, `CANCELLED`, or
`HOST_FAILURE`; it does not know module declarations or domain schemas. Its
record contains:

- result class and class-specific detail;
- exact artifact and profile digests;
- entry index and bounded entry name;
- canonical input-value digest and candidate output-value digest;
- trap location as the pair `(function index, function-local instruction
  index)`, never a byte or host address;
- optional bounded explicit-abort code;
- instruction, value-op, and copy-byte usage;
- peak data-stack, call-frame, and loop-frame usage;
- cumulative `output_arena_nodes` and `output_arena_bytes`;
- exact final `output_result_nodes` and `output_result_bytes`;
- input value-node and value-byte counts; and
- one owned structurally valid typed candidate only for `OK`.

The Stage 2 host wraps that record with request, declaration, input/output
schema, policy, and profile-resolution facts. It may additionally produce
`REQUEST_REJECTED`, `PROFILE_MISMATCH`, `VERIFICATION_REJECTED`, or
`OUTPUT_REJECTED`. Only this host invocation result carries external schema
digests.

Neither record's native memory layout is a wire format. Deterministic replay
means identical class/detail, trap pair, usage fields, canonical output bytes,
and output digest—not byte equality of implementation padding or pointers.
Every non-`OK` result has no output value. Unexpected native exceptions MUST be
converted to one `HOST_FAILURE` result through the cleanup/quarantine path.
For `OK`, private result transfer and sealing complete before invocation
cleanup, but public `OK` publication occurs only after cleanup succeeds. The
result-owned copy is then released and scrubbed by the result owner, not by the
invocation cleanup path.

## 14. Host-side integration

Desk, Practice, Agent, and capability-bus integration are host-side consumers
and are not on the critical path for implementing or qualifying the neutral
profile.

A trusted Akashic host is expected to:

1. resolve one digest-pinned module declaration and artifact;
2. obtain an independently verified representation;
3. create a fresh disposable capability-empty child Context;
4. materialize explicit effective budgets;
5. preallocate and zero all invocation buffers;
6. validate and copy the typed input;
7. run the pure VM without exposing Context, services, facets, Mandates, the
   request bus, VFS, native pointers, or callbacks;
8. validate and copy the typed result; and
9. cancel, scrub, and free every invocation-owned object on all exits.

“Capability-empty” describes the guest-visible authority surface. The child
may carry trusted owner, Practice, policy, lifecycle, and budget metadata
needed by the host. None of that metadata, its address, or its services is
placed in a guest value, memory, profile import, or callback.

A later Desk component may publish host-generated capability descriptors for
verified module entries. The handler remains trusted native adapter code; the
guest never supplies an `APP-DESC`, handler XT, service getter, or callback.

The guest profile remains effect-free. An Agent-facing trusted wrapper MAY be
classified as observe-only because it discloses a deterministic result through
the existing Agent accounting path. That wrapper classification grants no
observation or other authority inside the VM.

The neutral ABI includes BYTES. If an Agent/provider codec cannot represent
BYTES, its adapter MUST either omit that entry or use a separately explicit,
bounded encoding contract such as a declared base64 UTF8 envelope. It MUST NOT
narrow the neutral ABI or silently reinterpret BYTES as UTF8.

Practice may durably bind the exact module declaration, artifact, profile,
entry, schemas, and budget policy. Such a binding remains relevance and policy,
not a live VM, handle, grant, or invocation authority.

## 15. Explicit non-goals

This profile does not include:

- arbitrary native Forth or MF64 loading;
- synchronous host imports;
- resource identifiers or locator resolution;
- floating point;
- guest logs or terminal output;
- capability or service calls;
- effect proposals or review suspension;
- persistent VM memory or module state;
- UI lifecycle, drawing, or UIDL callbacks;
- contract caller/storage/gas/log/return/revert behavior; or
- compatibility with the prototype ITC image, entry table, or whitelist.

Any additional profile that binds or admits one of these surfaces requires its
own explicit threat review, canonical descriptor, digest, verifier rules, cost
table, budgets, traps, and qualification cases. It MUST use the same production
runtime architecture and MUST NOT preserve or introduce a simplified parallel
evaluator.
