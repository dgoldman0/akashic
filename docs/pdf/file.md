# akashic-pdf-file — a PDF file's objects

A PDF file opened over a media source, its objects read only when asked
for (PDF 32000-1, section 7.5).

```forth
REQUIRE pdf/file.f
```

`PROVIDED akashic-pdf-file`. It requires `pdf/lexer.f`, `pdf/filter.f` and
`media/source.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-FILE-SIZE` | `( -- 160 )` | A file's record, eight-byte aligned. |
| `PDF-OPEN` | `( source msrc file -- status )` | Read the cross-reference sections and trailer. |
| `PDF-CLOSE` | `( file -- )` | Give back everything; call it whatever `PDF-OPEN` said. |
| `PDF-TRAILER@` | `( key-a key-u file -- va vu type )` | A trailer entry, such as `Root`. |
| `PDF-OBJECT-COUNT` | `( file -- n )` | The object numbers the table spans, from 0. |
| `PDF-GET` | `( num file -- obj status )` | An object in a record of its own. |
| `PDF-OBJ-FREE` | `( obj file -- )` | Give an object's record back; 0 does nothing. |
| `PDF-OBJ-VALUE` | `( obj -- va vu type )` | The object's value, a span of its record. |
| `PDF-OBJ-NUM` | `( obj -- num gen )` | Its object and generation numbers. |
| `PDF-OBJ-STREAM?` | `( obj -- flag )` | Whether it is a stream. |
| `PDF-STREAM` | `( obj buf file -- status )` | A stream's data, decoded through its filters into `buf` (`pdf/filter.f`). |
| `PDF-RESOLVE` | `( va vu type file -- obj va' vu' type' status )` | A value with its reference followed; `obj` is the object to give back, or 0. |
| `PDF-REPAIRED?` | `( file -- flag )` | Whether the file was read by scanning. |

The statuses are `pdf/filter.f`'s, and `PDF-S-MISSING` for an object that
is free or that no section lists.

## Opening

`PDF-OPEN` finds `startxref` in the file's last kilobyte and reads the
section there, a table or a cross-reference stream, then the section each
one's `/Prev` names, and a hybrid file's `/XRefStm`. A newer section's entry
for an object stands over an older one's, so an incremental update is read
as its writer meant. The first trailer with a `/Root` is kept: a table's
trailer, or a cross-reference stream's dictionary. More sections than the
file could hold, one for every 16 bytes, mean a loop.

When a section cannot be read, or no trailer names a `/Root`, the file is
read again by scanning it: every `num gen obj` it holds, a later one
standing over an earlier one; the objects in each object stream it finds,
unless the file holds them itself; and its last trailer, or failing that a
trailer naming the first object whose `/Type` is `/Catalog`. `PDF-GET` does
the same, once, when an object of an open file is not where its entry says.

## Objects

`PDF-GET` reads an object from its offset or from the object stream that
holds it. The object stream last used stays decoded, so its other objects
cost no second decode. An object's record holds a copy of its value: its
spans stay valid until `PDF-OBJ-FREE`, whatever else is read.

A stream's data is read only by `PDF-STREAM`. Its length is the
dictionary's `/Length`, followed when it is a reference, when `endstream`
follows that many bytes, after one line end; otherwise the data runs to the
next `endstream`, less the line end before it.

Every buffer comes from the caller's memory source. The file borrows its
media source and keeps one read's bytes at a time in a work buffer. One
call runs at a time.
