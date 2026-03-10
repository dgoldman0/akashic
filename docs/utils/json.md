# akashic-json — JSON Vocabulary for KDOS / Megapad-64

A complete JSON reader and builder library for KDOS Forth.
Parses, navigates, and constructs JSON text using zero-copy `(addr len)` cursor
pairs — no hidden allocations, no dynamic memory.

```forth
REQUIRE json.f
```

`PROVIDED akashic-json` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Cursor Model](#cursor-model)
- [Error Handling](#error-handling)
- [Layer 0 — Primitives](#layer-0--primitives)
- [Layer 1 — Type Introspection](#layer-1--type-introspection)
- [Layer 2 — Value Extraction](#layer-2--value-extraction)
- [Layer 3 — Object Navigation](#layer-3--object-navigation)
- [Layer 4 — Array Navigation](#layer-4--array-navigation)
- [Layer 5 — Path Access](#layer-5--path-access)
- [Layer 6 — Iteration](#layer-6--iteration)
- [Layer 7 — Comparison](#layer-7--comparison)
- [Layer 8 — Builder](#layer-8--builder)
- [Layer 9 — Type Guards & Escaped Output](#layer-9--type-guards--escaped-output)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Zero-copy** | Reader words return pointers into the original JSON buffer — no intermediate copies unless you explicitly unescape. |
| **No hidden allocations** | All buffers (unescape targets, builder output) are user-provided. The library allocates only a handful of internal variables and a 16-byte comma-state stack. |
| **Composable cursors** | Every navigation word takes `(addr len)` and returns `(addr' len')`, so words chain naturally. |
| **Depth-aware** | `JSON-KEY` searches only top-level keys of the current object — it does not accidentally match keys inside nested structures. |
| **Configurable errors** | Abort-on-error or soft-fail with flag checking — your choice, changeable at runtime. |
| **Vectored builder** | Builder output goes through `JSON-EMIT` / `JSON-TYPE` which can be redirected to any target: UART, buffer, pipe. |
| **Auto-comma** | The builder tracks nesting depth and inserts commas between values automatically. |

---

## Cursor Model

A **cursor** is a standard Forth string pair `( addr len )` pointing somewhere
into a JSON text buffer. `addr` is the byte address of the current position,
`len` is the number of remaining bytes.

```
JSON text in memory:
  addr ──►{"name":"Alice","age":30}
           ↑ cursor starts here

After JSON-ENTER:
  addr' ──►"name":"Alice","age":30}
            ↑ past the {

After S" name" JSON-KEY:
  addr'' ──►"Alice","age":30}
             ↑ at the value for "name"
```

Words that navigate (enter, skip, find keys) return a new cursor.
Words that extract (`JSON-GET-STRING`, `JSON-GET-NUMBER`, etc.) consume the
cursor and return a Forth-native value.

> **Important:** Cursors are ephemeral. If you modify the underlying buffer,
> all cursors into it are invalidated. The reader is strictly read-only.

---

## Error Handling

### Variables

| Word | Stack | Description |
|---|---|---|
| `JSON-ERR` | `( -- addr )` | Variable holding the current error code. `0` = no error. |
| `JSON-ABORT-ON-ERROR` | `( -- addr )` | Variable. `-1` = abort on error, `0` = set flag only. Default: `0` (soft-fail). |

### Words

| Word | Stack | Description |
|---|---|---|
| `JSON-FAIL` | `( err-code -- )` | Store error code. If abort mode is on, calls `ABORT" JSON error"`. |
| `JSON-OK?` | `( -- flag )` | `-1` if no error, `0` if error is set. |
| `JSON-CLEAR-ERR` | `( -- )` | Reset error code to `0`. |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `JSON-E-NOT-FOUND` | 1 | Key or path not found |
| `JSON-E-WRONG-TYPE` | 2 | Value is not the expected type |
| `JSON-E-UNTERMINATED` | 3 | Unterminated string literal |
| `JSON-E-UNEXPECTED` | 4 | Unexpected character encountered |
| `JSON-E-OVERFLOW` | 5 | User-provided buffer is too small |

### Usage Patterns

**Abort mode** — simplest, crashes on any error:

```forth
-1 JSON-ABORT-ON-ERROR !
my-json JSON-ENTER S" name" JSON-KEY JSON-GET-STRING TYPE
```

**Flag mode** — check after each operation:

```forth
0 JSON-ABORT-ON-ERROR !
JSON-CLEAR-ERR
my-json JSON-ENTER S" name" JSON-KEY
JSON-OK? IF
    JSON-GET-STRING TYPE
ELSE
    ." key not found"
THEN
```

**Temporary mode switch** — `JSON-KEY?`, `JSON-HAS?`, and `JSON-PATH?`
automatically save/restore the abort mode, so they are safe to call in
either mode.

---

## Layer 0 — Primitives

Low-level character scanning. These words advance a cursor past one
syntactic element without extracting its value.

| Word | Stack | Description |
|---|---|---|
| `/STRING` | `( addr len n -- addr+n len-n )` | Standard Forth string advancement. Defined here in case the BIOS omits it. |
| `JSON-SKIP-WS` | `( addr len -- addr' len' )` | Skip JSON whitespace (space, tab, LF, CR). |
| `JSON-SKIP-STRING` | `( addr len -- addr' len' )` | Skip a complete `"..."` string, handling `\"` escapes. `addr` must point at the opening `"`. |
| `JSON-SKIP-VALUE` | `( addr len -- addr' len' )` | Skip one complete JSON value of any type: string, number, object, array, boolean, null. Depth-aware — correctly skips nested structures. |
| `JSON-SKIP-KV` | `( addr len -- addr' len' )` | Skip one `"key":value` pair in an object. |

### Example

```forth
\ Skip past the first value in an array to reach the second:
my-array JSON-ENTER     \ past [
JSON-SKIP-VALUE          \ skip first element
JSON-SKIP-WS
\ skip comma if present
OVER C@ 44 = IF 1 /STRING THEN
JSON-SKIP-WS
\ cursor now at second element
```

> Prefer the higher-level `JSON-NEXT` or `JSON-NTH` (Layer 4) for
> array traversal. These primitives are useful for building custom
> navigation logic.

---

## Layer 1 — Type Introspection

Examine the type of a JSON value at the current cursor position without
consuming it.

### Type Constants

| Constant | Value | JSON type |
|---|---|---|
| `JSON-T-ERROR` | 0 | Error / empty / invalid |
| `JSON-T-STRING` | 1 | `"..."` |
| `JSON-T-NUMBER` | 2 | `42`, `-7`, `0` |
| `JSON-T-OBJECT` | 3 | `{...}` |
| `JSON-T-ARRAY` | 4 | `[...]` |
| `JSON-T-BOOL` | 5 | `true` or `false` |
| `JSON-T-NULL` | 6 | `null` |

### Words

| Word | Stack | Description |
|---|---|---|
| `JSON-TYPE?` | `( addr len -- type )` | Return the type constant for the value at the cursor. |
| `JSON-STRING?` | `( addr len -- flag )` | Is the value a string? |
| `JSON-NUMBER?` | `( addr len -- flag )` | Is the value a number? |
| `JSON-OBJECT?` | `( addr len -- flag )` | Is the value an object? |
| `JSON-ARRAY?` | `( addr len -- flag )` | Is the value an array? |
| `JSON-BOOL?` | `( addr len -- flag )` | Is the value a boolean? |
| `JSON-NULL?` | `( addr len -- flag )` | Is the value null? |

### Example

```forth
my-json JSON-ENTER S" value" JSON-KEY
2DUP JSON-TYPE?
CASE
    JSON-T-STRING OF JSON-GET-STRING TYPE             ENDOF
    JSON-T-NUMBER OF JSON-GET-NUMBER .                ENDOF
    JSON-T-NULL   OF 2DROP ." (null)"                 ENDOF
ENDCASE
```

> The predicate words (`JSON-STRING?`, etc.) consume the cursor, so use
> `2DUP` if you need to keep it for extraction afterward.

---

## Layer 2 — Value Extraction

Pull Forth-native values out of JSON text.

| Word | Stack | Description |
|---|---|---|
| `JSON-GET-STRING` | `( addr len -- str-addr str-len )` | Extract the inner bytes of a JSON string (without surrounding quotes). **Zero-copy** — returns a pointer into the original buffer. Does **not** unescape. |
| `JSON-UNESCAPE` | `( src slen dest dmax -- len )` | Decode JSON escape sequences (`\"`, `\\`, `\/`, `\n`, `\r`, `\t`, `\b`, `\f`) from `src` into user-provided buffer `dest` of capacity `dmax`. Returns actual bytes written. Calls `JSON-FAIL` with `JSON-E-OVERFLOW` if buffer is too small. |
| `JSON-GET-NUMBER` | `( addr len -- n )` | Parse a signed integer. Stops at the first non-digit after optional leading `-`. |
| `JSON-GET-BOOL` | `( addr len -- flag )` | `true` → `-1`, `false` → `0`. |

### Example — String Extraction

```forth
my-json JSON-ENTER S" name" JSON-KEY
JSON-GET-STRING                 \ ( str-addr str-len ) — raw inner bytes
TYPE                            \ print it
```

### Example — Unescape

```forth
CREATE buf 256 ALLOT

my-json JSON-ENTER S" message" JSON-KEY
JSON-GET-STRING                 \ raw inner bytes (may contain \n etc.)
buf 256 JSON-UNESCAPE           \ decode into buf, returns length
buf SWAP TYPE                   \ print decoded string
```

### Notes

- `JSON-GET-STRING` returns the raw bytes *between* the quotes. If the
  string contains escape sequences like `\n` or `\"`, they appear as
  literal backslash-letter pairs. Use `JSON-UNESCAPE` to decode them.
- `JSON-GET-NUMBER` handles signed integers only. Floating-point is not
  supported on Megapad-64.
- All extraction words expect the cursor to already point at the correct
  value type. Use `JSON-EXPECT-*` (Layer 9) for guarded extraction.

---

## Layer 3 — Object Navigation

Depth-aware key lookup. Unlike a flat scan, `JSON-KEY` searches only the
top-level keys of the current object — it correctly skips over nested
objects and arrays.

| Word | Stack | Description |
|---|---|---|
| `JSON-ENTER` | `( addr len -- addr' len' )` | Enter a `{` or `[`. Returns cursor positioned after the opening bracket, with leading whitespace skipped. |
| `JSON-KEY` | `( addr len kaddr klen -- vaddr vlen )` | Look up key `kaddr klen` in the current object. Cursor must be inside the object (past `{`). Returns cursor at the corresponding value. Calls `JSON-FAIL` with `JSON-E-NOT-FOUND` if the key does not exist. |
| `JSON-KEY?` | `( addr len kaddr klen -- vaddr vlen flag )` | Like `JSON-KEY` but returns a flag. `-1` on success, `0` if not found (with `vaddr vlen` = `0 0`). **Never aborts** — temporarily switches to flag mode internally. |
| `JSON-HAS?` | `( addr len kaddr klen -- flag )` | Test whether the object contains the key. Does **not** move the cursor. |

### Example

```forth
\ Direct lookup (aborts if missing):
my-json JSON-ENTER S" user" JSON-KEY
        JSON-ENTER S" email" JSON-KEY
JSON-GET-STRING TYPE

\ Safe lookup with fallback:
my-json JSON-ENTER
S" nickname" JSON-KEY?
IF   JSON-GET-STRING TYPE
ELSE ." (no nickname)"
THEN
```

### How Depth-Awareness Works

When scanning for a key, `JSON-KEY` uses `JSON-SKIP-KV` to jump over
entire key-value pairs. `JSON-SKIP-KV` in turn calls `JSON-SKIP-VALUE`,
which is depth-aware — it tracks `{`/`[` nesting and `}`/`]` closers to
skip complete nested structures in one pass.

```
{"users":[{"id":1},{"id":2}],"count":2}
  ↑ JSON-KEY looking for "count"
  │
  ├─ tests "users" → not a match
  ├─ JSON-SKIP-KV skips "users":[{"id":1},{"id":2}]
  │                              ^^^^^^^^^^^^^^^^^^^^
  │                              entire nested array skipped
  ├─ tests "count" → match!
  └─ returns cursor at: 2}
```

---

## Layer 4 — Array Navigation

| Word | Stack | Description |
|---|---|---|
| `JSON-NEXT` | `( addr len -- addr' len' flag )` | Advance past the current value to the next element. Returns `-1` if another element exists, `0` at end. |
| `JSON-NEXT-VALUE` | `( addr len -- addr' len' )` | Like `JSON-NEXT` but drops the flag. Use when the caller knows more elements exist (e.g. parsing a fixed-layout array sequentially). |
| `JSON-NTH` | `( addr len n -- addr' len' )` | Jump to the *n*th element (0-based). Cursor must be inside the array (past `[`). Calls `JSON-FAIL` if *n* is out of range. |
| `JSON-COUNT` | `( addr len -- n )` | Count elements in an array (or keys in an object). Cursor must be inside (past `[` or `{`). Non-destructive scan. |

### Example — Index Access

```forth
my-json JSON-ENTER     \ enter the array
2 JSON-NTH              \ jump to element at index 2
JSON-GET-NUMBER .       \ extract and print it
```

### Example — Iterate an Array

```forth
my-json JSON-ENTER
BEGIN
    2DUP JSON-GET-NUMBER .     \ process current element
    JSON-NEXT                   \ advance
WHILE REPEAT
2DROP
```

> **Pattern:** Always `2DUP` before extracting if you plan to call
> `JSON-NEXT` afterward, because extraction words consume the cursor.

### Example — Count

```forth
my-json JSON-ENTER JSON-COUNT .    \ prints number of elements
```

### Example — Sequential Fixed-Layout Array (JSON-NEXT-VALUE)

When parsing an array with a known layout (e.g. `["leaf", 42, "proof", 3, "root"]`),
`JSON-NEXT-VALUE` lets you step through elements without tracking indices:

```forth
my-json JSON-ENTER
JSON-GET-STRING  leaf-buf FMT-HEX-DECODE DROP   \ element 0
JSON-NEXT-VALUE
JSON-GET-NUMBER  idx !                            \ element 1
JSON-NEXT-VALUE
JSON-GET-STRING  proof-buf FMT-HEX-DECODE DROP   \ element 2
JSON-NEXT-VALUE
JSON-GET-NUMBER  depth !                          \ element 3
JSON-NEXT-VALUE
JSON-GET-STRING  root-buf FMT-HEX-DECODE DROP    \ element 4
```

> Unlike `JSON-NEXT`, `JSON-NEXT-VALUE` does not return a flag —
> use it only when you are certain the next element exists.

---

## Layer 5 — Path Access

Navigate deeply nested structures with a single dot-separated path string.

| Word | Stack | Description |
|---|---|---|
| `JSON-PATH` | `( addr len paddr plen -- addr' len' )` | Navigate a dot-separated path. Each segment is treated as a key name, with automatic `JSON-ENTER` before each lookup. Calls `JSON-FAIL` if any segment is not found. |
| `JSON-PATH?` | `( addr len paddr plen -- addr' len' flag )` | Like `JSON-PATH` but returns a flag instead of failing. |

### Example

```forth
\ Given: {"post":{"author":{"handle":"alice.bsky.social"}}}
my-json S" post.author.handle" JSON-PATH
JSON-GET-STRING TYPE
\ prints: alice.bsky.social

\ Equivalent to:
my-json JSON-ENTER S" post" JSON-KEY
        JSON-ENTER S" author" JSON-KEY
        JSON-ENTER S" handle" JSON-KEY
JSON-GET-STRING TYPE
```

### Safe Path Access

```forth
my-json S" deep.nested.key" JSON-PATH?
IF   JSON-GET-STRING TYPE
ELSE ." path not found"
THEN
```

### Limitations

- Path segments are separated by `.` (period, ASCII 46). Keys containing
  literal dots cannot be addressed with `JSON-PATH` — use chained
  `JSON-ENTER` / `JSON-KEY` instead.
- Array indices are not supported in paths — a path like `items.0.name`
  will not work. Use `JSON-PATH` to reach the array, then `JSON-NTH` for
  the index.

---

## Layer 6 — Iteration

Structured iteration over object entries.

| Word | Stack | Description |
|---|---|---|
| `JSON-EACH-KEY` | `( addr len -- addr' len' key-addr key-len flag )` | Iterate object entries. Returns the next key name and positions the cursor at that key's value. Flag is `-1` if a pair was found, `0` at end. |

### Usage Pattern

```forth
my-json JSON-ENTER
BEGIN JSON-EACH-KEY WHILE           ( val-a val-l key-a key-l )
    2SWAP                            ( key-a key-l val-a val-l )
    \ --- process key and value here ---
    2OVER TYPE ." = "                \ print key
    2DUP JSON-GET-STRING TYPE CR     \ print value (if string)
    \ --- advance past the value ---
    JSON-SKIP-VALUE
    JSON-SKIP-WS
REPEAT 2DROP
```

### How It Works

1. Skips commas and whitespace.
2. Extracts the key string (zero-copy).
3. Skips past the key string and colon.
4. Leaves the cursor at the value.
5. The caller **must** advance past the value (via `JSON-SKIP-VALUE` or other navigation) before calling `JSON-EACH-KEY` again.

> For array iteration, use `JSON-ENTER` + `JSON-NEXT` (Layer 4).
> `JSON-EACH-KEY` is designed specifically for objects.

---

## Layer 7 — Comparison

Compare JSON values in-place without extracting to separate buffers.

| Word | Stack | Description |
|---|---|---|
| `JSON-STRING=` | `( addr len saddr slen -- flag )` | Is the JSON string value equal to the Forth string `saddr slen`? Compares raw (un-escaped) inner bytes. |
| `JSON-NUMBER=` | `( addr len n -- flag )` | Is the JSON number value equal to `n`? |

### Example

```forth
my-json JSON-ENTER S" type" JSON-KEY
S" like" JSON-STRING=
IF ." it's a like!" THEN
```

```forth
my-json JSON-ENTER S" status" JSON-KEY
200 JSON-NUMBER=
IF ." OK" THEN
```

---

## Layer 8 — Builder

Construct JSON text programmatically with automatic comma insertion
and vectored output.

### Vectored Output

Builder output flows through two indirection variables. By default they
point at `EMIT` and `TYPE`, sending JSON to the UART.

| Word | Stack | Description |
|---|---|---|
| `JSON-EMIT-XT` | `( -- addr )` | Variable holding the XT for single-character output `( char -- )`. |
| `JSON-TYPE-XT` | `( -- addr )` | Variable holding the XT for string output `( addr len -- )`. |
| `JSON-EMIT` | `( c -- )` | Emit one character through the current output vector. |
| `JSON-TYPE` | `( addr len -- )` | Emit a string through the current output vector. |

### Buffer Output

Redirect builder output into a user-provided memory buffer.

| Word | Stack | Description |
|---|---|---|
| `JSON-SET-OUTPUT` | `( addr max -- )` | Direct all builder output into buffer `addr` of capacity `max`. Resets write position to 0. Sets `JSON-EMIT-XT` and `JSON-TYPE-XT` to internal buffer-writing words. |
| `JSON-OUTPUT-RESULT` | `( -- addr len )` | Return the buffer address and number of bytes written so far. |
| `JSON-OUTPUT-RESET` | `( -- )` | Reset write position to 0 (re-use the same buffer). |

### Structural Words

| Word | Stack | Description |
|---|---|---|
| `JSON-{` | `( -- )` | Emit `{` and push comma state. |
| `JSON-}` | `( -- )` | Emit `}` and pop comma state. |
| `JSON-[` | `( -- )` | Emit `[` and push comma state. |
| `JSON-]` | `( -- )` | Emit `]` and pop comma state. |
| `JSON-KEY:` | `( addr len -- )` | Emit `"key":` and reset comma state so the following value is not preceded by a comma. |

### Value Words

| Word | Stack | Description |
|---|---|---|
| `JSON-STR` | `( addr len -- )` | Emit a JSON string value `"..."`. **No escaping** — use `JSON-ESTR` (Layer 9) for strings that may contain special characters. |
| `JSON-NUM` | `( n -- )` | Emit a signed decimal integer. |
| `JSON-TRUE` | `( -- )` | Emit `true`. |
| `JSON-FALSE` | `( -- )` | Emit `false`. |
| `JSON-NULL` | `( -- )` | Emit `null`. |
| `JSON-BOOL` | `( flag -- )` | Emit `true` if flag is non-zero, `false` otherwise. |

### Key-Value Convenience Words

These combine `JSON-KEY:` with a value word for the common case of
emitting a complete `"key":value` pair.

| Word | Stack | Description |
|---|---|---|
| `JSON-KV-STR` | `( kaddr klen vaddr vlen -- )` | Emit `"key":"value"`. |
| `JSON-KV-NUM` | `( kaddr klen n -- )` | Emit `"key":n`. |
| `JSON-KV-BOOL` | `( kaddr klen flag -- )` | Emit `"key":true` or `"key":false`. |
| `JSON-KV-NULL` | `( kaddr klen -- )` | Emit `"key":null`. |

### Reset

| Word | Stack | Description |
|---|---|---|
| `JSON-BUILD-RESET` | `( -- )` | Reset comma-state stack and restore default EMIT/TYPE vectors. |

### Auto-Comma Mechanism

The builder maintains an internal comma-state stack (max 16 levels deep).
When you open a structure with `JSON-{` or `JSON-[`, a new level is
pushed. The first value at each level emits no comma; subsequent values
automatically get a comma prepended.

```forth
JSON-[ 1 JSON-NUM 2 JSON-NUM 3 JSON-NUM JSON-]
\ produces: [1,2,3]
\              ^ ^  commas inserted automatically
```

`JSON-KEY:` emits the comma before the key, then resets the flag so the
value immediately after the colon does not get a spurious comma.

### Example — Build to Buffer

```forth
CREATE out-buf 512 ALLOT
out-buf 512 JSON-SET-OUTPUT

JSON-{
    S" name" S" Alice" JSON-KV-STR
    S" age" 30 JSON-KV-NUM
    S" active" -1 JSON-KV-BOOL
    S" items" JSON-KEY: JSON-[
        1 JSON-NUM
        2 JSON-NUM
        3 JSON-NUM
    JSON-]
JSON-}

JSON-OUTPUT-RESULT TYPE
\ prints: {"name":"Alice","age":30,"active":true,"items":[1,2,3]}
```

### Example — Build to UART

```forth
JSON-BUILD-RESET               \ ensure default output vectors
JSON-{ S" ok" -1 JSON-KV-BOOL JSON-}
\ directly prints to UART: {"ok":true}
```

### Custom Output Targets

Store any `( char -- )` word in `JSON-EMIT-XT` and any `( addr len -- )`
word in `JSON-TYPE-XT` to redirect output to a pipe, file, or network
socket.

```forth
: my-emit  ( c -- )  \ custom single-char output
    MY-PIPE-WRITE-BYTE ;
: my-type  ( addr len -- )  \ custom string output
    0 DO DUP I + C@ my-emit LOOP DROP ;

' my-emit JSON-EMIT-XT !
' my-type JSON-TYPE-XT !
```

---

## Layer 9 — Type Guards & Escaped Output

### Type Guards

Assertion words that verify the cursor points at the expected type.
On success, the cursor is preserved unchanged. On failure, `JSON-FAIL`
is called with `JSON-E-WRONG-TYPE`.

| Word | Stack | Description |
|---|---|---|
| `JSON-EXPECT-STRING` | `( addr len -- addr len )` | Assert value is a string. |
| `JSON-EXPECT-NUMBER` | `( addr len -- addr len )` | Assert value is a number. |
| `JSON-EXPECT-OBJECT` | `( addr len -- addr len )` | Assert value is an object. |
| `JSON-EXPECT-ARRAY` | `( addr len -- addr len )` | Assert value is an array. |
| `JSON-EXPECT-BOOL` | `( addr len -- addr len )` | Assert value is a boolean. |
| `JSON-EXPECT-NULL` | `( addr len -- addr len )` | Assert value is null. |

### Example

```forth
\ Guarded extraction — aborts (or sets error) if type is wrong:
my-json JSON-ENTER S" count" JSON-KEY
JSON-EXPECT-NUMBER JSON-GET-NUMBER .
```

### Escaped String Output

| Word | Stack | Description |
|---|---|---|
| `JSON-ESTR` | `( addr len -- )` | Emit a JSON string value with proper escaping. Handles `"` → `\"`, `\` → `\\`, newline → `\n`, CR → `\r`, tab → `\t`, backspace → `\b`, formfeed → `\f`. All other bytes are emitted verbatim. |
| `JSON-KV-ESTR` | `( kaddr klen vaddr vlen -- )` | Key-value convenience with escaped string value. |

### When to Use `JSON-ESTR` vs `JSON-STR`

- **`JSON-STR`** — fast, no escaping. Use when you know the string
  contains only safe characters (no quotes, backslashes, or control
  characters). Typical for identifiers, known-safe literals, or strings
  that came from `JSON-GET-STRING` (already in raw JSON form).

- **`JSON-ESTR`** — escapes special characters. Use for user-generated
  text, log messages, or any string that might contain `"`, `\`,
  newlines, tabs, etc.

```forth
\ Safe: known literal
S" status" S" ok" JSON-KV-STR

\ Needs escaping: user input might contain quotes
S" message" user-buf user-len JSON-KV-ESTR
```

---

## Quick Reference

All public words at a glance, grouped by function.

### Error Handling

```
JSON-ERR               ( -- addr )         error code variable
JSON-ABORT-ON-ERROR    ( -- addr )         abort mode variable
JSON-FAIL              ( err-code -- )     signal error
JSON-OK?               ( -- flag )         check for errors
JSON-CLEAR-ERR         ( -- )              reset error state
```

### Reading — Navigation

```
JSON-SKIP-WS           ( a u -- a' u' )           skip whitespace
JSON-SKIP-STRING       ( a u -- a' u' )           skip "..."
JSON-SKIP-VALUE        ( a u -- a' u' )           skip any value
JSON-SKIP-KV           ( a u -- a' u' )           skip "key":value
JSON-ENTER             ( a u -- a' u' )           enter { or [
JSON-KEY               ( a u ka ku -- va vu )     find key (fail)
JSON-KEY?              ( a u ka ku -- va vu f )   find key (flag)
JSON-HAS?              ( a u ka ku -- f )         test key exists
JSON-NEXT              ( a u -- a' u' f )         next element
JSON-NEXT-VALUE        ( a u -- a' u' )           next (no flag)
JSON-NTH               ( a u n -- a' u' )         nth element
JSON-COUNT             ( a u -- n )               count elements
JSON-PATH              ( a u pa pu -- a' u' )     dot-path (fail)
JSON-PATH?             ( a u pa pu -- a' u' f )   dot-path (flag)
JSON-EACH-KEY          ( a u -- a' u' ka ku f )   iterate keys
```

### Reading — Introspection & Extraction

```
JSON-TYPE?             ( a u -- type )     type constant
JSON-STRING?           ( a u -- f )        is string?
JSON-NUMBER?           ( a u -- f )        is number?
JSON-OBJECT?           ( a u -- f )        is object?
JSON-ARRAY?            ( a u -- f )        is array?
JSON-BOOL?             ( a u -- f )        is boolean?
JSON-NULL?             ( a u -- f )        is null?
JSON-GET-STRING        ( a u -- sa su )    extract string (zero-copy)
JSON-UNESCAPE          ( s l d m -- n )    unescape to buffer
JSON-GET-NUMBER        ( a u -- n )        extract integer
JSON-GET-BOOL          ( a u -- f )        extract boolean
JSON-STRING=           ( a u sa su -- f )  compare string
JSON-NUMBER=           ( a u n -- f )      compare number
JSON-EXPECT-STRING     ( a u -- a u )      guard: must be string
JSON-EXPECT-NUMBER     ( a u -- a u )      guard: must be number
JSON-EXPECT-OBJECT     ( a u -- a u )      guard: must be object
JSON-EXPECT-ARRAY      ( a u -- a u )      guard: must be array
JSON-EXPECT-BOOL       ( a u -- a u )      guard: must be boolean
JSON-EXPECT-NULL       ( a u -- a u )      guard: must be null
```

### Building

```
JSON-SET-OUTPUT        ( a m -- )          redirect to buffer
JSON-OUTPUT-RESULT     ( -- a u )          get buffer contents
JSON-OUTPUT-RESET      ( -- )              reset write position
JSON-BUILD-RESET       ( -- )              reset comma + vectors
JSON-{                 ( -- )              emit {
JSON-}                 ( -- )              emit }
JSON-[                 ( -- )              emit [
JSON-]                 ( -- )              emit ]
JSON-KEY:              ( a u -- )          emit "key":
JSON-STR               ( a u -- )          emit "str" (raw)
JSON-ESTR              ( a u -- )          emit "str" (escaped)
JSON-NUM               ( n -- )            emit number
JSON-TRUE              ( -- )              emit true
JSON-FALSE             ( -- )              emit false
JSON-NULL              ( -- )              emit null
JSON-BOOL              ( f -- )            emit true/false
JSON-KV-STR            ( ka ku va vu -- )  "key":"value"
JSON-KV-ESTR           ( ka ku va vu -- )  "key":"val" (escaped)
JSON-KV-NUM            ( ka ku n -- )      "key":n
JSON-KV-BOOL           ( ka ku f -- )      "key":true/false
JSON-KV-NULL           ( ka ku -- )        "key":null
JSON-EMIT-XT           ( -- addr )         emit vector variable
JSON-TYPE-XT           ( -- addr )         type vector variable
JSON-EMIT              ( c -- )            emit via vector
JSON-TYPE              ( a u -- )          type via vector
```

### Constants

```
JSON-T-ERROR  = 0      JSON-E-NOT-FOUND    = 1
JSON-T-STRING = 1      JSON-E-WRONG-TYPE   = 2
JSON-T-NUMBER = 2      JSON-E-UNTERMINATED = 3
JSON-T-OBJECT = 3      JSON-E-UNEXPECTED   = 4
JSON-T-ARRAY  = 4      JSON-E-OVERFLOW     = 5
JSON-T-BOOL   = 5
JSON-T-NULL   = 6
```

---

## Cookbook

### Parse a Bluesky Post Notification

```forth
\ Given a notification JSON in (json-addr json-len):
: process-notification  ( addr len -- )
    JSON-ENTER
    S" reason" JSON-KEY
    S" like" JSON-STRING= IF
        ." Liked by: "
        \ go back and get author — need original cursor
    THEN ;

\ Better approach using JSON-PATH:
: show-liker  ( addr len -- )
    2DUP S" reason" JSON-PATH S" like" JSON-STRING= IF
        S" author.displayName" JSON-PATH
        JSON-GET-STRING TYPE CR
    ELSE
        2DROP
    THEN ;
```

### Build an API Request Body

```forth
CREATE req-buf 1024 ALLOT
req-buf 1024 JSON-SET-OUTPUT

JSON-{
    S" collection" S" app.bsky.feed.like" JSON-KV-STR
    S" repo" my-did count JSON-KV-STR
    S" record" JSON-KEY: JSON-{
        S" subject" JSON-KEY: JSON-{
            S" uri"  post-uri  post-uri-len  JSON-KV-STR
            S" cid"  post-cid  post-cid-len  JSON-KV-STR
        JSON-}
        S" createdAt" timestamp timestamp-len JSON-KV-STR
    JSON-}
JSON-}

JSON-OUTPUT-RESULT    \ ( addr len ) — ready to send
```

### Iterate and Filter

```forth
\ Print all "like" notifications from a feed array:
: show-likes  ( addr len -- )
    JSON-ENTER
    BEGIN
        2DUP
        JSON-ENTER S" reason" JSON-KEY
        S" like" JSON-STRING= IF
            JSON-ENTER S" author.displayName" JSON-PATH
            JSON-GET-STRING TYPE CR
        THEN
        JSON-NEXT
    WHILE REPEAT
    2DROP ;
```

### Round-Trip: Read then Rebuild

```forth
\ Copy selected fields from input JSON to output JSON:
CREATE out 512 ALLOT
out 512 JSON-SET-OUTPUT

: transform  ( addr len -- )
    JSON-{
        2DUP JSON-ENTER S" name" JSON-KEY
        S" name" 2SWAP JSON-GET-STRING JSON-KV-STR

        2DUP JSON-ENTER S" age" JSON-KEY
        S" age" 2SWAP JSON-GET-NUMBER JSON-KV-NUM

        S" processed" -1 JSON-KV-BOOL
    JSON-}
    2DROP ;
```

### Conditional Field Handling

```forth
: extract-with-fallback  ( addr len -- )
    JSON-ENTER
    S" nickname" JSON-KEY?
    IF   JSON-GET-STRING
    ELSE DROP DROP S" Anonymous"    \ fallback
    THEN
    TYPE ;
```

---

## Internal Words

These are prefixed with `_JSON-` or `_J` and are not part of the public API.
They may change between versions.

| Word | Purpose |
|---|---|
| `_JSON-DEPTH` | Variable used by `JSON-SKIP-VALUE` for nesting depth. |
| `_JSON-STR=` | Internal string comparison `( s1 l1 s2 l2 -- flag )`. |
| `_JSON-NUM-NEG` | Sign flag for `JSON-GET-NUMBER`. |
| `_JU-DST`, `_JU-MAX`, `_JU-POS` | State for `JSON-UNESCAPE`. |
| `_JK-KA`, `_JK-KL` | Key address/length for `JSON-KEY`. |
| `_JK-SAVE-ABORT` | Abort-mode save for `JSON-KEY?`. |
| `_JH-SAVE-ABORT` | Abort-mode save for `JSON-HAS?`. |
| `_JP-PA`, `_JP-PL` | Path pointer/length for `JSON-PATH`. |
| `_JPQ-SAVE-ABORT` | Abort-mode save for `JSON-PATH?`. |
| `_JB-BUF`, `_JB-MAX`, `_JB-POS` | Buffer output state. |
| `_JC-STACK`, `_JC-DEPTH` | Auto-comma nesting stack (16 levels). |
| `_JN-BUF` | Scratch buffer for `JSON-NUM` digit conversion. |
| `_JSON-DEFAULT-EMIT` | Default emit word (wraps `EMIT`). |
| `_JSON-DEFAULT-TYPE` | Default type word (wraps `TYPE`). |
| `_JSON-QUOTED` | Emit a string wrapped in double quotes. |
| `_JC-RESET`, `_JC-PUSH`, `_JC-POP` | Comma-stack management. |
| `_JC-NEED?`, `_JC-MARK`, `_JC-COMMA` | Comma-state queries and insertion. |
| `/STRING` | Standard Forth word, defined as fallback. |
