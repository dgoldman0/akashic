# akashic-itc — General-Purpose ITC Compiler + Interpreter

Indirect-Threaded Code overlay for Megapad-64. Compiles Forth source
text into a cell-stream of whitelist indices and pseudo-ops, then
executes that stream via a table-dispatch inner interpreter.

Every cell in the compiled body is an integer — no native code. This
makes the ITC layer suitable for sandboxing untrusted code: smart
contracts, browser plugins, embedded scripting, REPL sandboxes.

```forth
REQUIRE utils/itc.f
```

Depends on: `string.f` (STR>NUM, STR-PARSE-TOKEN), `guard.f` (concurrency).

---

## Quick Reference

### Whitelist Management

| Word | Stack | Description |
|------|-------|-------------|
| `ITC-WL-ADD` | `( xt flags c-addr u -- )` | Register a word in the whitelist |
| `ITC-WL-FIND` | `( c-addr u -- index -1 \| 0 )` | Lookup word by name |
| `ITC-WL-XT@` | `( index -- xt )` | Get execution token for index |
| `ITC-WL-IMM?` | `( index -- flag )` | Check IMMEDIATE flag |
| `ITC-WL-RESET` | `( -- )` | Clear the entire whitelist |
| `ITC-WL-MAX` | `( -- 256 )` | Maximum whitelist entries |

### Compilation

| Word | Stack | Description |
|------|-------|-------------|
| `ITC-COMPILE` | `( src len buf limit -- entry-count \| -1 )` | Compile source into ITC body |
| `ITC-ENTRY@` | `( index -- name-addr name-len offset )` | Retrieve entry point info |
| `ITC-MAX-ENTRIES` | `( -- 32 )` | Maximum colon definitions |

### Execution

| Word | Stack | Description |
|------|-------|-------------|
| `ITC-EXECUTE` | `( ip rsp-base rsp-size -- fault-code )` | Run ITC body |
| `_ITC-PRE-DISPATCH-XT` | Variable | Callback before each whitelist dispatch |

### Image Serialization

| Word | Stack | Description |
|------|-------|-------------|
| `ITC-SAVE-IMAGE` | `( buf body-addr body-len -- total-len )` | Serialize to portable image |
| `ITC-LOAD-IMAGE` | `( image-addr image-len -- body-addr body-len entry-count \| 0 )` | Load image |

### Pseudo-Op Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `ITC-OP-LIT` | 0 | Next cell is a literal value |
| `ITC-OP-BRANCH` | 1 | Unconditional jump |
| `ITC-OP-0BRANCH` | 2 | Branch if top-of-stack is 0 |
| `ITC-OP-DO` | 3 | Start counted loop |
| `ITC-OP-LOOP` | 4 | End counted loop |
| `ITC-OP-PLOOP` | 5 | +LOOP variant |
| `ITC-OP-EXIT` | 6 | Return from colon definition |
| `ITC-OP-CALL` | 7 | Call another ITC word |

### Fault Codes

| Constant | Value | Description |
|----------|-------|-------------|
| `ITC-OK` | 0 | Success |
| `ITC-FAULT-BAD-OP` | 1 | Index exceeds whitelist count |
| `ITC-FAULT-STACK` | 2 | R-stack over/underflow |
| `ITC-FAULT-ABORT` | 3 | Pre-dispatch callback halted |
| `ITC-FAULT-COMPILE` | 4 | Compilation error |

---

## Whitelist

The whitelist is a flat table of up to 256 entries. Each entry stores
a name (up to 31 characters), flags, and an execution token.

Register words with `ITC-WL-ADD`:

```forth
' DUP  0 S" DUP"  ITC-WL-ADD    \ flags=0 (not IMMEDIATE)
' DROP 0 S" DROP" ITC-WL-ADD
```

The `flags` parameter: bit 0 = IMMEDIATE (reserved for future use;
control flow is currently handled by the compiler directly).

