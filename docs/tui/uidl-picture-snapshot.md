# UIDL Picture Snapshot

**Provider:** `akashic-tui-uidl-picture-snapshot`
**Prefix:** `UPICSN-` (public), `_UPICSN-` (private)

`UPICSN` describes the pictures a document's `<media>` elements show, one
pointer-free descriptor a picture, for the rich side: an element's own
picture, or each figure with a row in view in the
[document](widgets/document.md) an element shows. A picture whose file
the terminal decodes is described as that file, ready at once at the
picture's own size: no copy is made and no pixel size is needed. Any other
picture is asked, through its [picture widget](widgets/picture.md), for a
rich copy no larger than the pixels the picture's rectangle covers on the
terminal, so the rich side never decodes, holds or sends more pixels than
the screen can show. A ready file or copy is described by its format and
size; `UPICSN-PULL` copies a span of its bytes later, while the picture still
shows that file or copy, so the rich side can send it a chunk at a time. Each
descriptor also names the picture's revision, which every copy of that
picture shares. When the rich side cannot send a picture because of the
picture itself, `UPICSN-FAIL` has its widget remember why, and captures
describe it as failed until the widget is given another source.

The module keeps nothing between calls. Its caller describes afresh
whenever the terminal's pixel size, the space it may use, or the document
may have changed: asking costs nothing when the bound is the one asked for
before.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `UPICSN-CAPTURE` | `( descriptors-a descriptors-u ask -- count status )` | Describe every picture shown, asking each for its rich copy |
| `UPICSN-PULL` | `( descriptor offset dest-a dest-u -- status )` | Copy a span of a described file, or of a ready copy's pixels, into `dest` |
| `UPICSN-FAIL` | `( source-index root-key revision reason -- status )` | Have a picture the rich side could not send remember why |
| `UPICSN-BOUND` | `( cols rows ask -- max-w max-h )` | The most pixels a rectangle covers |
| `UPICSN-DESCRIPTOR-BYTES` | `( -- bytes )` | Return 192 |
| `UPICSN-ASK-SIZE` | `( -- bytes )` | Return 72 |
| `UPICSN-RELEASE-ALL` | `( -- )` | Let go of every picture a capture claimed, in every document |

The status domain is `UPICSN-S-OK=0`, `UPICSN-S-CAPACITY=1`,
`UPICSN-S-UNAVAILABLE=2`, `UPICSN-S-INVALID=3` and `UPICSN-S-STALE=4`.
Descriptor banks are eight-byte aligned multiples of 192 bytes. A bank too
small for every picture gives `CAPACITY`, writes nothing, and counts how many
descriptors it would take.

## The pixels a rectangle covers

The caller's ask is a record of nine native cells:

| Offset | Field | Accessor |
|---:|---|---|
| 0 | Surface columns | `UPICSN-ASK.SURFACE-COLS` |
| 8 | Surface rows | `UPICSN-ASK.SURFACE-ROWS` |
| 16 | Pixels across the whole surface, zero when unknown | `UPICSN-ASK.PIXEL-W` |
| 24 | Pixels down the whole surface | `UPICSN-ASK.PIXEL-H` |
| 32 | Most pixels across one copy, zero for no limit | `UPICSN-ASK.MAX-W` |
| 40 | Most pixels down one copy, zero for no limit | `UPICSN-ASK.MAX-H` |
| 48 | Most bytes of one picture, as decoded, zero for no limit | `UPICSN-ASK.BUDGET` |
| 56 | The picture files the terminal decodes, `PIC-F-` format N at bit N-1 | `UPICSN-ASK.FORMATS` |
| 64 | Nonzero when the rich side takes the pictures it is given | `UPICSN-ASK.CLAIM` |

A picture whose file format is in `FORMATS` is described as its file when
its own size is within `MAX-W` and `MAX-H` and its decoded size within
`BUDGET`; it needs no pixel size. Otherwise it is asked for a copy, and the
surface's pixels are the terminal's answer to a pixel question about the
whole surface. A rectangle of `cols` by `rows` cells then covers at
most `cols * pixel-w / surface-cols` by `rows * pixel-h / surface-rows`
pixels, rounded down and at least one each way. The largest picture the
terminal takes and the byte budget each lower that bound, keeping its
shape. A pixel size of zero, or over 2^30 - 1 either way, asks for nothing;
so does a budget too small for one pixel.

## Descriptor schema

Each field is one native cell; descriptors hold no pointer.

