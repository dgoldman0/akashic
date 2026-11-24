# akashic-game-save — Game Save / Load

Game state as a CBOR map of text keys to integers, text and bytes, kept in
one file that a checked replacement writes. A **save context** gathers
entries and writes them as one file; a **load context** reads the file
back, checks all of it and answers lookups by key. Every call that touches
the file answers a status.

```forth
REQUIRE game/save.f
```

`PROVIDED akashic-game-save` — safe to include multiple times. The module
requires `utf8.f`, `vfs-replace.f` and `vfs-access.f`; a game that binds
its replacement in a place also requires `place-replace.f`.

---

## Table of Contents

- [Where a Save Lives](#where-a-save-lives)
- [Statuses](#statuses)
- [Save API](#save-api)
- [Load API](#load-api)
- [The File](#the-file)
- [Memory](#memory)
- [Costs](#costs)
- [Quick Reference](#quick-reference)

---

## Where a Save Lives

The caller owns a replacement descriptor (`VREPL-SIZE` bytes, zeroed) and
points it at the save's path, as a game points it in its home:

```forth
S" /night.sav" home DUP PLACE-WRITABLE? repl PLACE-VREPL! THROW
```

The save then lands on whichever volume holds the home: the ext4 user
volume in the shipping form, the MP64FS boot volume in the linked build.
`GSAVE-WRITE` replaces the file through the replacement, so a power cut
during a save leaves either the old file or the new one
([vfs-replace.md](../utils/fs/vfs-replace.md)), and `GLOAD-OPEN` first
recovers whatever an interrupted save left. A replacement bound for
reading, as `PLACE-VREPL!` binds one on a read-only grant, loads and
refuses to save. The owner calls `VREPL-FINI` when it lets the descriptor
go.

---

## Statuses

| Constant | Value | Meaning |
|---|---:|---|
| `GSAVE-S-OK` | 0 | Done |
| `GSAVE-S-MISSING` | 1 | No save file |
| `GSAVE-S-CORRUPT` | 2 | The file is no save, or a damaged one |
| `GSAVE-S-IO` | 3 | Reading or writing failed; a failed save left the old file |
| `GSAVE-S-READ-ONLY` | 4 | The place takes no writes: a save is refused, or a load found an interrupted save that only a writable place can settle |
| `GSAVE-S-RECOVERY` | 5 | An interrupted save awaits recovery the replacement could not finish |
| `GSAVE-S-INVALID` | 6 | A save with a repeated key or text that is not UTF-8, or a replacement that is not configured |
| `GSAVE-S-NOMEM` | 7 | No memory for the encoding, the key table or the file |

---

## Save API

### GSAVE-NEW

```
( -- ctx )
```

Allocate a save context with an empty entry buffer of 256 bytes, which
grows as entries come.

### GSAVE-INT / GSAVE-STR / GSAVE-BLOB

```
GSAVE-INT   ( ctx key-a key-u n -- )
GSAVE-STR   ( ctx key-a key-u str-a str-u -- )
GSAVE-BLOB  ( ctx key-a key-u addr len -- )
```

Add an entry: an integer of any cell value, UTF-8 text, or bytes. The
entry buffer copies the key and the value, so the caller's strings need
not outlive the call. Keys are UTF-8 text and must be distinct within a
save; `GSAVE-WRITE` checks both.

### GSAVE-WRITE

```
( ctx replacement -- status )
```

Check the entries, encode them and replace the file the replacement
names. A repeated key, or a key or text that is not UTF-8, answers
`GSAVE-S-INVALID` before anything is written, and the last good save
stays. A replacement whose new file committed while its backup remained
is a save: the call recovers at once to remove the backup and answers
`GSAVE-S-OK`.

### GSAVE-RESET

```
( ctx -- )
```

Forget the entries and keep the buffers, for the context's next save.

### GSAVE-FREE

```
( ctx -- )
```

Free the entry buffer, the encoding buffer, the key table and the
context.

---

## Load API

### GLOAD-OPEN

```
( replacement -- ctx status )
```

Recover any interrupted save, read the file the replacement names and
check all of it. The context is 0 unless the status is `GSAVE-S-OK`. The
file's size is read first and exactly that is allocated, so the load
holds no limit of its own on a save's size.

### GLOAD-INT

```
( ctx key-a key-u -- n found? )
```

The integer saved under the key, and true; 0 and false when the save has
no integer under that key, including when the key holds text or bytes.

### GLOAD-STR / GLOAD-BLOB

```
GLOAD-STR   ( ctx key-a key-u -- addr len found? )
GLOAD-BLOB  ( ctx key-a key-u -- addr len found? )
```

The text or bytes saved under the key, and true; `0 0 false` when the save
has no value of that kind under the key. The bytes lie in the load
context, valid until `GLOAD-CLOSE`.

### GLOAD-COUNT

```
( ctx -- n )
```

The number of entries in the save.

### GLOAD-CLOSE

```
( ctx -- )
```

Free the file's bytes, the index, the key table and the context.

---

## The File

The file is standard CBOR (RFC 8949): one definite-length map whose keys
are text strings and whose values are unsigned integers, negative
integers, text strings and byte strings, in the order they were added.
Each head takes the fewest bytes that hold its argument. An integer `n`
below zero goes out as CBOR's negative form, whose argument is `-1-n`, so
every cell value from -2^63 to 2^63-1 round-trips. Any CBOR tool reads a
save.

The module writes and reads this part of CBOR itself and holds no state
between calls. Its reader checks every head and every length against the
file's end before it reads, and refuses as `GSAVE-S-CORRUPT`:

- anything but one map, or bytes after it;
- a key that is not a text string, or not UTF-8;
- a value of another CBOR type (arrays, maps, tags, simple values and
  floats), an integer outside a signed cell, or text that is not UTF-8;
- indefinite lengths and the reserved additional information 28 to 30;
- a key that appears twice;
- a head or a string that runs past the file's end, and an empty file.

`cbor.f`'s decoder reads lengths without checking them against its input,
and its `CBOR-SKIP` calls itself by name, which the native simulator's
loader refuses, so this module keeps its own writer and checked reader for
the part of CBOR a save uses.

---

## Memory

A save context holds an entry buffer that doubles as entries come, an
encoding buffer sized from the entries and kept between saves, its
capacity a power of two from 256 bytes, and a key table kept between
saves. A load allocates the file's size exactly, an index of 40 bytes an
entry and a key table, and `GLOAD-CLOSE` frees them. Repeated saves and
loads of the same entries reuse the same holes: ten rounds of 301 entries
leave `XMEM-HERE` where the first left it.

Keys are found through a hash table: FNV-1a picks a key's first slot and a
probe walks on to the next until it meets the key or an empty slot. The
table has a power of two of slots, at least twice the entries, so the
check for repeated keys at a save takes time in proportion to the entries,
and a lookup in proportion to its key.

---

## Costs

Emulator cycles for a save of 80 integers and two blobs of 288 bytes, a
file of 1,381 bytes, on a RAM volume (2026-11-23):

| Call | Cycles |
|---|---:|
| 82 adds | 134,371 |
| The check for repeated keys and UTF-8 | 220,521 |
| The file's size | 68,302 |
| Encoding | 220,017 |
| `GSAVE-WRITE`, all of it | 1,354,157 |
| `GLOAD-OPEN`, all of it | 728,069 |
| 80 lookups | 127,955 |

On the ext4 user volume a save of 2 to 16 KiB costs 1.25 to 1.35 s of
processor time in the writer, so games save at explicit points, such as
the end of a night or the player's Save.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `GSAVE-NEW` | `( -- ctx )` | Create a save context |
| `GSAVE-INT` | `( ctx ka ku n -- )` | Add an integer |
| `GSAVE-STR` | `( ctx ka ku sa su -- )` | Add UTF-8 text |
| `GSAVE-BLOB` | `( ctx ka ku a u -- )` | Add bytes |
| `GSAVE-WRITE` | `( ctx repl -- status )` | Check, encode and replace the file |
| `GSAVE-RESET` | `( ctx -- )` | Forget the entries |
| `GSAVE-FREE` | `( ctx -- )` | Free the context |
| `GLOAD-OPEN` | `( repl -- ctx status )` | Recover, read and check the file |
| `GLOAD-INT` | `( ctx ka ku -- n found? )` | Look up an integer |
| `GLOAD-STR` | `( ctx ka ku -- a u found? )` | Look up text |
| `GLOAD-BLOB` | `( ctx ka ku -- a u found? )` | Look up bytes |
| `GLOAD-COUNT` | `( ctx -- n )` | Entries in the save |
| `GLOAD-CLOSE` | `( ctx -- )` | Free the load |