Whitelist indices in the compiled body are offset by 8 (indices 0–7
are reserved for pseudo-ops).

---

## ITC-COMPILE

Compiles Forth-like source text into a cell-stream. The compiler
tokenizes the source buffer, resolves each token against:

1. Built-in keywords (`:`, `;`, `IF`, `ELSE`, `THEN`, `BEGIN`,
   `UNTIL`, `WHILE`, `REPEAT`, `DO`, `LOOP`, `+LOOP`, `RECURSE`,
   `CONSTANT`, `VARIABLE`)
2. Previously defined colon definitions (entry table)
3. Constants/variables (symbol table)
4. The whitelist
5. Number literals

```forth
\ Compile source into a 4KB buffer
CREATE buf 4096 ALLOT
S" : double DUP + ; : main 21 double . ;" buf 4096 ITC-COMPILE
\ Returns entry count (2) on success, -1 on error
```

### VARIABLE support

Set `_ITC-DATA-PTR` and `_ITC-DATA-END` before calling `ITC-COMPILE`
to enable VARIABLE allocation:

```forth
CREATE data-region 1024 ALLOT
data-region _ITC-DATA-PTR !
data-region 1024 + _ITC-DATA-END !
S" VARIABLE X : main 42 X ! X @ . ;" buf 4096 ITC-COMPILE
```

---

## ITC-EXECUTE

Walks the compiled cell-stream, dispatching each cell:

- Indices 0–7 are pseudo-ops handled inline (LIT, BRANCH, etc.)
- Indices 8+ are whitelist lookups → `ITC-WL-XT@ EXECUTE`

The interpreter maintains its own return stack (caller-supplied
memory region) for CALL/EXIT, DO/LOOP, and nested calls.

```forth
CREATE rstk 1024 ALLOT
\ ip = entry offset, rsp-base = rstk, rsp-size = 1024
entry-offset rstk 1024 ITC-EXECUTE   ( -- fault-code )
```

### Pre-dispatch Callback

Set `_ITC-PRE-DISPATCH-XT` to a word with signature
`( index -- continue-flag )`. Called before every whitelist dispatch.
Return 0 to halt execution (fault code = ITC-FAULT-ABORT).

```forth
: my-hook ( index -- flag )  DROP -1 ;   \ always continue
' my-hook _ITC-PRE-DISPATCH-XT !
```

Set to 0 to disable: `0 _ITC-PRE-DISPATCH-XT !`

---

## Image Format

Portable, position-independent serialization:

| Offset | Size | Content |
|--------|------|---------|
| 0 | 1 cell | Magic `0x49544346` ("ITCF") |
| 8 | 1 cell | Version (1) |
| 16 | 1 cell | Entry count |
| 24 | 1 cell | Body size (bytes) |
| 32 | 1 cell | Data size (reserved) |
| 40 | N | Entry table: 32B name-slot + 8B offset each |
| 40+N | M | ITC body |

---

## Concurrency

All public `ITC-` words are serialized via `_itc-guard` (a `GUARD`
from `guard.f`).  The guard is automatically acquired on entry and
released on exit (including on exception via `CATCH`).

The module is **not reentrant** — it uses shared compiler state
(`_ITC-CP`, `_ITC-IP`, `_ITC-STATE`, symbol/entry tables, etc.) and
module-level `VARIABLE`s for both compilation and execution. Concurrent
calls without the guard would corrupt internal state.

---

## Security Model

The ITC overlay provides five security properties:

1. **No native code** — compiled body is integers, not opcodes
2. **Whitelist-only** — tokens resolve against a caller-supplied table
3. **Isolated R-stack** — CALL/EXIT use a software stack, not hardware
4. **Controlled dispatch** — pre-dispatch callback enables gas/tracing
5. **No raw EXECUTE** — omitted from the default whitelist

Consumers (like `contract-vm.f`) add bounds-checked `@`/`!` wrappers
to prevent memory escapes.