| Offset | Field | Accessor |
|---:|---|---|
| 0 | Source kind, `UPICSN-SOURCE-UIDL=1` | |
| 8 | UIDL pool source index | `UPICSN-SOURCE-INDEX@` |
| 16 | Source generation, always zero | |
| 24 | Root key: one for an element's own picture, a figure's block key | `UPICSN-ROOT-KEY@` |
| 32 | Screen row of the whole rectangle, which may lie off the screen | `UPICSN-ROW@` |
| 40 | Screen column of the whole rectangle | `UPICSN-COLUMN@` |
| 48 | Height in cells | `UPICSN-HEIGHT@` |
| 56 | Width in cells | `UPICSN-WIDTH@` |
| 64 | Resolved UIDL paint z | `UPICSN-Z@` |
| 72 | The rich copy's state | `UPICSN-STATE@` |
| 80 | Why a failed copy failed, `PIC-R-*` | `UPICSN-REASON@` |
| 88 | Copy width in pixels | `UPICSN-COPY-WIDTH@` |
| 96 | Copy height in pixels | `UPICSN-COPY-HEIGHT@` |
| 104 | Bytes: width times height times four for a copy, the file's length for a file | `UPICSN-COPY-BYTES@` |
| 112 | Width asked for | `UPICSN-ASK-WIDTH@` |
| 120 | Height asked for | `UPICSN-ASK-HEIGHT@` |
| 128 | The format: `PIC-F-RGBA8` for a copy the widget makes, also while it is not ready, or the file's | `UPICSN-FORMAT@` |
| 136 | The caller's document key, zero after capture | `UPICSN-DOCUMENT@`, `UPICSN-DOCUMENT!` |
| 144 | The picture's revision, shared by every copy of it | `UPICSN-REVISION@` |
| 152 | The clip's row, in cells from the rectangle's top | `UPICSN-CLIP-ROW@` |
| 160 | The clip's column, from the rectangle's left | `UPICSN-CLIP-COLUMN@` |
| 168 | The clip's height, at least one | `UPICSN-CLIP-HEIGHT@` |
| 176 | The clip's width, at least one | `UPICSN-CLIP-WIDTH@` |
| 184 | Nonzero for a figure in a document | `UPICSN-FIGURE?` |

The copy's state is one of:

| State | Meaning |
|---|---|
| `UPICSN-C-NONE` | Nothing was asked: no pixel size, or no room for a pixel |
| `UPICSN-C-PENDING` | The widget is decoding the copy |
| `UPICSN-C-READY` | The copy is ready; its format and size are described |
| `UPICSN-C-FAILED` | The copy failed, or the rich side could not send the picture, for the reason given |
| `UPICSN-C-REFUSED` | The widget's memory refused the copy's record |

Descriptors are in increasing source index and, within one element,
increasing root key, with generation zero. An element's own picture has root
key one, the identity other families give direct UIDL roots. A figure has
its block's key, the block's index plus one, and is described while it has a
row in view, in block order. A descriptor gives the picture's whole
rectangle, which may reach off the screen, and the part of it shown, its
clip: a figure partly scrolled out of its document shows only that part, at
its whole size, and its copy is asked for at its whole rectangle, so
scrolling asks for nothing new. A picture with nothing of it shown is not
described. A figure lies in its document's rectangle, which the document's
root claims on the rich side.

## Claims

When the ask's `CLAIM` is nonzero, a capture claims each picture it
describes as a file, or as a copy ready or being made: the picture widget's
CELL view then shows the picture's name, format and size beneath it and
decodes nothing. Every other picture visited, including one with nothing
of it shown, is not claimed, and CELL shows it. A bank too small only
counts, and leaves claims as they were. Every capture also tells picture
widgets which file formats the rich side takes, `FORMATS` while `CLAIM` is
nonzero and none otherwise, so a new picture of one of them shows what it
is from its first draw rather than start a CELL copy. `UPICSN-RELEASE-ALL`
lets every claim go at once, when the rich side shows no picture or can
take none.

## Pulling a picture

`UPICSN-PULL` copies `dest-u` bytes of a described file, or of a copy's
pixels, from `offset` into `dest`. The span must lie within the descriptor's
bytes and hold at least one byte; one that does not answers `INVALID`. It
copies while the described picture still has the same revision and goes as
the same file, or has a ready copy of the same size, and answers `STALE`,
with nothing written, once it does not, or when the file could not be read. A
copy is the picture decoded at that size, so nothing else could match. A
picture widget takes a new revision with every source it is given, so a
picture opened again is a new picture, while its copies at any size share one
revision. The descriptor's source index and root key name the picture, an
element's own or a figure in the document it shows: a figure scrolled out
of view has no picture widget, so a pull of it is `STALE`. The caller pulls
in the same document context it described in.

A file that cannot be read is the picture's own failure: the pull has its
widget remember `PIC-R-READ`, as `UPICSN-FAIL` would.

## A picture the rich side could not send

`UPICSN-FAIL` says the rich side could not send picture `revision` at the
source index and root key because of the picture itself, for a `PIC-R-`
reason, such as
`PIC-R-DAMAGED` when the terminal refused its bytes. The picture's widget
remembers the reason until it is given another source, and its claim goes.
Every capture until then describes the picture as `UPICSN-C-FAILED` with that
reason, asks for no copy and claims nothing, so the rich side never sends it
again and CELL shows it. It answers `STALE`, remembering nothing, once that
element or figure shows another picture or none, and runs in the document's
context.
