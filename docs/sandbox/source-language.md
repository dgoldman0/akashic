# Canonical restricted sandbox source language

**Status:** Stage 0 language reference, narrowed for active Stage 1

The active compiler retains this document's bounded, non-evaluating grammar
and scalar control/stack/integer/memory forms. Typed-value forms and
production import declarations are deferred from the Stage 1 gate; see
[`stage1-implementation.md`](stage1-implementation.md).

**Source identity:** `org.akashic.sandbox.source`
**Scope:** bounded, non-evaluating compilation of restricted source into the
canonical executable artifact defined by
[`artifact-format.md`](artifact-format.md)

This document ratifies the source language accepted by Akashic's production
sandbox compiler. It is a permanent restricted frontend for the shared
artifact, verifier, profile, and executor architecture. It is not a toy
interpreter, bootstrap syntax, native-Forth subset, compatibility language for
`itc.f`, or disposable frontend intended to be replaced when additional
profiles or imports are added.

The source compiler accepts an exact immutable target profile as a separate API
input. Successful compilation emits one candidate bound to that profile's
semantic tag. The source does not select a profile, grant authority, embed a
module declaration, or bypass independent verification. Durable package
identity and cryptographic digests remain outside the active runtime path.

The security and ownership boundaries in
[`sandbox.md`](sandbox.md),
[`threat-model.md`](threat-model.md), and
[`profile-and-abi.md`](profile-and-abi.md) remain controlling. This document
only defines source bytes and their deterministic lowering.

## 1. Source byte and lexical contract

The compiler receives one explicitly bounded byte span. It first validates the
complete span as UTF-8 and then requires every source byte to be ASCII. A UTF-8
BOM, a non-ASCII code point, NUL, DEL, or any unlisted control byte is invalid.

The only whitespace bytes are:

| Byte | Meaning |
|---:|---|
| `0x09` | horizontal tab |
| `0x0A` | line feed |
| `0x0D` | carriage return |
| `0x20` | space |

Outside a lexical line comment, a token is one maximal nonempty run of printable
ASCII bytes `0x21..0x7e` delimited by whitespace or end of input. Tokens are
case-sensitive. Reserved source words are uppercase. User-defined names are
lowercase and therefore cannot shadow reserved words.

A backslash byte `\` at the beginning of a token starts a lexical line comment.
The compiler discards bytes from that backslash through, but not including, the
next carriage return or line feed. End of input also ends the comment. A
backslash inside another token is invalid. Comments are handled only by the
bounded byte tokenizer: they perform no lookup, execution, macro expansion,
conditional compilation, inclusion, or other evaluation. There is no
parenthesized-comment syntax.

There are no quoted strings, character literals, escapes, source includes,
macros, reader forms, or implementation-defined token classes in this language.

### 1.1 Names

Function names, import-local names, and entry names use exactly:

```text
[a-z][a-z0-9._-]{0,62}
```

They are 1 through 63 ASCII bytes. Function names are unique in the function
namespace, import-local names are unique in the import namespace, and entry
names are unique in the entry namespace. A reference is resolved only in the
namespace required by its source form.

Raw byte comparison defines name equality and ordering. There is no locale,
case folding, Unicode normalization, aliasing, or truncation.

### 1.2 Numbers

All source numbers use canonical decimal ASCII. Hexadecimal, octal, binary, a
leading plus sign, digit separators, decimal points, exponent notation, and
implementation-sized cells are invalid.

A bare runtime integer literal has this grammar:

```text
signed-i64 = "0"
           | [1-9][0-9]*
           | "-"[1-9][0-9]*
```

Its mathematical value must be in
`-9223372036854775808..9223372036854775807`. `-0` and a leading zero on a
multi-digit value are invalid. A valid bare integer emits one `LIT.I64`
instruction containing its complete two's-complement `u64` bit pattern.

Unsigned declaration and instruction operands have this grammar:

```text
unsigned = "0" | [1-9][0-9]*
```

The consuming source form supplies the exact range:

- parameter, result, and local counts must fit `u16` and the target profile;
- an `ABORT` code must be in `0..65535`;
- a local index must fit `u32` and be below the current function's local count;
- profile import IDs and machine-signature IDs must be in
  `1..4294967295`; and
- an entry machine-signature ID must be in `1..4294967295`.

An operand token is syntax owned by the preceding source form. It does not also
emit a runtime literal.

## 2. Top-level grammar

The active Stage 1 compiler accepts the permanent pure-machine subset:

```text
source          = function-declaration { function-declaration }
                  entry-declaration { entry-declaration }

