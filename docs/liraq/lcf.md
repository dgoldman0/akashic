# akashic-lcf — LCF Reader / Writer for KDOS / Megapad-64

Reader and writer for the LIRAQ Communication Format (LCF), the
wire format defined in LIRAQ v1.0 spec §2.3. LCF supports both
TOML 1.0 and JSON formats — the reader auto-detects the format,
and the writer dispatches to TOML or JSON based on `LCF-FORMAT`.

```forth
REQUIRE lcf.f
```

`PROVIDED akashic-lcf` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [LCF Message Format](#lcf-message-format)
- [Error Handling](#error-handling)
- [Format Dispatch (JSON / TOML)](#format-dispatch-json--toml)
- [Reader — Message Inspection](#reader--message-inspection)
- [Reader — Batch Access](#reader--batch-access)
- [Reader — Action Helpers](#reader--action-helpers)
- [Reader — Capabilities](#reader--capabilities)
- [Validation](#validation)
- [Notification Messages](#notification-messages)
- [Handshake / Session](#handshake--session)
- [Operation Vocabulary](#operation-vocabulary)
- [Writer — Buffer Management](#writer--buffer-management)
- [Writer — Key-Value Emission](#writer--key-value-emission)
- [Writer — Table Headers](#writer--table-headers)
- [Writer — Convenience Messages](#writer--convenience-messages)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Dual format** | LCF supports both TOML 1.0 and JSON. The reader auto-detects the format by inspecting the first non-whitespace character. The writer dispatches based on `LCF-FORMAT`. |
| **TOML / JSON delegation** | Parsing delegates to `akashic-toml` or `akashic-json`. No duplicate parsing logic. |
| **Zero-copy reading** | All reader words return pointers into the original message buffer. |
| **Buffer-based writing** | The writer appends text into a caller-supplied buffer via `LCF-W-INIT`. For JSON output, the json.f builder is used. No hidden allocations. |
| **Kebab-case convention** | LCF keys must be kebab-case (`[a-z0-9-]+`). `LCF-VALID-KEY?` enforces this. |
| **64 KiB message limit** | `LCF-VALIDATE` rejects messages exceeding `LCF-MAX-SIZE` (65536 bytes). |
| **VARIABLE-based state** | Writer uses module-scoped VARIABLEs (`_LW-BUF`, `_LW-MAX`, `_LW-POS`). Not re-entrant. |

---

## LCF Message Format

LCF defines four message categories. Each can be encoded as TOML or JSON.

### DCS → Runtime (Actions)

```toml
[action]
type = "batch"

[[batch]]
op = "set-state"
path = "/ui/theme"
value = "dark"

[[batch]]
op = "append-child"
element-id = "main"
value = "<p>Hello</p>"
```

### Runtime → DCS (Results)

```toml
[result]
status = "ok"
value = "systems"
```

```toml
[result]
status = "error"
error = "element-not-found"
detail = "No element with id 'nav-panel'"
```

### Notifications (Runtime → DCS)

```toml
[notification]
type = "event"
path = "/ui/button-clicked"
value = "submit"
```

### Handshake / Capabilities

```toml
[action]
type = "handshake"

[capabilities]
version = "1.0"
queries = true
behaviors = false
max-batch-size = 50
```

### JSON variants

All of the above can also be expressed as JSON:

```json
{"action":{"type":"query"},"batch":[{"op":"get-state","path":"/ui/theme"}]}
{"result":{"status":"ok","value":"dark"}}
{"notification":{"type":"state-change","path":"/ui/theme","value":"dark"}}
```

**Convention summary:**
- `[action]` / `"action"` with `type` key — DCS to Runtime
- `[result]` / `"result"` with `status` key — Runtime to DCS
- `[notification]` / `"notification"` — async notifications
- `[[batch]]` / `"batch"` array — batch mutations
- All keys kebab-case
- Max 64 KiB per message

---

## Error Handling

### Variables

| Variable | Purpose |
|----------|---------|
| `LCF-ERR` | Current error code (0 = no error) |

### Error Codes

| Constant | Value | Meaning |
|----------|-------|---------|
| `LCF-E-NO-ACTION` | 10 | Message lacks `[action]` table |
| `LCF-E-NO-RESULT` | 11 | Message lacks `[result]` table |
| `LCF-E-NO-TYPE` | 12 | Action has no `type` key |
| `LCF-E-BAD-KEY` | 13 | Key is not kebab-case |
| `LCF-E-TOO-LARGE` | 14 | Message exceeds 64 KiB |
| `LCF-E-OVERFLOW` | 15 | Writer buffer overflow |
| `LCF-E-NO-NOTIFY` | 16 | Message lacks `[notification]` table |

### Words

```forth
LCF-FAIL       ( code -- )   \ Store error code
LCF-OK?        ( -- flag )   \ True if no error pending
LCF-CLEAR-ERR  ( -- )        \ Reset error state
```

### Constants

```forth
LCF-MAX-SIZE  ( -- 65536 )   \ Maximum message size in bytes
```

---

## Format Dispatch (JSON / TOML)

LCF messages can be encoded as either TOML or JSON, per LIRAQ v1.0
spec §2.3. The reader auto-detects the format; the writer uses
whichever format `LCF-FORMAT` selects.

### Format Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `LCF-FMT-TOML` | 0 | TOML format (default) |
| `LCF-FMT-JSON` | 1 | JSON format |

### Writer Format Variable

```forth
LCF-FORMAT  ( -- addr )
```

A VARIABLE controlling which format the writer convenience words
(`LCF-W-OK`, `LCF-W-ERROR`, etc.) emit. Default is `LCF-FMT-TOML`.

```forth
LCF-FMT-JSON LCF-FORMAT !    \ switch writer to JSON
```

### Auto-detection (Reader)

All reader words auto-detect the message format by inspecting the
first non-whitespace character. If it is `{`, the JSON reader path
is used; otherwise the TOML reader path is used. This means the
same LCF reader words work transparently on both formats:

```forth
\ Both of these work with the same LCF-ACTION-TYPE word:
S" [action]\ntype = \"query\"" LCF-ACTION-TYPE   \ TOML
S" {\"action\":{\"type\":\"query\"}}" LCF-ACTION-TYPE  \ JSON
```

### Internal Dispatch Primitives

These are implementation details but are documented for completeness:

| Word | Stack | Purpose |
|------|-------|---------|
| `_LCF-IS-JSON?` | `( a l -- flag )` | TRUE if first non-WS char is `{` |
| `_LCF-DETECT` | `( a l -- )` | Set `_LCF-FMT` from message content |
| `_LF-FIND-TABLE` | `( a l key-a key-l -- )` | Find table by name (either format) |
| `_LF-FIND-TABLE?` | `( a l key-a key-l -- flag )` | Try to find table, return success flag |
| `_LF-KEY` | `( key-a key-l -- val-a val-l )` | Get string by key (either format) |
| `_LF-KEY?` | `( key-a key-l -- val-a val-l flag )` | Try to get string, flag success |
| `_LF-GET-STRING` | `( key-a key-l -- val-a val-l )` | Get string value by key |
| `_LF-GET-BOOL` | `( key-a key-l -- flag )` | Get boolean value by key |
| `_LF-GET-INT` | `( key-a key-l -- n )` | Get integer value by key |
| `_LF-FIND-ATABLE` | `( a l name-a name-l -- )` | Find array-of-tables / JSON array |
| `_LF-CLEAR-ERR` | `( -- )` | Clear current backend error state |

---

## Reader — Message Inspection

All reader words take a message document as `( doc-a doc-l )`.
The format (TOML or JSON) is auto-detected on each call.

### LCF-ACTION?

```forth
LCF-ACTION?  ( doc-a doc-l -- flag )
```

TRUE if the message contains an `[action]` table.

### LCF-RESULT?

```forth
LCF-RESULT?  ( doc-a doc-l -- flag )
```

TRUE if the message contains a `[result]` table.

### LCF-ACTION-TYPE

```forth
LCF-ACTION-TYPE  ( doc-a doc-l -- str-a str-l )
```

Extract the `type` string from `[action]`. Aborts if not found.

### LCF-ACTION-TYPE?

```forth
LCF-ACTION-TYPE?  ( doc-a doc-l -- str-a str-l flag )
```

Non-aborting variant. Returns `( 0 0 FALSE )` if action or type
is missing.

### LCF-RESULT-STATUS

```forth
LCF-RESULT-STATUS  ( doc-a doc-l -- str-a str-l )
```

Extract the `status` string from `[result]`.

### LCF-RESULT-OK?

```forth
LCF-RESULT-OK?  ( doc-a doc-l -- flag )
```

TRUE if `[result].status` equals `"ok"`.

### LCF-RESULT-ERROR

```forth
LCF-RESULT-ERROR  ( doc-a doc-l -- err-a err-l )
```

Extract the `error` string from `[result]`.

### LCF-RESULT-DETAIL

```forth
LCF-RESULT-DETAIL  ( doc-a doc-l -- str-a str-l )
```

Extract the `detail` string from `[result]`.

---

## Reader — Batch Access

### LCF-BATCH-NTH

```forth
LCF-BATCH-NTH  ( doc-a doc-l n -- body-a body-l )
```

Get the *n*th (0-based) `[[batch]]` entry. Returns a cursor to the
entry's body where individual keys can be extracted.

### LCF-BATCH-OP

```forth
LCF-BATCH-OP  ( body-a body-l -- str-a str-l )
```

Extract the `op` string from a batch entry body.

### LCF-BATCH-COUNT

```forth
LCF-BATCH-COUNT  ( doc-a doc-l -- n )
```

Count `[[batch]]` entries by probing successive indices.

### LCF-ENTRY-STRING

```forth
LCF-ENTRY-STRING  ( body-a body-l key-a key-l -- str-a str-l )
```

Extract a string key from a batch entry body. Generic accessor
for any entry field.

```forth
doc doc-len 0 LCF-BATCH-NTH            \ get first batch entry
2DUP LCF-BATCH-OP TYPE                 \ print op
S" path" LCF-ENTRY-STRING TYPE         \ print path
```

---

## Reader — Action Helpers

### LCF-ACTION-KEY

```forth
LCF-ACTION-KEY  ( doc-a doc-l key-a key-l -- val-a val-l )
```

Retrieve a key's value cursor from the `[action]` table.

### LCF-ACTION-STRING

```forth
LCF-ACTION-STRING  ( doc-a doc-l key-a key-l -- str-a str-l )
```

Retrieve a string value from `[action]`.

### LCF-QUERY-METHOD

```forth
LCF-QUERY-METHOD  ( doc-a doc-l -- str-a str-l )
```

Shortcut for `[action].method` as string.

### LCF-QUERY-PATH

```forth
LCF-QUERY-PATH  ( doc-a doc-l -- str-a str-l )
```

Shortcut for `[action].path` as string.

---

## Reader — Capabilities

### LCF-CAP-VERSION

```forth
LCF-CAP-VERSION  ( doc-a doc-l -- str-a str-l )
```

Extract `[capabilities].version` as string.

### LCF-CAP-BOOL

```forth
LCF-CAP-BOOL  ( doc-a doc-l key-a key-l -- flag )
```

Extract a boolean capability by key name.

```forth
doc doc-len S" queries" LCF-CAP-BOOL   \ TRUE or FALSE
```

### LCF-CAP-INT

```forth
LCF-CAP-INT  ( doc-a doc-l key-a key-l -- n )
```

Extract an integer capability by key name.

```forth
doc doc-len S" max-batch-size" LCF-CAP-INT   \ 50
```

---

## Validation

### LCF-VALID-KEY?

```forth
LCF-VALID-KEY?  ( addr len -- flag )
```

Check that all characters are valid kebab-case: `[a-z0-9-]`.
Empty strings return FALSE.

```forth
S" set-state"   LCF-VALID-KEY?   \ TRUE
S" setState"    LCF-VALID-KEY?   \ FALSE (uppercase)
S" set_state"   LCF-VALID-KEY?   \ FALSE (underscore)
```

### LCF-VALIDATE

```forth
LCF-VALIDATE  ( doc-a doc-l -- flag )
```

Basic message validation:
1. Message size ≤ 64 KiB
2. Contains `[action]`, `[result]`, or `[notification]` table

Returns TRUE if valid. Sets `LCF-ERR` on failure.

---

## Notification Messages

Notification messages carry asynchronous events from runtime to DCS.
They use a `[notification]` (TOML) or `{"notification":{...}}` (JSON)
table instead of `[action]` or `[result]`.

### Message Format

```toml
[notification]
type = "event"
path = "/ui/button-clicked"
value = "submit"
```

```json
{"notification":{"type":"state-change","path":"/ui/theme","value":"dark"}}
```

### Reader Words

#### LCF-NOTIFICATION?

```forth
LCF-NOTIFICATION?  ( doc-a doc-l -- flag )
```

TRUE if the message contains a `notification` table/object.

#### LCF-NOTIFY-TYPE

```forth
LCF-NOTIFY-TYPE  ( doc-a doc-l -- str-a str-l )
```

Extract the `type` string from the notification table.

#### LCF-NOTIFY-PATH

```forth
LCF-NOTIFY-PATH  ( doc-a doc-l -- str-a str-l )
```

Extract the `path` string from the notification table.

#### LCF-NOTIFY-VALUE

```forth
LCF-NOTIFY-VALUE  ( doc-a doc-l -- str-a str-l )
```

Extract the `value` string from the notification table.

### Writer Word

#### LCF-W-NOTIFICATION

```forth
LCF-W-NOTIFICATION  ( type-a type-l path-a path-l -- )
```

Emit a notification message with the given type and path.
Dispatches to TOML or JSON based on `LCF-FORMAT`.

```forth
256 ALLOT CONSTANT buf
buf 256 LCF-W-INIT
S" event" S" /ui/click" LCF-W-NOTIFICATION
```

---

## Handshake / Session

The handshake protocol establishes a session between DCS and runtime.

### LCF-W-HANDSHAKE

```forth
LCF-W-HANDSHAKE  ( ver-a ver-l caps-bitmask -- )
```

Write a complete handshake action message. `ver-a ver-l` is the
protocol version string (e.g., `S" 1.0"`). `caps-bitmask` encodes
which capability categories to advertise as `true`:

| Bit | Capability |
|-----|------------|
| 0 | `queries` |
| 1 | `mutations` |
| 2 | `behaviors` |
| 3 | `surfaces` |

```forth
buf 1024 LCF-W-INIT
S" 1.0" 11 LCF-W-HANDSHAKE
\ 11 = 0b1011 = queries + mutations + surfaces
```

### LCF-HANDSHAKE?

```forth
LCF-HANDSHAKE?  ( doc-a doc-l -- flag )
```

TRUE if the message is a handshake action (`type = "handshake"`).

### LCF-SESSION-ID

```forth
LCF-SESSION-ID  ( doc-a doc-l -- str-a str-l )
```

Extract the `session-id` from a result message's `[result]` table.
Works on both TOML and JSON session-assignment responses.

---

## Operation Vocabulary

The module includes a built-in table of the 24 standard LIRAQ
operations, useful for input validation and introspection.

### LCF-OP-COUNT

```forth
LCF-OP-COUNT  ( -- 24 )
```

The number of registered operations.

### LCF-OP-VALID?

```forth
LCF-OP-VALID?  ( str-a str-l -- flag )
```

TRUE if the string matches one of the 24 standard operations.
Comparison is case-sensitive.

```forth
S" query"       LCF-OP-VALID?   \ TRUE
S" set-state"   LCF-OP-VALID?   \ TRUE
S" bogus"       LCF-OP-VALID?   \ FALSE
```

### LCF-OP-NTH

```forth
LCF-OP-NTH  ( n -- str-a str-l )
```

Return the nth operation name (0-based). Returns `( 0 0 )` if
index is out of range.

```forth
0  LCF-OP-NTH TYPE   \ "close"
23 LCF-OP-NTH TYPE   \ "write"
24 LCF-OP-NTH        \ 0 0  (out of range)
```

### Standard Operations (alphabetical)

| # | Operation |
|---|-----------|
| 0 | `close` |
| 1 | `composite` |
| 2 | `create` |
| 3 | `create-surface` |
| 4 | `delete` |
| 5 | `destroy-surface` |
| 6 | `draw` |
| 7 | `get-state` |
| 8 | `get-surface` |
| 9 | `handshake` |
| 10 | `list` |
| 11 | `list-surfaces` |
| 12 | `merge` |
| 13 | `move` |
| 14 | `open` |
| 15 | `patch` |
| 16 | `query` |
| 17 | `read` |
| 18 | `render` |
| 19 | `resize-surface` |
| 20 | `set-state` |
| 21 | `subscribe` |
| 22 | `unsubscribe` |
| 23 | `write` |

---

## Writer — Buffer Management

The writer appends TOML (or JSON) text into a caller-supplied buffer.
Always call `LCF-W-INIT` before any write operations. The low-level
KV/table words always emit TOML; the convenience words dispatch on
`LCF-FORMAT`.

### LCF-W-INIT

```forth
LCF-W-INIT  ( buf-a buf-max -- )
```

Initialize the writer with a buffer and its capacity. Resets the
write position to 0.

```forth
CREATE outbuf 4096 ALLOT
outbuf 4096 LCF-W-INIT
```

### LCF-W-LEN

```forth
LCF-W-LEN  ( -- n )
```

Return the number of bytes written so far.

### LCF-W-STR

```forth
LCF-W-STR  ( -- addr len )
```

Return the buffer address and current length as a string pair,
suitable for passing to reader words or `TYPE`.

---

## Writer — Key-Value Emission

### LCF-W-KV-STR

```forth
LCF-W-KV-STR  ( key-a key-l val-a val-l -- )
```

Emit `key = "value"\n`.

### LCF-W-KV-INT

```forth
LCF-W-KV-INT  ( key-a key-l n -- )
```

Emit `key = 42\n`. Handles positive, negative, and zero.

### LCF-W-KV-BOOL

```forth
LCF-W-KV-BOOL  ( key-a key-l flag -- )
```

Emit `key = true\n` or `key = false\n`.

### LCF-W-NL

```forth
LCF-W-NL  ( -- )
```

Emit a blank line (separator between sections).

---

## Writer — Table Headers

### LCF-W-TABLE

```forth
LCF-W-TABLE  ( name-a name-l -- )
```

Emit `[name]\n`.

### LCF-W-ATABLE

```forth
LCF-W-ATABLE  ( name-a name-l -- )
```

Emit `[[name]]\n`.

---

## Writer — Convenience Messages

Pre-built message constructors. Each initializes the writer, emits
a complete message, and returns the length. Output format is
controlled by `LCF-FORMAT` (default: TOML; set to `LCF-FMT-JSON`
for JSON output).

### LCF-W-OK

```forth
LCF-W-OK  ( buf-a buf-max -- len )
```

Write a complete OK response:

```toml
[result]
status = "ok"
```

### LCF-W-ERROR

```forth
LCF-W-ERROR  ( buf-a buf-max err-a err-l detail-a detail-l -- len )
```

Write a complete error response:

```toml
[result]
status = "error"
error = "..."
detail = "..."
```

### LCF-W-VALUE-RESULT

```forth
LCF-W-VALUE-RESULT  ( buf-a buf-max val-a val-l -- len )
```

Write an OK response with a string value:

```toml
[result]
status = "ok"
value = "..."
```

### LCF-W-INT-RESULT

```forth
LCF-W-INT-RESULT  ( buf-a buf-max n -- len )
```

Write an OK response with an integer value:

```toml
[result]
status = "ok"
value = 42
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| **Error Handling** | | |
| `LCF-FAIL` | `( code -- )` | Store error code |
| `LCF-OK?` | `( -- flag )` | True if no error |
| `LCF-CLEAR-ERR` | `( -- )` | Reset error state |
| `LCF-MAX-SIZE` | `( -- 65536 )` | Max message size |
| **Reader — Inspection** | | |
| `LCF-ACTION?` | `( da dl -- f )` | Has `[action]`? |
| `LCF-RESULT?` | `( da dl -- f )` | Has `[result]`? |
| `LCF-ACTION-TYPE` | `( da dl -- sa sl )` | Action type string |
| `LCF-ACTION-TYPE?` | `( da dl -- sa sl f )` | Non-aborting variant |
| `LCF-RESULT-STATUS` | `( da dl -- sa sl )` | Result status string |
| `LCF-RESULT-OK?` | `( da dl -- f )` | Status is "ok"? |
| `LCF-RESULT-ERROR` | `( da dl -- sa sl )` | Error string |
| `LCF-RESULT-DETAIL` | `( da dl -- sa sl )` | Detail string |
| **Reader — Batch** | | |
| `LCF-BATCH-NTH` | `( da dl n -- ba bl )` | Nth batch entry |
| `LCF-BATCH-OP` | `( ba bl -- sa sl )` | Entry "op" string |
| `LCF-BATCH-COUNT` | `( da dl -- n )` | Count batch entries |
| `LCF-ENTRY-STRING` | `( ba bl ka kl -- sa sl )` | Entry string field |
| **Reader — Action** | | |
| `LCF-ACTION-KEY` | `( da dl ka kl -- va vl )` | Action field cursor |
| `LCF-ACTION-STRING` | `( da dl ka kl -- sa sl )` | Action string field |
| `LCF-QUERY-METHOD` | `( da dl -- sa sl )` | Query method |
| `LCF-QUERY-PATH` | `( da dl -- sa sl )` | Query path |
| **Reader — Capabilities** | | |
| `LCF-CAP-VERSION` | `( da dl -- sa sl )` | Capabilities version |
| `LCF-CAP-BOOL` | `( da dl ka kl -- f )` | Boolean capability |
| `LCF-CAP-INT` | `( da dl ka kl -- n )` | Integer capability |
| **Validation** | | |
| `LCF-VALID-KEY?` | `( a l -- f )` | Kebab-case check |
| `LCF-VALIDATE` | `( da dl -- f )` | Size + header check |
| **Format Dispatch** | | |
| `LCF-FMT-TOML` | `( -- 0 )` | TOML format constant |
| `LCF-FMT-JSON` | `( -- 1 )` | JSON format constant |
| `LCF-FORMAT` | `( -- addr )` | Writer format selector |
| **Notifications** | | |
| `LCF-E-NO-NOTIFY` | `( -- 16 )` | No notification error |
| `LCF-NOTIFICATION?` | `( da dl -- f )` | Has `[notification]`? |
| `LCF-NOTIFY-TYPE` | `( da dl -- sa sl )` | Notification type |
| `LCF-NOTIFY-PATH` | `( da dl -- sa sl )` | Notification path |
| `LCF-NOTIFY-VALUE` | `( da dl -- sa sl )` | Notification value |
| `LCF-W-NOTIFICATION` | `( ta tl pa pl -- )` | Write notification msg |
| **Handshake / Session** | | |
| `LCF-W-HANDSHAKE` | `( va vl caps -- )` | Write handshake msg |
| `LCF-HANDSHAKE?` | `( da dl -- f )` | Is handshake? |
| `LCF-SESSION-ID` | `( da dl -- sa sl )` | Session ID from result |
| **Operation Vocabulary** | | |
| `LCF-OP-COUNT` | `( -- 24 )` | Number of operations |
| `LCF-OP-VALID?` | `( sa sl -- f )` | Is standard operation? |
| `LCF-OP-NTH` | `( n -- sa sl )` | Nth operation name |
| **Writer — Management** | | |
| `LCF-W-INIT` | `( buf max -- )` | Initialize writer |
| `LCF-W-LEN` | `( -- n )` | Bytes written |
| `LCF-W-STR` | `( -- a l )` | Buffer as string |
| **Writer — KV** | | |
| `LCF-W-KV-STR` | `( ka kl va vl -- )` | Emit `key = "val"` |
| `LCF-W-KV-INT` | `( ka kl n -- )` | Emit `key = N` |
| `LCF-W-KV-BOOL` | `( ka kl f -- )` | Emit `key = bool` |
| `LCF-W-NL` | `( -- )` | Emit blank line |
| **Writer — Headers** | | |
| `LCF-W-TABLE` | `( na nl -- )` | Emit `[name]` |
| `LCF-W-ATABLE` | `( na nl -- )` | Emit `[[name]]` |
| **Writer — Messages** | | |
| `LCF-W-OK` | `( buf max -- len )` | OK response |
| `LCF-W-ERROR` | `( buf max ea el da dl -- len )` | Error response |
| `LCF-W-VALUE-RESULT` | `( buf max va vl -- len )` | OK + string value |
| `LCF-W-INT-RESULT` | `( buf max n -- len )` | OK + integer value |

---

## Cookbook

### Dispatch on action type

```forth
2DUP LCF-ACTION? IF
    2DUP LCF-ACTION-TYPE
    2DUP S" batch"     STR-STR= IF 2DROP handle-batch     EXIT THEN
    2DUP S" query"     STR-STR= IF 2DROP handle-query     EXIT THEN
    2DUP S" handshake" STR-STR= IF 2DROP handle-handshake EXIT THEN
    2DROP   \ unknown type
THEN
```

### Process all batch entries

```forth
: handle-batch  ( doc-a doc-l -- )
    2DUP LCF-BATCH-COUNT  0 DO
        2DUP I LCF-BATCH-NTH
        2DUP LCF-BATCH-OP TYPE SPACE
        S" path" LCF-ENTRY-STRING TYPE CR
    LOOP 2DROP ;
```

### Build and send an OK response

```forth
CREATE reply 4096 ALLOT
reply 4096 LCF-W-OK  ( -- len )
reply SWAP send-to-dcs
```

### Build a custom error response

```forth
reply 4096
S" not-found" S" Element 'nav' does not exist"
LCF-W-ERROR  ( -- len )
reply SWAP send-to-dcs
```

### Build a multi-field action message

```forth
outbuf 4096 LCF-W-INIT
S" action" LCF-W-TABLE
S" type" S" batch" LCF-W-KV-STR
LCF-W-NL
S" batch" LCF-W-ATABLE
S" op" S" set-state" LCF-W-KV-STR
S" path" S" /ui/theme" LCF-W-KV-STR
S" value" S" dark" LCF-W-KV-STR
LCF-W-STR   ( -- addr len )  \ complete message
```

### Validate before processing

```forth
: process-msg  ( msg-a msg-l -- )
    2DUP LCF-VALIDATE 0= IF
        2DROP
        reply 4096 S" invalid-message" S" Validation failed"
        LCF-W-ERROR DROP
        EXIT
    THEN
    \ ... dispatch on type ...
;
```

### Writer → Reader roundtrip

```forth
CREATE buf 4096 ALLOT
buf 4096 S" Hello" LCF-W-VALUE-RESULT DROP
buf 4096 LCF-W-STR
LCF-RESULT-OK?         \ TRUE
buf 4096 LCF-W-STR
S" result" TOML-FIND-TABLE S" value" TOML-KEY TOML-GET-STRING
\ → "Hello"
```

### Switch to JSON output

```forth
LCF-FMT-JSON LCF-FORMAT !
CREATE jbuf 4096 ALLOT
jbuf 4096 LCF-W-OK   ( -- len )
\ jbuf now contains: {"result":{"status":"ok"}}
LCF-FMT-TOML LCF-FORMAT !   \ restore default
```

### Auto-detect JSON or TOML input

```forth
\ Both work transparently with the same reader words:
S" [action]\ntype = \"query\"" LCF-ACTION-TYPE   \ → "query"
S" {\"action\":{\"type\":\"query\"}}" LCF-ACTION-TYPE  \ → "query"
```

### Send a notification

```forth
buf 4096 LCF-W-INIT
S" event" S" /ui/button-clicked" LCF-W-NOTIFICATION
LCF-W-STR   \ → notification message
```

### Handshake with capability bitmask

```forth
buf 4096 LCF-W-INIT
S" 1.0" 11 LCF-W-HANDSHAKE
\ 11 = 0b1011 → queries + mutations + surfaces
LCF-W-STR   \ → complete handshake message
```

### Validate an operation name

```forth
S" set-state" LCF-OP-VALID?   \ TRUE
S" bogus"     LCF-OP-VALID?   \ FALSE

\ Iterate all operations:
LCF-OP-COUNT 0 DO
    I LCF-OP-NTH TYPE CR
LOOP
```
