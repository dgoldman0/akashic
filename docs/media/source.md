# akashic-media-source — the bytes of one thing

A media source stands for the bytes of a file, a download, or anything else
a viewer shows. Readers ask for an exact span at any offset and never learn
where the bytes live. Whoever made a source releases it, which gives back
what it holds, such as an open file.

```forth
REQUIRE media/source.f       \ the record and memory sources
REQUIRE media/vfs-source.f   \ files in a VFS
```

## The record

A source is a record its creator owns, `MEDSRC-SIZE` bytes and eight-byte
aligned. A kind of source may extend the record after those bytes, as the
VFS source does, so the record itself is the source every reader takes.

| Word | Stack | Meaning |
|---|---|---|
| `MEDSRC-INIT` | `( size read-xt release-xt context source -- )` | Make a source. `read-xt` is `( buf len offset context -- ior )` and fills `buf` with exactly `len` bytes or returns a nonzero ior. `release-xt` is `( context -- )`, or 0. |
| `MEDSRC-VALID?` | `( source -- flag )` | A live source. |
| `MEDSRC-SIZE@` | `( source -- bytes )` | How many bytes it has. |
| `MEDSRC-READ?` | `( buf len offset source -- ior )` | Read an exact span. A span past the end, or one whose end wraps, is refused with `MEDSRC-E-RANGE` before the reader runs; a dead source gives `MEDSRC-E-INVALID`. A reader's own iors pass through. |
| `MEDSRC-RELEASE` | `( source -- )` | Give back what the source holds. The record is no longer a source. |

## Kinds of source

`MEDSRC-MEMORY ( a u source -- )` reads `u` bytes at `a`, which the creator
keeps unchanged and alive until it releases the source. It suits bytes a
download or another program already holds. It holds nothing, so releasing it
only ends it.

`MEDSRC-SPAN ( offset u base source -- )` reads the `u` bytes of the source
`base` from `offset`, as a file of its own: a picture inside a PDF, say. Its
record is `MEDSRC-SPAN-SIZE` bytes. The creator keeps `base` alive until it
releases the span, which gives nothing back. A span past the base's end is
refused by the base when it is read.

`MEDSRC-VFS-OPEN ( path-a path-u vfs source -- ior )` opens a file read-only
as a source in a record of `MEDSRC-VFS-SIZE` bytes. The file stays open until
the source is released. If the file system changes under the open file, reads
fail with the VFS's stale-file error and the viewer says so; a new source
sees the new file. On a nonzero ior nothing is open and the record is not a
source.