function-declaration
                = FUNCTION function-name
                  PARAMS parameter-count
                  RESULTS result-count
                  LOCALS local-count
                  { form }
                  END

entry-declaration
                = ENTRY entry-name function-name
```

It accepts no import declaration or import call. The broader import grammar
below records the later extension point; it is not an alternate Stage 1 parser
and does not block qualification of the pure runtime.

The grammar below is token grammar. Juxtaposition means whitespace-separated
tokens. Braces mean repetition and brackets mean an optional group; those
metacharacters do not occur in source.

```text
source          = { import-declaration }
                  function-declaration { function-declaration }
                  entry-declaration { entry-declaration }

import-declaration
                = IMPORT import-name profile-import-id machine-signature-id

function-declaration
                = FUNCTION function-name
                  PARAMS parameter-count
                  RESULTS result-count
                  LOCALS local-count
                  { form }
                  END

entry-declaration
                = ENTRY [ SIGNATURE entry-signature-id ]
                  entry-name function-name

form            = simple-form
                | IF { form } [ ELSE { form } ] THEN
                | BEGIN { form } UNTIL
                | BEGIN { form } AGAIN
                | BEGIN { form } WHILE { form } REPEAT
                | DO { form } LOOP
                | DO { form } +LOOP
```

At least one function and one entry are required. Imports, if any, precede all
functions; functions precede all entries. No token may follow the final entry
except whitespace or a line comment.

Omitting `SIGNATURE` selects signature zero, the internal scalar qualification
surface retained for Stage 1 regression. Production pure-computation entries
spell `SIGNATURE 1` explicitly and bind a one-parameter, one-result function.
All entries in one candidate currently use the same signature. A
signature-zero candidate cannot contain typed-value opcodes, so a scalar entry
cannot indirectly reach the production typed surface.

Import declarations must be strictly increasing by numeric profile import ID.
Entry declarations must be strictly increasing by raw entry-name bytes. These
requirements match the canonical artifact table order rather than relying on a
compiler-specific sort.

Functions receive zero-based artifact function indices in source declaration
order. Forward and backward `CALL` references are allowed. Every reference must
resolve exactly once before artifact publication.

An `ENTRY` emits no instruction. It binds the exact entry name to the named
function and target-profile machine-signature ID. The compiler requires that
the function's declared parameter and result counts exactly equal that
signature's machine lowering. Domain schemas remain in the separately owned
module declaration and cannot appear in this source.

An `IMPORT` emits one artifact import record and grants no authority. The target
profile must define the numeric import ID, require the stated machine-signature
ID, and admit the generic typed-import instruction. The profile, verifier, and
runtime binding remain the authorities for the import's exact machine kinds,
cost, implementation, and activation policy. Under an import-free profile,
including `org.akashic.sandbox.pure-compute`, every `IMPORT` declaration and
`IMPORT.CALL` form is a compile error.

## 3. Functions, parameters, and locals

`PARAMS`, `RESULTS`, and `LOCALS` are mandatory even when their value is zero.
There are no inferred function signatures.

Parameters begin on the function's operand stack. They are not implicit locals.
Locals are separate 64-bit cells, initialized to zero on every call, and can be
accessed only by `LOCAL.GET`, `LOCAL.SET`, and `LOCAL.TEE` with an immediate
numeric index. A source function cannot name a caller local or a module global.

`CALL name` resolves to a direct function-table index. A function name by itself
does not call the function. `RETURN` is explicit; `END` emits no implicit
return. Every reachable non-control fallthrough must remain within the
function, and no reachable edge may fall through `END`. Reachable cycles are
valid and need not have a path to `RETURN` or `ABORT`; instruction accounting
and cancellation contain them at runtime.

The compiler checks bounded lexical control and lowers only the closed opcode
set. The independent verifier owns stack-height, call-signature, target, and
reachability proofs from candidate and profile bytes. It rejects reachable
fallthrough through `END`, unreachable instructions, and wrong return shapes;
compiler acceptance never substitutes for verifier acceptance.

Recursion is permitted only when the exact target profile permits it. It remains
bounded by the invocation's instruction and call-frame budgets.

## 4. Exact simple-form lowering

The tables below are complete. A listed source form emits exactly one
instruction except for structured control forms described later. An opcode that
exists in the runtime but is disabled by the exact target profile is a compile
error. An unknown token is never offered to the host dictionary.

### 4.1 Literals, calls, locals, and loop index

| Source form | Opcode | Operand lowering |
|---|---:|---|
| bare `signed-i64` | `0x01 LIT.I64` | complete literal bits in operand B |
| `NOP` | `0x00 NOP` | none |
| `CALL function-name` | `0x05 CALL` | resolved function index in operand A |
| `RETURN` | `0x06 RETURN` | none |
| `ABORT unsigned` | `0x07 ABORT` | `u16` abort code in low operand A |
| `LOCAL.GET unsigned` | `0x08 LOCAL.GET` | checked local index in operand A |
| `LOCAL.SET unsigned` | `0x09 LOCAL.SET` | checked local index in operand A |
| `LOCAL.TEE unsigned` | `0x0a LOCAL.TEE` | checked local index in operand A |
| `R` | `0x0e LOOP.INDEX` | none |

`LIT.I64`, `BR`, `BR.ZERO`, `BR.NONZERO`, `LOOP.ENTER`, `LOOP.NEXT`,
`LOOP.NEXT.BY`, and `LOOP.INDEX` are artifact mnemonics, not alternate source
spellings. Authors use a numeric literal, structured control words, and `R`.

### 4.2 Operand-stack words

| Source token | Opcode |
|---|---:|
| `DROP` | `0x10 DROP` |
| `DUP` | `0x11 DUP` |
| `SWAP` | `0x12 SWAP` |
| `OVER` | `0x13 OVER` |
| `ROT` | `0x14 ROT` |
| `NIP` | `0x15 NIP` |
| `TUCK` | `0x16 TUCK` |
| `2DROP` | `0x17 2DROP` |
| `2DUP` | `0x18 2DUP` |
| `2SWAP` | `0x19 2SWAP` |
| `2OVER` | `0x1a 2OVER` |

### 4.3 Integer, comparison, and bit words

| Source token | Opcode |
|---|---:|
| `I64.ADD` | `0x20 I64.ADD` |
| `I64.SUB` | `0x21 I64.SUB` |
| `I64.MUL` | `0x22 I64.MUL` |
| `I64.DIV.S` | `0x23 I64.DIV.S` |
| `I64.REM.S` | `0x24 I64.REM.S` |
| `I64.DIVMOD.S` | `0x25 I64.DIVMOD.S` |
| `I64.NEG` | `0x26 I64.NEG` |
| `I64.ABS` | `0x27 I64.ABS` |
| `I64.MIN.S` | `0x28 I64.MIN.S` |
| `I64.MAX.S` | `0x29 I64.MAX.S` |
| `I64.INC` | `0x2a I64.INC` |
| `I64.DEC` | `0x2b I64.DEC` |
| `I64.EQ` | `0x2c I64.EQ` |
| `I64.NE` | `0x2d I64.NE` |
| `I64.LT.S` | `0x2e I64.LT.S` |
| `I64.LE.S` | `0x2f I64.LE.S` |
| `I64.GT.S` | `0x30 I64.GT.S` |
| `I64.GE.S` | `0x31 I64.GE.S` |
| `I64.LT.U` | `0x32 I64.LT.U` |
| `I64.LE.U` | `0x33 I64.LE.U` |
| `I64.GT.U` | `0x34 I64.GT.U` |
| `I64.GE.U` | `0x35 I64.GE.U` |
| `I64.ZERO?` | `0x36 I64.ZERO?` |
| `I64.NEGATIVE?` | `0x37 I64.NEGATIVE?` |
| `I64.POSITIVE?` | `0x38 I64.POSITIVE?` |
| `I64.AND` | `0x39 I64.AND` |
| `I64.OR` | `0x3a I64.OR` |
| `I64.XOR` | `0x3b I64.XOR` |
| `I64.NOT` | `0x3c I64.NOT` |
| `I64.SHL` | `0x3d I64.SHL` |
| `I64.SHR.U` | `0x3e I64.SHR.U` |

Arithmetic, booleans, comparisons, shifts, division traps, and wrapping behavior
are exactly those of the target profile. Source spelling adds no alternate
numeric semantics.

### 4.4 Guest linear-memory words

| Source token | Opcode |
|---|---:|
| `MEM.SIZE` | `0x40 MEM.SIZE` |
| `MEM.LOAD8.U` | `0x41 MEM.LOAD8.U` |
| `MEM.STORE8` | `0x42 MEM.STORE8` |
| `MEM.LOAD64` | `0x43 MEM.LOAD64` |
| `MEM.STORE64` | `0x44 MEM.STORE64` |
| `MEM.MOVE` | `0x45 MEM.MOVE` |
| `MEM.FILL` | `0x46 MEM.FILL` |

Every address consumed by these words is a checked offset into the current
invocation's guest linear memory. No source syntax converts a number into a host
address.

### 4.5 Generic typed import call

| Source form | Opcode | Operand lowering |
|---|---:|---|
| `IMPORT.CALL import-name` | `0x50 IMPORT.CALL` | resolved artifact import index in operand A |

The target profile supplies the exact stack effect and deterministic cost.
Compilation resolves only the source declaration and profile metadata. It never
resolves, calls, or stores a native adapter, host word, execution token, or
service address.

### 4.6 Typed-value words

| Source token | Opcode |
|---|---:|
| `V.TYPE` | `0x60 V.TYPE` |
| `V.BOOL.GET` | `0x61 V.BOOL.GET` |
| `V.I64.GET` | `0x62 V.I64.GET` |
| `V.LEN` | `0x63 V.LEN` |
| `V.LIST.GET` | `0x64 V.LIST.GET` |
| `V.MAP.KEY` | `0x65 V.MAP.KEY` |
| `V.MAP.VALUE` | `0x66 V.MAP.VALUE` |
| `V.MAP.FIND` | `0x67 V.MAP.FIND` |
| `V.BLOB.COPY` | `0x68 V.BLOB.COPY` |
| `V.NEW.NULL` | `0x70 V.NEW.NULL` |
| `V.NEW.BOOL` | `0x71 V.NEW.BOOL` |
| `V.NEW.I64` | `0x72 V.NEW.I64` |
| `V.NEW.BYTES` | `0x73 V.NEW.BYTES` |
| `V.NEW.UTF8` | `0x74 V.NEW.UTF8` |
| `V.NEW.LIST` | `0x75 V.NEW.LIST` |
| `V.NEW.MAP` | `0x76 V.NEW.MAP` |

Their stack effects, handle validation, graph bounds, costs, and publication
rules are exactly those of the target profile.

## 5. Structured conditionals and branch loops

Raw branch opcodes and numeric branch targets are not source forms. The compiler
alone derives function-local instruction indices while closing structured
control frames.

### 5.1 `IF`, `ELSE`, and `THEN`

```text
IF true-forms THEN
IF true-forms ELSE false-forms THEN
```

`IF` emits `0x03 BR.ZERO` with a pending target and consumes one flag.

- Without `ELSE`, `THEN` patches that target to the first instruction after the
  conditional.
- With `ELSE`, the compiler patches the `BR.ZERO` target to the first false-arm
  instruction. If the true arm has a live fallthrough, it emits `0x02 BR`
  before the false arm and patches that branch at `THEN` to the first
  instruction after the conditional. If the true arm is terminal on every
  path, it emits no unreachable skip branch.

All live arms must have identical operand-stack height and typed loop state at
the merge. A terminal arm has no merge edge. If every arm is terminal, the
conditional as a whole is terminal and a following form on that path is a
compile error.

### 5.2 `BEGIN` forms

`BEGIN` records the next emitted instruction as a function-local body target.
It emits no instruction by itself.

```text
BEGIN body UNTIL
```

`UNTIL` emits `0x03 BR.ZERO` to the matching `BEGIN` target. It consumes one
flag, repeats while the flag is zero, and falls through while the flag is
nonzero.

```text
BEGIN body AGAIN
```

`AGAIN` emits `0x02 BR` to the matching `BEGIN` target. It may form a
branch-only cycle with no static exit; such a program is valid and terminates
dynamically only through a guest trap, resource exhaustion, or external
cancellation.

```text
BEGIN prefix WHILE body REPEAT
```

`WHILE` emits `0x03 BR.ZERO` with a pending exit target and consumes one flag.
`REPEAT` emits `0x02 BR` to the matching `BEGIN` target, then patches the
`WHILE` exit to the first instruction after that branch.

This language admits exactly one `WHILE` for each `BEGIN`/`REPEAT` form.
Unmatched, crossed, or incorrectly ordered control words are compile errors.

## 6. Counted loops

Counted loops lower only to the production runtime's typed loop instructions.
They never use the operand stack as a return stack, forge a continuation, or
reuse a call frame as raw loop storage. Each call frame owns its own lexically
nested typed loop frames. A callee cannot observe or alter a caller's loop
frames.

### 6.1 `DO`

At runtime `DO` has:

```forth
( limit start -- )
```

It emits `0x0b LOOP.ENTER`. Operand A is patched to the first instruction after
the matching `LOOP` or `+LOOP`. The loop body begins at the instruction
immediately following `LOOP.ENTER`.

`LOOP.ENTER` pops `start` and `limit` and interprets both as signed 64-bit
integers. If `start = limit`, it creates no loop frame and transfers directly
to its exit target. Otherwise it creates one typed lexical loop frame holding
the current index, limit, body target, exit target, and owning call frame, then
enters the body. Equality is the only entry-time zero-trip condition.

### 6.2 `LOOP`

`LOOP` emits `0x0c LOOP.NEXT`, with operand A equal to the first instruction of
the matching loop body. Its source stack effect is:

```forth
( -- )
```

It computes `next = current + 1` using checked signed addition. Overflow traps.
It continues at the body target exactly when `next < limit`; otherwise it pops
the loop frame and falls through to the instruction after `LOOP.NEXT`.

### 6.3 `+LOOP`

`+LOOP` emits `0x0d LOOP.NEXT.BY`, with operand A equal to the first instruction
of the matching loop body. Its source stack effect is:

```forth
( step -- )
```

The step is a signed 64-bit integer and must be nonzero. Zero traps. The
instruction computes `next = current + step` using checked signed addition;
overflow traps.

- For a positive step, it continues exactly when `next < limit`.
- For a negative step, it continues exactly when `next > limit`.
- Otherwise it pops the loop frame and falls through.

No wraparound, unsigned comparison, crossing heuristic, or implementation-native
cell comparison changes these rules.

### 6.4 `R`

Within a lexically enclosing counted loop, `R` emits
`0x0e LOOP.INDEX`:

```forth
( -- index )
```

It pushes the current counter of the innermost lexical counted loop owned by the
current call frame. It does not expose a limit, continuation, return address,
caller loop, or raw loop-frame handle.

`R` outside a lexically enclosing `DO` form is a compile error. The verifier
also rejects `LOOP.INDEX` without matching typed loop state. Nested calls do not
inherit lexical eligibility for `R`.

### 6.5 Structural validation

`DO` and its closing `LOOP` or `+LOOP` must be in the same function and nest
properly with every conditional and branch-loop frame. The compiler patches
both typed loop targets; source cannot supply either target.

The compiler requires lexically matched loop forms and rejects `RETURN` with a
live counted-loop frame. The independent verifier proves loop ownership,
targets, nesting, ordered loop scope, and operand-stack height at every merge
from emitted instructions.

There is no source `LEAVE`, `UNLOOP`, `I`, `J`, return-stack transfer, or
user-visible loop-frame operation. `R` is the loop counter.

## 7. Deliberately absent source capabilities

The source language has no spelling or lookup rule for:

- raw `BR`, `BR.ZERO`, `BR.NONZERO`, `LOOP.ENTER`, `LOOP.NEXT`, or
  `LOOP.NEXT.BY`;
- a byte offset, instruction index, function index, import index, or patch
  address supplied by source;
- native `@`, `!`, `C@`, `C!`, `EXECUTE`, `EVALUATE`, `FIND`, tick, bracket
  tick, `>BODY`, `HERE`, `LATEST`, `ALLOT`, `CREATE`, `DOES>`, or dictionary
  mutation;
- host data-stack or return-stack operations;
- a host pointer, XT, callback, service getter, Context, endpoint, facet,
  Mandate, grant, VFS path, environment variable, clock, randomness source, or
  native error buffer;
- source inclusion, file access, package resolution, network access, dynamic
  loading, native Forth evaluation, or MF64 loading; or
- a module declaration, domain schema, Practice binding, capability request,
  effect proposal, persistent-state declaration, UI callback, or contract
  operation.

A token with one of these spellings is simply an unknown token unless it is an
ordinary lowercase user name in a syntactic name position. The compiler never
asks the ambient dictionary whether an unknown token exists.

A numeric literal equal to a native address or execution token remains inert
integer data. Only the listed checked guest-memory and typed-value operations
interpret cells as anything other than integers.

## 8. Canonical emission

The compiler emits format-1 fixed-width artifact records exactly as specified
by [`artifact-format.md`](artifact-format.md):

- functions occur in source declaration order;
- imports occur in their already-validated increasing profile-import-ID order;
- entries and concatenated entry-name bytes occur in their already-validated
  raw-byte order;
- every instruction is one canonical 16-byte record;
- unused instruction operands, flags, reserved fields, and alignment padding
  are zero;
- function instruction counts are derived from emitted instructions;
- structured targets are function-local instruction indices;
- calls, imports, and entries use resolved table indices; and
- the header contains the exact target-profile digest.

Source bytes, comments, names used only for internal resolution, paths,
timestamps, compiler identity, diagnostics, and module schemas do not enter the
artifact.

For the same exact source byte span, target profile descriptor, and compiler
contract, successful compilation must produce byte-identical candidate artifact
bytes.

## 9. Bounded compilation

Compilation applies checked limits before allocation, token copying, table
growth, target patching, or instruction emission.

| Quantity | Production ceiling |
|---|---:|
| complete source | 65,536 bytes |
| one token | 63 bytes |
| token count, including declaration operands | 16,384 |
| function declarations | 256 |
| entry declarations | 32 |
| import declarations | target-profile ceiling, never above 256 |
| parameter cells per function | 16 |
| result cells per function | 16 |
| local cells per function | 64 |
| nested structured-control frames | 64 |
| emitted instructions | 3,072 |
| emitted instruction bytes | 49,152 |
| unresolved symbol references | 3,072 |
| compiler-owned workspace | 1,048,576 bytes |

The exact target profile may only tighten applicable limits. A disabled feature
has a zero profile ceiling and cannot be enabled by source.

The compiler uses caller-scoped bounded arrays or arenas for tokens, symbols,
control frames, references, and output. Every derived product, sum, aligned
extent, and subspan uses checked arithmetic. Identifier resolution must have a
bounded worst case under the table ceilings; an implementation must not use an
attacker-controlled unbounded search, recursive parser call on the host return
stack, or allocator growth loop.

Tokenization is a forward byte scan. Structured parsing is a forward token scan
with a bounded compiler-owned control stack. Resolution and emission may use
additional bounded passes, but no pass may restart indefinitely or execute
source semantics. Reaching any checked ceiling is a deterministic compile
rejection, never permission to truncate, wrap, omit a declaration, or emit a
partial artifact.

## 10. Compiler validation and errors

Before candidate publication, the compiler validates at least:

1. caller spans, aliases, capacities, and initial destination state;
2. complete UTF-8 and ASCII lexical validity;
3. source, token, count, and workspace limits;
4. exact top-level declaration order and grammar;
5. canonical numeric spellings and ranges;
6. name grammar, uniqueness, and required ordering;
7. target-profile identity, opcode surface, signatures, imports, and ceilings;
8. complete function, import, entry, and local reference resolution;
9. structured-control pairing, nesting, targets, and lexical loop ownership;
10. stack effects, call signatures, return shapes, and control-flow merges;
11. function and instruction reachability and exact import use;
12. canonical artifact geometry and output capacity; and
13. successful independent verification when using a combined
    compile-and-verify API.

Errors are structured compiler results with a bounded error group and, where
available, the offending source byte offset and token length. Diagnostics are
owned sanitized data. They contain no borrowed source pointer, host address,
XT, native throw buffer, dictionary name resolution, or partially emitted
artifact bytes.

The first error is deterministic under the validation order above. An internal
dependency throw is caught at the public compiler boundary, translated to a
compiler host-failure result, and followed by the same cleanup path.

## 11. Publication and cleanup

Compilation constructs all state and candidate bytes privately. On lexical,
syntactic, semantic, profile, capacity, allocation, or internal failure, it:

- publishes no candidate artifact;
- clears or invalidates the complete caller destination;
- releases every compiler-owned allocation;
- restores the documented caller stack state; and
- leaves no current compiler, symbol table, control frame, patch address, or
  target profile in process-global mutable state.

On source-level success, the compiler may atomically publish one complete
canonical candidate artifact. That candidate is still untrusted. The compiler
cannot create or seal a verified plan, and no execution API accepts compiler
success in place of the independent verifier.

A combined convenience API may compile into private storage, independently
verify the complete candidate against the exact profile, and then publish both
the candidate and a separately sealed verified plan. Verifier rejection
invalidates both outputs.

Compiler instances are caller-scoped and may be interleaved without sharing
tokens, names, patches, output buffers, errors, or profile state. Cleanup is
idempotent and scrubs all compiler-owned mutable bytes before allocator reuse
or release.
