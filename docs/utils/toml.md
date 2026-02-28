# akashic-toml — TOML v1.0 Reader for KDOS / Megapad-64

A zero-copy, cursor-based TOML 1.0 reader for KDOS Forth.
Parses, navigates, and extracts values from TOML text using `(addr len)`
cursor pairs — no hidden allocations, no dynamic memory.

```forth
REQUIRE toml.f
```

`PROVIDED akashic-toml` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Cursor Model](#cursor-model)
- [Error Handling](#error-handling)
- [Layer 0 — Primitives](#layer-0--primitives)
- [Layer 1 — Type Introspection](#layer-1--type-introspection)
- [Layer 2 — Value Extraction](#layer-2--value-extraction)
- [Layer 3 — Table Navigation](#layer-3--table-navigation)
- [Layer 4 — Key Navigation](#layer-4--key-navigation)
- [Layer 5 — Path Navigation](#layer-5--path-navigation)
- [Layer 6 — Array & Inline-Table Navigation](#layer-6--array--inline-table-navigation)
- [Layer 7 — Iteration](#layer-7--iteration)
- [Layer 8 — Inline-Table Key Lookup](#layer-8--inline-table-key-lookup)
- [Layer 9 — Convenience & Guards](#layer-9--convenience--guards)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Zero-copy** | Reader words return pointers into the original TOML buffer — no intermediate copies. |
| **No hidden allocations** | All buffers (unescape targets) are user-provided. The library uses only module-scoped VARIABLEs. |
| **Composable cursors** | Every navigation word takes `(addr len)` and returns `(addr' len')`, so words chain naturally. |
| **Section-aware** | `TOML-FIND-TABLE` locates `[table]` headers; `TOML-KEY` searches only the current scope. |
| **Configurable errors** | Abort-on-error or soft-fail with flag checking — your choice, changeable at runtime. |
| **Non-aborting variants** | Every navigation word has a `?`-suffixed variant that returns a flag instead of aborting. |
| **TOML 1.0 compliant** | Basic / literal strings, multiline `"""` / `'''`, integers (dec/hex/oct/bin with `_`), booleans, arrays, inline tables, `[[array-of-tables]]`. |

---

## Cursor Model

A **cursor** is a standard Forth string pair `( addr len )` pointing into
TOML text. `addr` is the byte address of the current position, `len` is
the number of remaining bytes.

```
TOML text in memory:
  addr ──►[server]\nhost = "localhost"\nport = 8080\n
           ↑ cursor starts here

After S" server" TOML-FIND-TABLE:
  addr' ──►host = "localhost"\nport = 8080\n
            ↑ body of [server]

After S" host" TOML-KEY:
  addr'' ──►"localhost"\nport = 8080\n
             ↑ at the value

After TOML-GET-STRING:
  ( str-addr 9 )  →  "localhost" (zero-copy into source)
```

> **Important:** Cursors are ephemeral. If you modify the underlying buffer,
> all cursors into it are invalidated. The reader is strictly read-only.

---

## Error Handling

### Variables

| Variable | Purpose |
|----------|---------|
| `TOML-ERR` | Current error code (0 = no error) |
| `TOML-ABORT-ON-ERROR` | If nonzero, `TOML-FAIL` calls `ABORT"` |

### Error Codes

| Constant | Value | Meaning |
|----------|-------|---------|
| `TOML-E-NOT-FOUND` | 1 | Key or table not found |
| `TOML-E-WRONG-TYPE` | 2 | Value is not the expected type |
| `TOML-E-UNTERMINATED` | 3 | Unterminated string |
| `TOML-E-UNEXPECTED` | 4 | Unexpected character |
| `TOML-E-OVERFLOW` | 5 | Numeric overflow |
| `TOML-E-BAD-KEY` | 6 | Malformed key |
| `TOML-E-BAD-INT` | 7 | Malformed integer |

### Words

```forth
TOML-FAIL       ( err-code -- )   \ Store error; abort if configured
TOML-OK?        ( -- flag )       \ True if no error pending
TOML-CLEAR-ERR  ( -- )            \ Reset error state
```

---

## Layer 0 — Primitives

Low-level cursor movement words.

### TOML-SKIP-WS

```forth
TOML-SKIP-WS  ( addr len -- addr' len' )
```

Skip horizontal whitespace (space, tab) only.

### TOML-SKIP-COMMENT

```forth
TOML-SKIP-COMMENT  ( addr len -- addr' len' )
```

Skip a `#` comment through end of line. No-op if cursor is not at `#`.

### TOML-SKIP-EOL

```forth
TOML-SKIP-EOL  ( addr len -- addr' len' )
```

Skip one end-of-line sequence (CR, LF, or CRLF).

### TOML-SKIP-LINE

```forth
TOML-SKIP-LINE  ( addr len -- addr' len' )
```

Advance past the current line including its EOL.

### TOML-SKIP-NL

```forth
TOML-SKIP-NL  ( addr len -- addr' len' )
```

Skip all whitespace (including newlines) and comments.
Use this to advance between logical tokens.

### TOML-SKIP-BASIC-STRING

```forth
TOML-SKIP-BASIC-STRING  ( addr len -- addr' len' )
```

Skip over a basic `"..."` string (handles backslash escapes).

### TOML-SKIP-LITERAL-STRING

```forth
TOML-SKIP-LITERAL-STRING  ( addr len -- addr' len' )
```

Skip over a literal `'...'` string.

### TOML-SKIP-ML-BASIC

```forth
TOML-SKIP-ML-BASIC  ( addr len -- addr' len' )
```

Skip over a multiline basic `"""..."""` string.

### TOML-SKIP-ML-LITERAL

```forth
TOML-SKIP-ML-LITERAL  ( addr len -- addr' len' )
```

Skip over a multiline literal `'''...'''` string.

### TOML-SKIP-STRING

```forth
TOML-SKIP-STRING  ( addr len -- addr' len' )
```

Dispatch to the correct string skipper based on the opening delimiter.

### TOML-SKIP-VALUE

```forth
TOML-SKIP-VALUE  ( addr len -- addr' len' )
```

Skip any TOML value (string, number, boolean, array, inline table).

---

## Layer 1 — Type Introspection

Determine the type of a TOML value at the cursor without consuming it.

### Type Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `TOML-T-ERROR` | 0 | Unknown or error |
| `TOML-T-STRING` | 1 | Basic or literal string |
| `TOML-T-INTEGER` | 2 | Integer |
| `TOML-T-FLOAT` | 3 | Floating-point |
| `TOML-T-BOOL` | 4 | Boolean (`true` / `false`) |
| `TOML-T-DATETIME` | 5 | Date/time value |
| `TOML-T-ARRAY` | 6 | Array `[...]` |
| `TOML-T-INLINE-TABLE` | 7 | Inline table `{...}` |

### TOML-TYPE?

```forth
TOML-TYPE?  ( addr len -- type )
```

Return the type constant for the value at cursor.

### Convenience Predicates

```forth
TOML-STRING?        ( addr len -- flag )
TOML-INTEGER?       ( addr len -- flag )
TOML-FLOAT?         ( addr len -- flag )
TOML-BOOL?          ( addr len -- flag )
TOML-DATETIME?      ( addr len -- flag )
TOML-ARRAY?         ( addr len -- flag )
TOML-INLINE-TABLE?  ( addr len -- flag )
```

Each returns TRUE if the value at cursor matches the respective type.

---

## Layer 2 — Value Extraction

### TOML-GET-STRING

```forth
TOML-GET-STRING  ( addr len -- str-addr str-len )
```

Extract a TOML string value. Dispatches to the correct parser
(basic, literal, multiline basic, multiline literal).
Returns a zero-copy pointer into the source buffer (without quotes).

> **Note:** Escape sequences (`\n`, `\t`, `\uXXXX`, etc.) are *not*
> expanded by `TOML-GET-STRING`. Use `TOML-UNESCAPE` for that.

### TOML-UNESCAPE

```forth
TOML-UNESCAPE  ( src slen dest dmax -- len )
```

Unescape a TOML basic string into a user-provided buffer.
Handles: `\\`, `\"`, `\n`, `\t`, `\r`, `\b`, `\f`,
`\uXXXX` (BMP), `\UXXXXXXXX` (full Unicode via UTF-8 encoding).
Returns the actual length written.

```forth
CREATE ubuf 256 ALLOT
str-addr str-len ubuf 256 TOML-UNESCAPE  ( -- actual-len )
ubuf SWAP TYPE
```

### TOML-GET-INT

```forth
TOML-GET-INT  ( addr len -- n )
```

Parse a TOML integer. Supports:
- Decimal: `42`, `+42`, `-17`, `1_000`
- Hexadecimal: `0xDEAD_BEEF`
- Octal: `0o755`
- Binary: `0b1010`
- Underscore separators in all bases

### TOML-GET-BOOL

```forth
TOML-GET-BOOL  ( addr len -- flag )
```

Parse `true` → -1, `false` → 0.

### TOML-GET-FLOAT-STR

```forth
TOML-GET-FLOAT-STR  ( addr len -- str-a str-l )
```

Extract a float value as a raw string token (no numeric conversion).
Megapad-64 has no FPU; callers use this with `fp32.f` or `fp16.f`.

### TOML-GET-DATETIME-STR

```forth
TOML-GET-DATETIME-STR  ( addr len -- str-a str-l )
```

Extract a datetime token as a raw string (same implementation as
`TOML-GET-FLOAT-STR`).

---

## Layer 3 — Table Navigation

### TOML-FIND-TABLE

```forth
TOML-FIND-TABLE  ( addr len name-a name-l -- body-a body-l )
```

Find the `[name]` table header in the document and return a cursor
to its body (the lines between this header and the next header).

Aborts with `TOML-E-NOT-FOUND` if not found (unless aborting is
disabled).

```forth
doc doc-len S" database" TOML-FIND-TABLE
\ cursor now at body of [database]
```

### TOML-FIND-TABLE?

```forth
TOML-FIND-TABLE?  ( addr len name-a name-l -- body-a body-l flag )
```

Non-aborting variant. Returns flag: TRUE if found, FALSE otherwise.

### TOML-FIND-ATABLE

```forth
TOML-FIND-ATABLE  ( addr len name-a name-l n -- body-a body-l )
```

Find the *n*th (0-based) `[[name]]` array-of-tables entry and return
a cursor to its body.

```forth
doc doc-len S" products" 0 TOML-FIND-ATABLE
\ cursor at first [[products]] entry

doc doc-len S" products" 2 TOML-FIND-ATABLE
\ cursor at third [[products]] entry
```

---

## Layer 4 — Key Navigation

### TOML-KEY

```forth
TOML-KEY  ( addr len kaddr klen -- vaddr vlen )
```

Find `key = value` in the current scope and return cursor at value.
Searches only top-level keys — does not descend into sub-tables.

```forth
S" host" TOML-KEY TOML-GET-STRING    \ extract host value
```

### TOML-KEY?

```forth
TOML-KEY?  ( addr len kaddr klen -- vaddr vlen flag )
```

Non-aborting variant. Returns flag.

---

## Layer 5 — Path Navigation

### TOML-PATH

```forth
TOML-PATH  ( addr len path-a path-l -- val-a val-l )
```

Navigate a dotted path. Splits at the last `.` to auto-enter tables.
For example, `"database.server.host"` first finds `[database.server]`,
then looks up `host`. Falls back to flat key lookup if no dot is found.

```forth
doc doc-len S" database.port" TOML-PATH TOML-GET-INT  ( -- 5432 )
```

### TOML-PATH?

```forth
TOML-PATH?  ( addr len path-a path-l -- val-a val-l flag )
```

Non-aborting variant.

---

## Layer 6 — Array & Inline-Table Navigation

### TOML-ENTER

```forth
TOML-ENTER  ( addr len -- addr' len' )
```

Enter an array `[` or inline table `{` — skip the opening delimiter
and whitespace.

### TOML-NEXT

```forth
TOML-NEXT  ( addr len -- addr' len' flag )
```

Skip the current value, consume the comma, advance to the next element.
Returns FALSE when the closing `]` or `}` is reached.

### TOML-NTH

```forth
TOML-NTH  ( addr len n -- addr' len' )
```

Skip to the *n*th element (0-based).

```forth
S" ports" TOML-KEY TOML-ENTER 2 TOML-NTH TOML-GET-INT  ( -- third port )
```

### TOML-COUNT

```forth
TOML-COUNT  ( addr len -- n )
```

Count elements in an entered array or inline table.

---

## Layer 7 — Iteration

### TOML-EACH-KEY

```forth
TOML-EACH-KEY  ( addr len -- addr' len' key-a key-l flag )
```

Iterate key-value pairs in a table scope. Each call returns the next
key name and cursor positioned at its value. Returns FALSE when the
scope is exhausted.

```forth
body body-len
BEGIN TOML-EACH-KEY WHILE
    2>R                          \ save key
    TOML-TYPE? TOML-T-STRING = IF
        TOML-GET-STRING TYPE
    THEN
    2R>                          \ restore key
REPEAT
```

---

## Layer 8 — Inline-Table Key Lookup

### TOML-IKEY

```forth
TOML-IKEY  ( addr len kaddr klen -- vaddr vlen )
```

Find a key inside an already-entered inline table `{ ... }`.
The cursor must be past the `{` (as returned by `TOML-ENTER`).

```forth
S" owner" TOML-KEY TOML-ENTER
S" name" TOML-IKEY TOML-GET-STRING   \ get owner.name from inline table
```

---

## Layer 9 — Convenience & Guards

### Comparison

```forth
TOML-STRING=  ( addr len saddr slen -- flag )
```

Extract the string value at cursor and compare with a given string.

```forth
TOML-INT=  ( addr len n -- flag )
```

Extract the integer value at cursor and compare with a given number.

### Type Guards

Each guard word verifies the value at cursor matches the expected type,
failing with `TOML-E-WRONG-TYPE` if not. The cursor is passed through
unchanged on success.

```forth
TOML-EXPECT-STRING        ( addr len -- addr len )
TOML-EXPECT-INTEGER       ( addr len -- addr len )
TOML-EXPECT-BOOL          ( addr len -- addr len )
TOML-EXPECT-ARRAY         ( addr len -- addr len )
TOML-EXPECT-INLINE-TABLE  ( addr len -- addr len )
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| **Error Handling** | | |
| `TOML-FAIL` | `( err -- )` | Store error code |
| `TOML-OK?` | `( -- flag )` | True if no error |
| `TOML-CLEAR-ERR` | `( -- )` | Reset error state |
| **Primitives** | | |
| `TOML-SKIP-WS` | `( a l -- a' l' )` | Skip spaces/tabs |
| `TOML-SKIP-COMMENT` | `( a l -- a' l' )` | Skip `#` comment |
| `TOML-SKIP-EOL` | `( a l -- a' l' )` | Skip one EOL |
| `TOML-SKIP-LINE` | `( a l -- a' l' )` | Skip entire line |
| `TOML-SKIP-NL` | `( a l -- a' l' )` | Skip all whitespace + comments |
| `TOML-SKIP-STRING` | `( a l -- a' l' )` | Skip any string value |
| `TOML-SKIP-VALUE` | `( a l -- a' l' )` | Skip any value |
| **Type Introspection** | | |
| `TOML-TYPE?` | `( a l -- type )` | Type constant for value |
| `TOML-STRING?` | `( a l -- flag )` | Is string? |
| `TOML-INTEGER?` | `( a l -- flag )` | Is integer? |
| `TOML-FLOAT?` | `( a l -- flag )` | Is float? |
| `TOML-BOOL?` | `( a l -- flag )` | Is boolean? |
| `TOML-DATETIME?` | `( a l -- flag )` | Is datetime? |
| `TOML-ARRAY?` | `( a l -- flag )` | Is array? |
| `TOML-INLINE-TABLE?` | `( a l -- flag )` | Is inline table? |
| **Value Extraction** | | |
| `TOML-GET-STRING` | `( a l -- sa sl )` | Extract string (zero-copy) |
| `TOML-UNESCAPE` | `( src sl dst dmax -- n )` | Unescape to buffer |
| `TOML-GET-INT` | `( a l -- n )` | Parse integer |
| `TOML-GET-BOOL` | `( a l -- flag )` | Parse boolean |
| `TOML-GET-FLOAT-STR` | `( a l -- sa sl )` | Float as raw string |
| `TOML-GET-DATETIME-STR` | `( a l -- sa sl )` | Datetime as raw string |
| **Table Navigation** | | |
| `TOML-FIND-TABLE` | `( a l na nl -- ba bl )` | Find `[table]` body |
| `TOML-FIND-TABLE?` | `( a l na nl -- ba bl f )` | Non-aborting variant |
| `TOML-FIND-ATABLE` | `( a l na nl n -- ba bl )` | Find nth `[[atable]]` |
| **Key Navigation** | | |
| `TOML-KEY` | `( a l ka kl -- va vl )` | Find key → value cursor |
| `TOML-KEY?` | `( a l ka kl -- va vl f )` | Non-aborting variant |
| **Path Navigation** | | |
| `TOML-PATH` | `( a l pa pl -- va vl )` | Dotted path lookup |
| `TOML-PATH?` | `( a l pa pl -- va vl f )` | Non-aborting variant |
| **Array / Inline-Table** | | |
| `TOML-ENTER` | `( a l -- a' l' )` | Enter `[` or `{` |
| `TOML-NEXT` | `( a l -- a' l' f )` | Advance to next element |
| `TOML-NTH` | `( a l n -- a' l' )` | Skip to nth element |
| `TOML-COUNT` | `( a l -- n )` | Count elements |
| **Iteration** | | |
| `TOML-EACH-KEY` | `( a l -- a' l' ka kl f )` | Iterate key-value pairs |
| **Inline-Table Keys** | | |
| `TOML-IKEY` | `( a l ka kl -- va vl )` | Key lookup in `{ }` |
| **Convenience** | | |
| `TOML-STRING=` | `( a l sa sl -- f )` | Compare string value |
| `TOML-INT=` | `( a l n -- f )` | Compare integer value |
| `TOML-EXPECT-STRING` | `( a l -- a l )` | Guard: must be string |
| `TOML-EXPECT-INTEGER` | `( a l -- a l )` | Guard: must be integer |
| `TOML-EXPECT-BOOL` | `( a l -- a l )` | Guard: must be boolean |
| `TOML-EXPECT-ARRAY` | `( a l -- a l )` | Guard: must be array |
| `TOML-EXPECT-INLINE-TABLE` | `( a l -- a l )` | Guard: must be inline table |

---

## Cookbook

### Read a flat key

```forth
doc doc-len S" title" TOML-KEY TOML-GET-STRING
\ ( str-addr str-len )  →  "My Title"
```

### Read from a table section

```forth
doc doc-len S" database" TOML-FIND-TABLE
S" port" TOML-KEY TOML-GET-INT
\ ( -- 5432 )
```

### Use dotted path shortcut

```forth
doc doc-len S" database.port" TOML-PATH TOML-GET-INT
\ Same result, one call
```

### Iterate array-of-tables

```forth
\ Count [[products]] entries
0  ( count )
BEGIN
    doc doc-len S" products" 2 PICK TOML-FIND-ATABLE
    TOML-OK?
WHILE
    1+ TOML-CLEAR-ERR
REPEAT

\ Or use LCF-BATCH-COUNT if working with LCF [[batch]]
```

### Iterate array elements

```forth
doc doc-len S" ports" TOML-KEY TOML-ENTER
BEGIN TOML-NEXT WHILE
    TOML-GET-INT .
REPEAT
\ prints each port number
```

### Soft-fail key lookup

```forth
doc doc-len S" optional" TOML-FIND-TABLE?
IF
    S" key" TOML-KEY? IF
        TOML-GET-STRING TYPE
    ELSE 2DROP THEN
ELSE 2DROP THEN
```

### Unescape a string with special characters

```forth
CREATE ubuf 512 ALLOT
doc doc-len S" message" TOML-KEY TOML-GET-STRING
ubuf 512 TOML-UNESCAPE
ubuf SWAP TYPE   \ prints unescaped text
```
