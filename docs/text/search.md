# akashic-search — Text Search for Gap Buffer

Byte-pattern matching over gap-buffer logical content.
Case-sensitive and case-insensitive variants.  Forward and reverse
search.  Replace is left to the caller (move cursor, delete, insert).

```forth
REQUIRE text/search.f
```

`PROVIDED akashic-search` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Forward Search](#forward-search)
- [Reverse Search](#reverse-search)
- [Count](#count)
- [Replace Pattern](#replace-pattern)
- [Quick Reference](#quick-reference)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Logical addressing** | All positions are logical byte offsets (gap-transparent). |
| **Byte-level match** | Matches raw bytes via `GB-BYTE@` — works with any encoding. |
| **Case folding** | Insensitive variants use `_STR-LC` from `string.f`. |
| **No allocation** | Module temporaries only. |
| **Prefix convention** | Public: `SRCH-`. Internal: `_SRCH-`. |

---

## Forward Search

### SRCH-FIND

```
( pos ndl-a ndl-u gb -- match | -1 )
```

Find first occurrence of needle at or after `pos`.  Returns the
matching byte offset, or `−1` if not found.  Case-sensitive.

### SRCH-IFIND

```
( pos ndl-a ndl-u gb -- match | -1 )
```

Case-insensitive forward search (ASCII letters only).

```forth
0  S" REQUIRE"  my-gb  SRCH-IFIND   \ → byte offset or -1
```

---

## Reverse Search

### SRCH-RFIND

```
( pos ndl-a ndl-u gb -- match | -1 )
```

Find last occurrence of needle at or before `pos`.  Case-sensitive.
`pos` is clamped to the maximum valid start position.

### SRCH-IRFIND

```
( pos ndl-a ndl-u gb -- match | -1 )
```

Case-insensitive reverse search.

```forth
\ Search backward from end of document
my-gb GB-LEN  S" TODO"  my-gb  SRCH-IRFIND
```

---

## Count

### SRCH-COUNT

```
( ndl-a ndl-u gb -- n )
```

Count non-overlapping occurrences of needle (forward, case-sensitive).
Scans the entire buffer from position 0.

### SRCH-ICOUNT

```
( ndl-a ndl-u gb -- n )
```

Case-insensitive count.

```forth
S" the"  my-gb  SRCH-ICOUNT   \ → 42
```

---

## Replace Pattern

Replace is not in this module.  The caller composes search + gap
buffer operations:

```forth
\ Find and replace first occurrence:
0 S" old" my-gb SRCH-FIND   ( match )
DUP -1 <> IF
    my-gb GB-MOVE!
    3 my-gb GB-DEL 2DROP        \ delete "old"
    S" new" my-gb GB-INS        \ insert "new"
    \ Record undo entries as needed
ELSE DROP THEN
```

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `SRCH-FIND` | `( pos ndl-a ndl-u gb -- match \| -1 )` | Forward search |
| `SRCH-IFIND` | `( pos ndl-a ndl-u gb -- match \| -1 )` | Forward (case-insensitive) |
| `SRCH-RFIND` | `( pos ndl-a ndl-u gb -- match \| -1 )` | Reverse search |
| `SRCH-IRFIND` | `( pos ndl-a ndl-u gb -- match \| -1 )` | Reverse (case-insensitive) |
| `SRCH-COUNT` | `( ndl-a ndl-u gb -- n )` | Count matches |
| `SRCH-ICOUNT` | `( ndl-a ndl-u gb -- n )` | Count (case-insensitive) |

---

## Dependencies

- `text/gap-buf.f` — `GB-BYTE@`, `GB-LEN`
- `utils/string.f` — `_STR-LC` (byte lowercase for case-insensitive matching)

## Consumers

- Akashic Pad — find/replace, search-and-count

## Internal State

Module-level `VARIABLE`s prefixed `_SRCH-`:

- `_SRCH-GB` — current gap buffer handle
- `_SRCH-NA`, `_SRCH-NU` — needle address and length

Not reentrant without the `GUARDED` guard section.
