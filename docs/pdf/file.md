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
| `PDF-FILE-SIZE` | `( -- 232 )` | A file's record, eight-byte aligned. |
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
| `PDF-STREAM-IMAGE` | `( obj buf file -- coding status )` | A picture's stream decoded as far as its own coding (`PDF-DECODE-IMAGE`). |
| `PDF-RAW-SIZE` | `( -- bytes )` | A record that reads a stream's stored bytes in pieces, eight-byte aligned. |
| `PDF-RAW-START` | `( obj file raw -- status )` | Start reading stream `obj`'s stored bytes; `obj` may be given back after. |
| `PDF-RAW-READ` | `( a u raw -- n status )` | The next of them, at most `u`, decrypted, into `a`; `n` is 0 at the end. |
| `PDF-RAW-SPAN` | `( raw -- offset u stored? )` | Where the bytes left lie in the file's media source, and whether they are as stored, not encrypted. |
| `PDF-RESOLVE` | `( va vu type file -- obj va' vu' type' status )` | A value with its reference followed; `obj` is the object to give back, or 0. |
| `PDF-REPAIRED?` | `( file -- flag )` | Whether the file was read by scanning. |
| `PDF-FILE-MSRC` | `( file -- msrc )` | The memory source the file draws on, for the modules that read it. |
| `PDF-FILE-SOURCE` | `( file -- source )` | The media source it reads, which a span source may share. |
| `PDF-FILE-LOCKED?` | `( file -- flag )` | Whether the file is encrypted and could not be opened with the empty password. |

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
holds it. The file holds each object stream it decodes for as long as it
is open, so objects that lie in several streams, read in turn, as a name
tree's nodes and a page tree's are, decode each stream once; each holds
its table of object numbers and offsets, read once into an index, so an
object is found at the place its cross-reference entry gives, its number
checked, or else by searching the index: about 6,000 steps an object
wherever it lies in the stream. When memory refuses a stream, the file
gives back the others and decodes it again. While an object stream is
being decoded no object is read from another, as its own entries lie in
none (PDF 32000-1 7.5.7); a file that asks for one is damaged. An object's record holds a copy of its value: its
spans stay valid until `PDF-OBJ-FREE`, whatever else is read.

A stream's data is read only by `PDF-STREAM`, or in pieces through a
`PDF-RAW-SIZE` record. Its length is the dictionary's `/Length`, followed
when it is a reference, when `endstream` follows that many bytes, after one
line end; otherwise the data runs to the next `endstream`, less the line
end before it.

`PDF-RAW-START` and `PDF-RAW-READ` read a stream's bytes as the file stores
them, before its filters, as many at a time as the caller asks, so a large
picture is never held whole. An encrypted stream's bytes are decrypted as
they come by a `pdf/crypt.f` reader kept in the record: RC4's key stream,
or AES's key and chain. An AES stream's 16-byte IV is taken when it starts;
then whole blocks are decrypted straight into the caller's bytes, but for
the last block, whose padding comes off, and a block when the caller asks
for less than one, which the record holds and gives a part at a time; part
of a block at the end is no data. `PDF-RAW-SPAN` says
whether the bytes left are as stored, so a reader can take them from the
file's own media source instead: `pdf/image.f` makes a JPEG's file a span of
the PDF.

Every buffer comes from the caller's memory source. The file borrows its
media source and keeps one read's bytes at a time in a work buffer. One
call runs at a time.

## Encryption

When the trailer names an `/Encrypt` dictionary, `PDF-OPEN` opens the file
with the empty user password through `pdf/crypt.f`. An object read from the
file then has its strings decrypted, each rewritten in its value as a hex
string of its plain bytes, and a stream's data is decrypted before its
filters. The `/Encrypt` dictionary, cross-reference streams and the objects
inside object streams are left as they are, since they are not encrypted
apart. A file that needs a password still opens: `PDF-FILE-LOCKED?` says
so, its unencrypted parts can be read, and its encrypted streams give
`PDF-S-LOCKED`. RC4, AES-128 and AES-256 files open (`docs/pdf/crypt.md`).
