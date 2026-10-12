# akashic/utils/fs/link-path.f — the path a document's link names

```forth
REQUIRE utils/fs/link-path.f
```

A link in a document names a file by a path from the folder of the file
that holds the link, or from the root when it starts with `/`.
`LPATH-RESOLVE` turns such a target into the path it names, as Pad and the
media widget's documents follow links and find figures:

- a `#fragment` or `?query` is left out;
- empty and `.` steps add nothing, and `..` goes back one folder;
- a target that begins with a URI scheme, as RFC 3986 spells one (a letter,
  then letters, digits, `+`, `-` or `.`, then `:`), names no file:
  `https:`, `mailto:` and the like.

The path is absolute when the target or the base is, and `..` never goes
above the root; a link to the root gives `/`. From a relative base the path
stays relative, for a file system to take from its current folder: `..`
steps it cannot undo stay at its start, and a link to that folder gives `.`.

| Status | Value | Meaning |
|---|---|---|
| `LPATH-S-OK` | 0 | The path is in the buffer. |
| `LPATH-S-EMPTY` | 1 | No path: an empty target, or only a fragment or query. |
| `LPATH-S-SCHEME` | 2 | A scheme, so no file. |
| `LPATH-S-ROOM` | 3 | The path does not fit the buffer. |

The path goes into the caller's buffer. It is never longer than
`LPATH-BOUND`, the base's length and the target's and one byte more, so a
caller can size the buffer exactly.

| Word | Stack |
|---|---|
| `LPATH-BOUND` | `( target-u base-u -- bytes )` |
| `LPATH-RESOLVE` | `( target-a target-u base-a base-u buf cap -- u status )` |

`base` is the path of the file that holds the link, or `0 0` for none,
which starts a relative target at the root.
