# akashic-yaml — YAML 1.2 Reader & Builder for KDOS / Megapad-64

A cursor-based YAML 1.2 library for KDOS Forth.
Parses, navigates, and constructs YAML text using zero-copy `(addr len)` cursor
pairs — no hidden allocations, no dynamic memory.
Supports both block style (indentation-based) and flow style (JSON-like).

```forth
REQUIRE yaml.f
```

`PROVIDED akashic-yaml` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Cursor Model](#cursor-model)
- [Error Handling](#error-handling)
- [Layer 0 — Primitives](#layer-0--primitives)
- [Layer 1 — Type Introspection](#layer-1--type-introspection)
- [Layer 2 — Value Extraction](#layer-2--value-extraction)
- [Layer 3 — Block Scalar Extraction](#layer-3--block-scalar-extraction)
- [Layer 4 — Mapping Navigation](#layer-4--mapping-navigation)
- [Layer 5 — Sequence Navigation](#layer-5--sequence-navigation)
- [Layer 6 — Path Navigation](#layer-6--path-navigation)
- [Layer 7 — Iteration](#layer-7--iteration)
- [Layer 8 — Comparison & Guards](#layer-8--comparison--guards)
- [Layer 9 — Flow Mapping Key Lookup](#layer-9--flow-mapping-key-lookup)
- [Layer 10 — Builder (Emitter)](#layer-10--builder-emitter)
- [Layer 11 — Multi-Document Support](#layer-11--multi-document-support)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Zero-copy** | Reader words return pointers into the original YAML buffer — no intermediate copies unless you explicitly unescape or extract block scalars. |
| **No hidden allocations** | All buffers (unescape targets, block scalar output) are user-provided. The library allocates only module-scoped VARIABLEs. |
| **Composable cursors** | Every navigation word takes `(addr len)` and returns `(addr' len')`, so words chain naturally. |
| **Indent-aware** | `YAML-KEY` searches only at the current indentation level. Block sequences track their base indent for proper scoping. |
| **Dual-style** | Full support for both block style (indentation) and flow style (`{...}`, `[...]`). |
| **Configurable errors** | Abort-on-error or soft-fail with flag checking — your choice, changeable at runtime. |
| **Non-aborting variants** | Navigation words have `?`-suffixed variants returning a flag. |
| **YAML 1.2 Core Schema** | Null (`null`, `~`, empty), booleans (`true`/`false`/`yes`/`no`/`on`/`off`), integers (dec/hex/oct/bin), floats (`.inf`/`.nan`), strings (plain, single-quoted, double-quoted, literal block `|`, folded block `>`). |
| **Multi-document** | Handles `---` / `...` document boundaries with `YAML-NEXT-DOC`. |

---

## Cursor Model

A **cursor** is a standard Forth string pair `( addr len )` pointing into
YAML text. `addr` is the byte address of the current position, `len` is
the number of remaining bytes.

```
YAML text in memory:
  addr ──►server:\n  host: localhost\n  port: 8080\n
           ↑ cursor starts here

After S" server" YAML-KEY:
  addr' ──►\n  host: localhost\n  port: 8080\n
             ↑ value starts (the nested mapping)

After S" host" YAML-KEY:
  addr'' ──►localhost\nport: 8080\n
             ↑ at the plain scalar value

After YAML-GET-STRING:
  ( str-addr 9 )  →  "localhost" (zero-copy into source)
```

**Block-style indentation awareness:**
YAML-KEY records the indentation level of the first key it encounters
and only matches keys at that same level. Nested content at deeper
indentation is automatically skipped over.

> **Important:** Cursors are ephemeral. If you modify the underlying buffer,
> all cursors into it are invalidated. The reader is strictly read-only.

---

## Error Handling

### Variables

| Variable | Purpose |
|----------|---------|
| `YAML-ERR` | Current error code (0 = no error) |
| `YAML-ABORT-ON-ERROR` | If nonzero, `YAML-FAIL` calls `ABORT"` |

### Error Codes

| Constant | Value | Meaning |
|----------|-------|---------|
| `YAML-E-NOT-FOUND` | 1 | Key or path not found |
| `YAML-E-WRONG-TYPE` | 2 | Value is not the expected type |
| `YAML-E-UNTERMINATED` | 3 | Unterminated string |
| `YAML-E-UNEXPECTED` | 4 | Unexpected character |
| `YAML-E-OVERFLOW` | 5 | Buffer overflow |
| `YAML-E-BAD-INDENT` | 6 | Illegal indentation |
| `YAML-E-BAD-SCALAR` | 7 | Malformed scalar |

### Words

```forth
YAML-FAIL       ( err-code -- )   \ Store error; abort if configured
YAML-OK?        ( -- flag )       \ True if no error pending
YAML-CLEAR-ERR  ( -- )            \ Reset error state
```

---

## Layer 0 — Primitives

Low-level cursor movement words.

### YAML-SKIP-WS

```forth
YAML-SKIP-WS  ( addr len -- addr' len' )
```

Skip horizontal whitespace only (space, tab). Does **not** skip newlines.

### YAML-SKIP-COMMENT

```forth
YAML-SKIP-COMMENT  ( addr len -- addr' len' )
```

If at `#`, skip to end of line. No-op otherwise.

### YAML-SKIP-EOL

```forth
YAML-SKIP-EOL  ( addr len -- addr' len' )
```

Skip one end-of-line sequence (CR, LF, or CRLF).

### YAML-SKIP-LINE

```forth
YAML-SKIP-LINE  ( addr len -- addr' len' )
```

Skip past the rest of the current line including its EOL.

### YAML-SKIP-NL

```forth
YAML-SKIP-NL  ( addr len -- addr' len' )
```

Skip all whitespace (including newlines), blank lines, and comments.

### YAML-INDENT

```forth
YAML-INDENT  ( addr len -- n )
```

Count leading spaces on the current line. Only counts ASCII 32 (space).

### YAML-SKIP-DOC-START

```forth
YAML-SKIP-DOC-START  ( addr len -- addr' len' )
```

If at `---`, skip past it and EOL. Otherwise no-op.

### YAML-SKIP-DOC-END

```forth
YAML-SKIP-DOC-END  ( addr len -- addr' len' )
```

If at `...`, skip past it and EOL. Otherwise no-op.

### YAML-SKIP-DQ-STRING

```forth
YAML-SKIP-DQ-STRING  ( addr len -- addr' len' )
```

Skip over a double-quoted `"..."` string (handles backslash escapes).

### YAML-SKIP-SQ-STRING

```forth
YAML-SKIP-SQ-STRING  ( addr len -- addr' len' )
```

Skip over a single-quoted `'...'` string (handles `''` escape).

### YAML-SKIP-FLOW

```forth
YAML-SKIP-FLOW  ( addr len -- addr' len' )
```

Skip a complete flow collection `{...}` or `[...]`, depth-aware.

### YAML-SKIP-BLOCK-SCALAR

```forth
YAML-SKIP-BLOCK-SCALAR  ( addr len -- addr' len' )
```

Skip a block scalar (`|` or `>`) and all its indented content lines.

### YAML-SKIP-VALUE

```forth
YAML-SKIP-VALUE  ( addr len -- addr' len' )
```

Skip any YAML value (string, flow collection, block scalar, plain scalar).

---

## Layer 1 — Type Introspection

### Type Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `YAML-T-ERROR` | 0 | Unknown or error |
| `YAML-T-STRING` | 1 | Any string (plain, quoted, block scalar) |
| `YAML-T-INTEGER` | 2 | Integer |
| `YAML-T-BOOL` | 3 | Boolean |
| `YAML-T-NULL` | 4 | Null (`null`, `~`, empty) |
| `YAML-T-MAPPING` | 5 | Mapping (block `key: val` or flow `{...}`) |
| `YAML-T-SEQUENCE` | 6 | Sequence (block `- item` or flow `[...]`) |
| `YAML-T-FLOAT` | 7 | Float (`.inf`, `.nan`, decimal with `.`/`e`) |

### YAML-TYPE?

```forth
YAML-TYPE?  ( addr len -- type )
```

Return the type constant for the value at cursor.

### Convenience Predicates

```forth
YAML-STRING?    ( addr len -- flag )
YAML-INTEGER?   ( addr len -- flag )
YAML-BOOL?      ( addr len -- flag )
YAML-NULL?      ( addr len -- flag )
YAML-MAPPING?   ( addr len -- flag )
YAML-SEQUENCE?  ( addr len -- flag )
YAML-FLOAT?     ( addr len -- flag )
```

---

## Layer 2 — Value Extraction

### YAML-GET-STRING

```forth
YAML-GET-STRING  ( addr len -- str-addr str-len )
```

Extract a YAML string value. Dispatches based on style:
- `"..."` → double-quoted (inner bytes, zero-copy)
- `'...'` → single-quoted (inner bytes, zero-copy)
- Otherwise → plain scalar (trimmed, zero-copy)

> **Note:** Escape sequences in double-quoted strings are NOT expanded.
> Use `YAML-UNESCAPE` for that. For block scalars (`|`/`>`), use
> `YAML-GET-BLOCK-SCALAR`.

### YAML-UNESCAPE

```forth
YAML-UNESCAPE  ( src slen dest dmax -- len )
```

Unescape a YAML double-quoted string into a user-provided buffer.
Handles all YAML escape sequences:

| Escape | Meaning |
|--------|---------|
| `\\` | Backslash |
| `\"` | Double quote |
| `\n` | Newline (LF) |
| `\r` | Carriage return |
| `\t` | Tab |
| `\b` | Backspace |
| `\f` | Form feed |
| `\0` | Null |
| `\a` | Bell |
| `\e` | Escape (0x1B) |
| `\v` | Vertical tab |
| `\N` | Next line (U+0085) |
| `\_` | Non-breaking space (U+00A0) |
| `\L` | Line separator (U+2028) |
| `\P` | Paragraph separator (U+2029) |
| `\xNN` | 8-bit Unicode |
| `\uNNNN` | 16-bit Unicode |
| `\UNNNNNNNN` | 32-bit Unicode |

### YAML-GET-INT

```forth
YAML-GET-INT  ( addr len -- n )
```

Parse a YAML integer. Supports decimal, `0x` hex, `0o` octal, `0b` binary,
underscore separators, and `+`/`-` signs.

### YAML-GET-BOOL

```forth
YAML-GET-BOOL  ( addr len -- flag )
```

Parse boolean values:
- `true`, `True`, `yes`, `Yes`, `on`, `On` → `-1`
- `false`, `False`, `no`, `No`, `off`, `Off` → `0`

### YAML-GET-FLOAT-STR

```forth
YAML-GET-FLOAT-STR  ( addr len -- str-a str-l )
```

Extract a float value as a raw string token. Megapad-64 has no FPU.

---

## Layer 3 — Block Scalar Extraction

### YAML-GET-BLOCK-SCALAR

```forth
YAML-GET-BLOCK-SCALAR  ( addr len dest dmax -- len )
```

Extract a literal (`|`) or folded (`>`) block scalar into a buffer.
Handles chomp indicators:

| Header | Behavior |
|--------|----------|
| `|` or `>` | **Clip** — single trailing newline (default) |
| `|-` or `>-` | **Strip** — no trailing newline |
| `|+` or `>+` | **Keep** — all trailing newlines preserved |
| `|2` or `>2` | Explicit indentation indicator |

Literal (`|`) preserves newlines as-is.
Folded (`>`) replaces single newlines with spaces (blank lines preserved).

```forth
CREATE buf 1024 ALLOT
yaml-cursor YAML-GET-BLOCK-SCALAR  ( -- actual-len )
buf SWAP TYPE
```

---

## Layer 4 — Mapping Navigation

### YAML-KEY

```forth
YAML-KEY  ( addr len kaddr klen -- vaddr vlen )
```

Find `key: value` in a block mapping. Indent-aware — searches only at
the base indentation level (does not match keys inside nested structures).
Stops at document boundaries (`---`, `...`).

```forth
S" host" YAML-KEY YAML-GET-STRING   \ extract host value
```

### YAML-KEY?

```forth
YAML-KEY?  ( addr len kaddr klen -- vaddr vlen flag )
```

Non-aborting variant. Returns `-1` on success, `0` if not found.

### YAML-HAS?

```forth
YAML-HAS?  ( addr len kaddr klen -- flag )
```

Test if a key exists without moving the cursor.

---

## Layer 5 — Sequence Navigation

### YAML-ENTER

```forth
YAML-ENTER  ( addr len -- addr' len' )
```

Enter a collection:
- Flow `{` or `[` → skip the opening delimiter
- Block sequence `- ` → skip the dash and space
- Block mapping → no-op (already positioned at content)

### YAML-SEQ-INIT

```forth
YAML-SEQ-INIT  ( addr len -- addr' len' )
```

Initialize block sequence iteration. Records the base indent and
skips past the first `- `.

### YAML-BLOCK-NEXT

```forth
YAML-BLOCK-NEXT  ( addr len -- addr' len' flag )
```

Advance to the next item in a block sequence. Flag `-1` if found, `0` at end.

### YAML-FLOW-NEXT

```forth
YAML-FLOW-NEXT  ( addr len -- addr' len' flag )
```

Advance to the next element in a flow collection `[...]` or `{...}`.

### YAML-NTH

```forth
YAML-NTH  ( addr len n -- addr' len' )
```

Jump to the *n*th item (0-based) in a block sequence.

### YAML-COUNT

```forth
YAML-COUNT  ( addr len -- n )
```

Count items in a block sequence.

### YAML-FLOW-COUNT

```forth
YAML-FLOW-COUNT  ( addr len -- n )
```

Count elements in a flow collection (cursor must be past `[`/`{`).

---

## Layer 6 — Path Navigation

### YAML-PATH

```forth
YAML-PATH  ( addr len path-a path-l -- addr' len' )
```

Navigate a dot-separated path through block mappings.
Each segment is a key name.

```forth
doc doc-len S" server.host" YAML-PATH YAML-GET-STRING
\ → "localhost"
```

### YAML-PATH?

```forth
YAML-PATH?  ( addr len path-a path-l -- addr' len' flag )
```

Non-aborting variant.

---

## Layer 7 — Iteration

### YAML-EACH-KEY

```forth
YAML-EACH-KEY  ( addr len -- addr' len' key-a key-l flag )
```

Iterate key-value pairs in a block mapping. Each call returns the next
key name and positions cursor at its value. Flag `-1` if found, `0` at end.

> **Important:** Call `YAML-EACH-RESET` before starting a new iteration loop.
> After processing a value, advance past it with `YAML-SKIP-LINE` before
> calling `YAML-EACH-KEY` again.

### YAML-EACH-RESET

```forth
YAML-EACH-RESET  ( -- )
```

Reset iteration state for `YAML-EACH-KEY`.

---

## Layer 8 — Comparison & Guards

### Comparison

```forth
YAML-STRING=  ( addr len saddr slen -- flag )   \ Compare string value
YAML-INT=     ( addr len n -- flag )             \ Compare integer value
```

### Type Guards

Assert and pass through, or fail with `YAML-E-WRONG-TYPE`:

```forth
YAML-EXPECT-STRING    ( addr len -- addr len )
YAML-EXPECT-INTEGER   ( addr len -- addr len )
YAML-EXPECT-BOOL      ( addr len -- addr len )
YAML-EXPECT-NULL      ( addr len -- addr len )
YAML-EXPECT-MAPPING   ( addr len -- addr len )
YAML-EXPECT-SEQUENCE  ( addr len -- addr len )
```

---

## Layer 9 — Flow Mapping Key Lookup

### YAML-FKEY

```forth
YAML-FKEY  ( addr len kaddr klen -- vaddr vlen )
```

Find a key in a flow mapping `{key: val, key: val}`.
Cursor must be past the opening `{`.

```forth
flow-map YAML-ENTER S" name" YAML-FKEY YAML-GET-STRING TYPE
```

---

## Layer 10 — Builder (Emitter)

Build YAML text programmatically with proper indentation.

### Vectored Output

| Word | Stack | Description |
|------|-------|-------------|
| `YAML-EMIT-XT` | `( -- addr )` | Variable: char output vector `( c -- )` |
| `YAML-TYPE-XT` | `( -- addr )` | Variable: string output vector `( a u -- )` |
| `YAML-EMIT` | `( c -- )` | Emit char through vector |
| `YAML-TYPE` | `( a u -- )` | Emit string through vector |

### Buffer Output

| Word | Stack | Description |
|------|-------|-------------|
| `YAML-SET-OUTPUT` | `( addr max -- )` | Redirect output to buffer |
| `YAML-OUTPUT-RESULT` | `( -- addr len )` | Get buffer contents |
| `YAML-OUTPUT-RESET` | `( -- )` | Reset write position |
| `YAML-BUILD-RESET` | `( -- )` | Reset all builder state |
| `YAML-SET-INDENT` | `( n -- )` | Set spaces per indent level (default: 2) |

### Document Markers

```forth
YAML-DOC-START  ( -- )    \ Emit ---
YAML-DOC-END    ( -- )    \ Emit ...
```

### Block-Style Mapping

| Word | Stack | Description |
|------|-------|-------------|
| `YAML-KEY:` | `( addr len -- )` | Emit `key: ` at current indent |
| `YAML-MAP-OPEN` | `( addr len -- )` | Emit `key:` + newline, increase indent |
| `YAML-MAP-CLOSE` | `( -- )` | Decrease indent level |

### Block-Style Sequence

```forth
YAML-SEQ-ITEM  ( -- )    \ Emit "- " at current indent
```

### Scalar Values

| Word | Stack | Description |
|------|-------|-------------|
| `YAML-STR` | `( addr len -- )` | Emit plain string |
| `YAML-DQ-STR` | `( addr len -- )` | Emit `"string"` |
| `YAML-ESTR` | `( addr len -- )` | Emit `"string"` with escaping |
| `YAML-NUM` | `( n -- )` | Emit integer |
| `YAML-INT` | `( n -- )` | Emit integer (alias) |
| `YAML-TRUE` | `( -- )` | Emit `true` |
| `YAML-FALSE` | `( -- )` | Emit `false` |
| `YAML-NULL` | `( -- )` | Emit `null` |
| `YAML-BOOL` | `( flag -- )` | Emit `true` or `false` |

### Key-Value Convenience

| Word | Stack | Description |
|------|-------|-------------|
| `YAML-KV-STR` | `( ka kl va vl -- )` | `key: value` (plain string) |
| `YAML-KV-DQ` | `( ka kl va vl -- )` | `key: "value"` |
| `YAML-KV-ESTR` | `( ka kl va vl -- )` | `key: "value"` (escaped) |
| `YAML-KV-INT` | `( ka kl n -- )` | `key: 42` |
| `YAML-KV-BOOL` | `( ka kl flag -- )` | `key: true/false` |
| `YAML-KV-NULL` | `( ka kl -- )` | `key: null` |

### Flow-Style Output

| Word | Stack | Description |
|------|-------|-------------|
| `YAML-F{` | `( -- )` | Emit `{` |
| `YAML-F}` | `( -- )` | Emit `}` |
| `YAML-F[` | `( -- )` | Emit `[` |
| `YAML-F]` | `( -- )` | Emit `]` |
| `YAML-FKEY:` | `( addr len -- )` | Emit `key: ` (with auto-comma) |
| `YAML-FVAL-STR` | `( addr len -- )` | Emit value (auto-comma) |
| `YAML-FVAL-DQ` | `( addr len -- )` | Emit `"value"` (auto-comma) |
| `YAML-FVAL-INT` | `( n -- )` | Emit number (auto-comma) |
| `YAML-FVAL-BOOL` | `( flag -- )` | Emit bool (auto-comma) |
| `YAML-FVAL-NULL` | `( -- )` | Emit null (auto-comma) |

---

## Layer 11 — Multi-Document Support

### YAML-NEXT-DOC

```forth
YAML-NEXT-DOC  ( addr len -- addr' len' flag )
```

Advance to the next document in a multi-document YAML stream.
Skips past `---` or `...` boundaries. Flag `-1` if another document
was found, `0` at end of stream.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| **Error Handling** | | |
| `YAML-FAIL` | `( err -- )` | Store error code |
| `YAML-OK?` | `( -- flag )` | True if no error |
| `YAML-CLEAR-ERR` | `( -- )` | Reset error state |
| **Primitives** | | |
| `YAML-SKIP-WS` | `( a l -- a' l' )` | Skip spaces/tabs |
| `YAML-SKIP-COMMENT` | `( a l -- a' l' )` | Skip `#` comment |
| `YAML-SKIP-EOL` | `( a l -- a' l' )` | Skip one EOL |
| `YAML-SKIP-LINE` | `( a l -- a' l' )` | Skip entire line |
| `YAML-SKIP-NL` | `( a l -- a' l' )` | Skip all whitespace + comments |
| `YAML-INDENT` | `( a l -- n )` | Measure leading spaces |
| `YAML-SKIP-DOC-START` | `( a l -- a' l' )` | Skip `---` |
| `YAML-SKIP-DOC-END` | `( a l -- a' l' )` | Skip `...` |
| `YAML-SKIP-DQ-STRING` | `( a l -- a' l' )` | Skip `"..."` |
| `YAML-SKIP-SQ-STRING` | `( a l -- a' l' )` | Skip `'...'` |
| `YAML-SKIP-FLOW` | `( a l -- a' l' )` | Skip `{...}` / `[...]` |
| `YAML-SKIP-BLOCK-SCALAR` | `( a l -- a' l' )` | Skip `|`/`>` block |
| `YAML-SKIP-VALUE` | `( a l -- a' l' )` | Skip any value |
| **Type Introspection** | | |
| `YAML-TYPE?` | `( a l -- type )` | Type constant for value |
| `YAML-STRING?` | `( a l -- flag )` | Is string? |
| `YAML-INTEGER?` | `( a l -- flag )` | Is integer? |
| `YAML-BOOL?` | `( a l -- flag )` | Is boolean? |
| `YAML-NULL?` | `( a l -- flag )` | Is null? |
| `YAML-MAPPING?` | `( a l -- flag )` | Is mapping? |
| `YAML-SEQUENCE?` | `( a l -- flag )` | Is sequence? |
| `YAML-FLOAT?` | `( a l -- flag )` | Is float? |
| **Value Extraction** | | |
| `YAML-GET-STRING` | `( a l -- sa sl )` | Extract string (zero-copy) |
| `YAML-UNESCAPE` | `( src sl dst mx -- n )` | Unescape to buffer |
| `YAML-GET-INT` | `( a l -- n )` | Parse integer |
| `YAML-GET-BOOL` | `( a l -- flag )` | Parse boolean |
| `YAML-GET-FLOAT-STR` | `( a l -- sa sl )` | Float as raw string |
| `YAML-GET-BLOCK-SCALAR` | `( a l d mx -- n )` | Extract block scalar |
| **Mapping Navigation** | | |
| `YAML-KEY` | `( a l ka kl -- va vl )` | Find key (fail) |
| `YAML-KEY?` | `( a l ka kl -- va vl f )` | Find key (flag) |
| `YAML-HAS?` | `( a l ka kl -- f )` | Test key exists |
| **Sequence Navigation** | | |
| `YAML-ENTER` | `( a l -- a' l' )` | Enter collection |
| `YAML-SEQ-INIT` | `( a l -- a' l' )` | Init block sequence |
| `YAML-BLOCK-NEXT` | `( a l -- a' l' f )` | Next block seq item |
| `YAML-FLOW-NEXT` | `( a l -- a' l' f )` | Next flow element |
| `YAML-NTH` | `( a l n -- a' l' )` | Jump to nth item |
| `YAML-COUNT` | `( a l -- n )` | Count block seq items |
| `YAML-FLOW-COUNT` | `( a l -- n )` | Count flow elements |
| **Path Navigation** | | |
| `YAML-PATH` | `( a l pa pl -- a' l' )` | Dotted path (fail) |
| `YAML-PATH?` | `( a l pa pl -- a' l' f )` | Dotted path (flag) |
| **Iteration** | | |
| `YAML-EACH-KEY` | `( a l -- a' l' ka kl f )` | Iterate mapping keys |
| `YAML-EACH-RESET` | `( -- )` | Reset iteration state |
| **Comparison / Guards** | | |
| `YAML-STRING=` | `( a l sa sl -- f )` | Compare string value |
| `YAML-INT=` | `( a l n -- f )` | Compare integer value |
| `YAML-EXPECT-STRING` | `( a l -- a l )` | Guard: must be string |
| `YAML-EXPECT-INTEGER` | `( a l -- a l )` | Guard: must be integer |
| `YAML-EXPECT-BOOL` | `( a l -- a l )` | Guard: must be boolean |
| `YAML-EXPECT-NULL` | `( a l -- a l )` | Guard: must be null |
| `YAML-EXPECT-MAPPING` | `( a l -- a l )` | Guard: must be mapping |
| `YAML-EXPECT-SEQUENCE` | `( a l -- a l )` | Guard: must be sequence |
| **Flow Key Lookup** | | |
| `YAML-FKEY` | `( a l ka kl -- va vl )` | Key in flow `{...}` |
| **Multi-Document** | | |
| `YAML-NEXT-DOC` | `( a l -- a' l' f )` | Advance to next document |
| **Builder** | | |
| `YAML-SET-OUTPUT` | `( a m -- )` | Redirect to buffer |
| `YAML-OUTPUT-RESULT` | `( -- a l )` | Get buffer contents |
| `YAML-BUILD-RESET` | `( -- )` | Reset builder state |
| `YAML-DOC-START` | `( -- )` | Emit `---` |
| `YAML-DOC-END` | `( -- )` | Emit `...` |
| `YAML-KEY:` | `( a l -- )` | Emit `key: ` |
| `YAML-MAP-OPEN` | `( a l -- )` | Start nested mapping |
| `YAML-MAP-CLOSE` | `( -- )` | End nested mapping |
| `YAML-SEQ-ITEM` | `( -- )` | Emit `- ` |
| `YAML-STR` | `( a l -- )` | Emit plain string |
| `YAML-DQ-STR` | `( a l -- )` | Emit quoted string |
| `YAML-ESTR` | `( a l -- )` | Emit escaped string |
| `YAML-NUM` | `( n -- )` | Emit number |
| `YAML-BOOL` | `( f -- )` | Emit true/false |
| `YAML-NULL` | `( -- )` | Emit null |
| `YAML-KV-STR` | `( ka kl va vl -- )` | key: value |
| `YAML-KV-INT` | `( ka kl n -- )` | key: n |
| `YAML-KV-BOOL` | `( ka kl f -- )` | key: bool |
| `YAML-KV-NULL` | `( ka kl -- )` | key: null |

### Constants

```
YAML-T-ERROR    = 0      YAML-E-NOT-FOUND    = 1
YAML-T-STRING   = 1      YAML-E-WRONG-TYPE   = 2
YAML-T-INTEGER  = 2      YAML-E-UNTERMINATED = 3
YAML-T-BOOL     = 3      YAML-E-UNEXPECTED   = 4
YAML-T-NULL     = 4      YAML-E-OVERFLOW     = 5
YAML-T-MAPPING  = 5      YAML-E-BAD-INDENT   = 6
YAML-T-SEQUENCE = 6      YAML-E-BAD-SCALAR   = 7
YAML-T-FLOAT    = 7
```

---

## Cookbook

### Read a flat key

```forth
doc doc-len S" name" YAML-KEY YAML-GET-STRING
\ ( str-addr str-len )  →  "Alice"
```

### Read from nested mapping

```forth
doc doc-len
S" server" YAML-KEY       \ cursor at nested mapping
S" host" YAML-KEY         \ find host within server's block
YAML-GET-STRING TYPE      \ prints "localhost"
```

### Use dotted path shortcut

```forth
doc doc-len S" server.port" YAML-PATH YAML-GET-INT
\ → 8080
```

### Iterate block sequence

```forth
doc doc-len S" items" YAML-KEY
YAML-SEQ-INIT                       \ enter first item
BEGIN
    YAML-GET-STRING TYPE CR
    YAML-BLOCK-NEXT                  \ advance to next
WHILE REPEAT
```

### Count sequence items

```forth
doc doc-len S" items" YAML-KEY
YAML-COUNT .                         \ prints number of items
```

### Access nth sequence item

```forth
doc doc-len S" items" YAML-KEY
2 YAML-NTH                          \ jump to third item (0-based)
YAML-GET-STRING TYPE
```

### Flow collection access

```forth
\ Given: colors: [red, green, blue]
doc doc-len S" colors" YAML-KEY
YAML-ENTER                           \ past [
\ Now at first element
YAML-GET-STRING TYPE                 \ "red"
```

### Flow mapping key lookup

```forth
\ Given: point: {x: 10, y: 20}
doc doc-len S" point" YAML-KEY
YAML-ENTER                           \ past {
S" y" YAML-FKEY YAML-GET-INT .      \ prints 20
```

### Safe key lookup with fallback

```forth
doc doc-len
S" nickname" YAML-KEY?
IF   YAML-GET-STRING TYPE
ELSE ." Anonymous"
THEN
```

### Multi-document stream

```forth
\ Process all documents:
doc doc-len
YAML-SKIP-DOC-START
BEGIN
    \ ... process current document ...
    YAML-NEXT-DOC
WHILE REPEAT
2DROP
```

### Build YAML to buffer

```forth
CREATE out 1024 ALLOT
out 1024 YAML-SET-OUTPUT
YAML-BUILD-RESET

YAML-DOC-START
S" name" S" Alice" YAML-KV-STR
S" age" 30 YAML-KV-INT
S" active" -1 YAML-KV-BOOL
S" tags" YAML-MAP-OPEN
  YAML-SEQ-ITEM S" admin" YAML-STR
  YAML-SEQ-ITEM S" user" YAML-STR
YAML-MAP-CLOSE

YAML-OUTPUT-RESULT TYPE
```

Output:
```yaml
---
name: Alice
age: 30
active: true
tags:
  - admin
  - user
```

### Build flow-style inline

```forth
YAML-F{ S" x" YAML-FKEY: 10 YAML-FVAL-INT
        S" y" YAML-FKEY: 20 YAML-FVAL-INT YAML-F}
\ produces: {x: 10, y: 20}
```

### Unescape a double-quoted string

```forth
CREATE ubuf 512 ALLOT
doc doc-len S" message" YAML-KEY YAML-GET-STRING
ubuf 512 YAML-UNESCAPE
ubuf SWAP TYPE   \ prints unescaped text
```

---

## Internal Words

These are prefixed with `_YAML-` or `_Y` and are not part of the public API.

| Word | Purpose |
|------|---------|
| `_YAML-FAIL-00` | Fail and push `0 0` |
| `_YAML-SKIP-INDENT` | Skip leading spaces |
| `_YAML-AT-EOL?` | Test for end-of-line |
| `_YAML-3DASH?` | Test for `---` marker |
| `_YAML-3DOT?` | Test for `...` marker |
| `_YAML-IS-NULL?` | Null value detection |
| `_YAML-IS-BOOL?` | Boolean value detection |
| `_YAML-IS-INT?` | Integer value detection |
| `_YAML-IS-FLOAT?` | Float value detection |
| `_YAML-AT-MAP-KEY?` | Map key pattern detection |
| `_YAML-AT-SEQ-ITEM?` | Sequence `- ` detection |
| `_YAML-EXTRACT-KEY` | Parse key from mapping line |
| `_YAML-SKIP-PLAIN-SCALAR` | Skip unquoted scalar |
| `_YAML-BLOCK-HEADER` | Parse `|`/`>` header |
| `_YSV-DEPTH` | Flow skip depth counter |
| `_YK-KA`, `_YK-KL`, `_YK-BASE` | Key lookup state |
| `_YBN-BASE` | Block sequence base indent |
| `_YP-PA`, `_YP-PL` | Path navigation state |
| `_YEK-BASE`, `_YEK-INIT` | Iteration state |
| `_YU-DST`, `_YU-MAX`, `_YU-POS` | Unescape state |
| `_YB-BUF`, `_YB-MAX`, `_YB-POS` | Buffer output state |
| `_YB-LEVEL`, `_YB-INDENT-SIZE` | Builder indentation |
| `_YN-BUF` | Number conversion buffer |
| `_YFC-NEED` | Flow comma state |
