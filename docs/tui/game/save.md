# akashic-tui-game-save — Game Save / Load

Serialize and deserialize game state as a CBOR map stored on disk.
A **save context** accumulates key-value entries (integers, strings,
blobs) in a linear buffer, encodes them as a CBOR map, and writes the
result to a named file.  A **load context** reads a file, parses the
CBOR, and provides key-based lookups.

```forth
REQUIRE tui/game/save.f
```

`PROVIDED akashic-tui-game-save` — safe to include multiple times.

---

## Table of Contents

- [Save API](#save-api)
- [Load API](#load-api)
- [Descriptor Layout](#descriptor-layout)
- [Entry Buffer Format](#entry-buffer-format)
- [Quick Reference](#quick-reference)

---

## Save API

### GSAVE-NEW

```
( -- ctx )
```

Allocate a new save context with a 16 KB entry buffer.  All fields
are zeroed.  The returned `ctx` is used with all subsequent save
operations.

```forth
GSAVE-NEW CONSTANT sv
```

### GSAVE-INT

```
( ctx key-a key-u val -- )
```

Accumulate an integer entry.  `key-a key-u` is the key string;
`val` is a cell-sized integer.

```forth
sv S" score" 42 GSAVE-INT
```

### GSAVE-STR

```
( ctx key-a key-u str-a str-u -- )
```

Accumulate a text string entry.

```forth
sv S" name" S" hero" GSAVE-STR
```

### GSAVE-BLOB

```
( ctx key-a key-u addr len -- )
```

Accumulate a binary blob entry.  The data at `addr len` is copied
into the entry buffer.

### GSAVE-WRITE

```
( ctx path-a path-u -- ior )
```

Encode all accumulated entries as a CBOR map and write them to the
file at `path-a path-u`.  The file is created (64 sectors,
type DATA) if it does not already exist.

Returns 0 on success, -1 if the file could not be opened/created,
-2 on CBOR encoding error.

```forth
sv S" save1.dat" GSAVE-WRITE  0<> ABORT" write failed"
```

### GSAVE-FREE

```
( ctx -- )
```

Free the save context and its entry buffer.

---

## Load API

### GLOAD-OPEN

```
( path-a path-u -- ctx | 0 )
```

Open a save file, read its contents (up to 16 KB), and parse the
CBOR map.  Returns a load context, or 0 if the file does not exist,
is empty, or fails to parse as a CBOR map.

```forth
S" save1.dat" GLOAD-OPEN DUP 0= ABORT" open failed"
```

### GLOAD-INT

```
( ctx key-a key-u -- val )
```

Look up an integer value by key.  Returns 0 if the key is not
found or the value is not a CBOR unsigned integer.

```forth
ctx S" score" GLOAD-INT .  \ prints 42
```

### GLOAD-STR

```
( ctx key-a key-u -- addr len )
```

Look up a text string value by key.  Returns `0 0` if not found.
The returned address points into the internal load buffer and is
valid until `GLOAD-CLOSE` is called.

### GLOAD-BLOB

```
( ctx key-a key-u -- addr len )
```

Look up a byte string (blob) value by key.  Returns `0 0` if not
found.  The returned address points into the internal load buffer
and is valid until `GLOAD-CLOSE` is called.

### GLOAD-CLOSE

```
( ctx -- )
```

Free the load context descriptor.  After this call, any pointers
returned by `GLOAD-STR` or `GLOAD-BLOB` are invalid.

---

## Descriptor Layout

72 bytes (9 cells):

```
Offset  Size  Field       Used in
──────  ────  ──────────  ──────────
 +0       8  buf          Save: entry buffer address
 +8       8  buf-cap      Save: buffer capacity (default 16384)
+16       8  count        Save: number of entries accumulated
+24       8  eptr         Save: write offset into entry buffer
+32       8  fd           File descriptor (during I/O)
+40       8  mode         0 = save, 1 = load
+48       8  parse-addr   Load: CBOR data start address
+56       8  parse-len    Load: CBOR data length
+64       8  map-count    Load: CBOR map pair count
```

---

## Entry Buffer Format

Entries are stored sequentially in the linear buffer.  Each
entry begins with a 1-byte type tag, a 2-byte LE key length,
and key bytes, followed by type-specific payload:

| Type | Tag | Payload |
|------|-----|---------|
| INT  | 0   | 8-byte LE value |
| STR  | 1   | 2-byte LE length + string bytes |
| BLOB | 2   | 2-byte LE length + raw bytes |

When `GSAVE-WRITE` is called, the entry buffer is walked and
each entry is encoded into a single CBOR map.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `GSAVE-NEW` | `( -- ctx )` | Create save context |
| `GSAVE-INT` | `( ctx key-a key-u val -- )` | Add integer entry |
| `GSAVE-STR` | `( ctx key-a key-u str-a str-u -- )` | Add string entry |
| `GSAVE-BLOB` | `( ctx key-a key-u addr len -- )` | Add blob entry |
| `GSAVE-WRITE` | `( ctx path-a path-u -- ior )` | Encode & write to disk |
| `GSAVE-FREE` | `( ctx -- )` | Free save context |
| `GLOAD-OPEN` | `( path-a path-u -- ctx \| 0 )` | Open & parse save file |
| `GLOAD-INT` | `( ctx key-a key-u -- val )` | Look up integer |
| `GLOAD-STR` | `( ctx key-a key-u -- addr len )` | Look up string |
| `GLOAD-BLOB` | `( ctx key-a key-u -- addr len )` | Look up blob |
| `GLOAD-CLOSE` | `( ctx -- )` | Free load context |
