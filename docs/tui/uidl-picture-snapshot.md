# UIDL Picture Snapshot

**Provider:** `akashic-tui-uidl-picture-snapshot`
**Prefix:** `UPICSN-` (public), `_UPICSN-` (private)

`UPICSN` describes the pictures a document's `<media>` elements show, one
pointer-free descriptor a picture, for the rich side. Describing a picture
also asks its [picture widget](widgets/picture.md) for a rich copy no larger
than the pixels the picture's rectangle covers on the terminal, so the rich
side never decodes, holds or sends more pixels than the screen can show. A
ready copy is described by its size and SHA3-256 digest; `UPICSN-PULL`
copies its pixels later, while the picture still shows that copy.

The module keeps nothing between calls. Its caller describes afresh
whenever the terminal's pixel size, the space it may use, or the document
may have changed: asking costs nothing when the bound is the one asked for
before.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `UPICSN-CAPTURE` | `( descriptors-a descriptors-u surface-cols surface-rows pixel-w pixel-h byte-budget -- count status )` | Describe every picture shown, asking each for its rich copy |
| `UPICSN-PULL` | `( descriptor dest-a dest-u -- status )` | Copy a described ready copy's pixels into `dest` |
| `UPICSN-BOUND` | `( cols rows surface-cols surface-rows pixel-w pixel-h byte-budget -- max-w max-h )` | The most pixels a rectangle covers |
| `UPICSN-DESCRIPTOR-BYTES` | `( -- bytes )` | Return 160 |

The status domain is `UPICSN-S-OK=0`, `UPICSN-S-CAPACITY=1`,
`UPICSN-S-UNAVAILABLE=2`, `UPICSN-S-INVALID=3` and `UPICSN-S-STALE=4`.
Descriptor banks are eight-byte aligned multiples of 160 bytes. A bank too
small for every picture gives `CAPACITY` and describes nothing.

## The pixels a rectangle covers

`surface-cols` by `surface-rows` cells cover `pixel-w` by `pixel-h` pixels,
the terminal's answer to a pixel question about the whole surface. A
rectangle of `cols` by `rows` cells then covers at most
`cols * pixel-w / surface-cols` by `rows * pixel-h / surface-rows` pixels,
rounded down and at least one each way. A nonzero `byte-budget` lowers that
bound, keeping its shape, to the largest whose RGBA8 bytes fit. A zero pixel
size asks for nothing; so does a budget too small for one pixel.

## Descriptor schema

Each field is one native cell; descriptors hold no pointer.

| Offset | Field | Accessor |
|---:|---|---|
| 0 | Source kind, `UPICSN-SOURCE-UIDL=1` | |
| 8 | UIDL pool source index | `UPICSN-SOURCE-INDEX@` |
| 16 | Source generation, always zero | |
| 24 | Root key, always one | |
| 32 | Screen row | `UPICSN-ROW@` |
| 40 | Screen column | `UPICSN-COLUMN@` |
| 48 | Height in cells | `UPICSN-HEIGHT@` |
| 56 | Width in cells | `UPICSN-WIDTH@` |
| 64 | Resolved UIDL paint z | `UPICSN-Z@` |
| 72 | The rich copy's state | `UPICSN-STATE@` |
| 80 | Why a failed copy failed, `PIC-R-*` | `UPICSN-REASON@` |
| 88 | Copy width in pixels | `UPICSN-COPY-WIDTH@` |
| 96 | Copy height in pixels | `UPICSN-COPY-HEIGHT@` |
| 104 | Copy bytes, width times height times four | `UPICSN-COPY-BYTES@` |
| 112 | Width asked for | `UPICSN-ASK-WIDTH@` |
| 120 | Height asked for | `UPICSN-ASK-HEIGHT@` |
| 128 | The copy's 32-byte SHA3-256 | `UPICSN-DIGEST` |

The copy's state is one of:

| State | Meaning |
|---|---|
| `UPICSN-C-NONE` | Nothing was asked: no pixel size, or no room for a pixel |
| `UPICSN-C-PENDING` | The widget is decoding the copy |
| `UPICSN-C-READY` | The copy is ready; its size and digest are described |
| `UPICSN-C-FAILED` | The copy failed, for the reason given |
| `UPICSN-C-REFUSED` | The widget's memory refused the copy's record |

Descriptors are in increasing source index, with generation zero and root
key one, the identity other families give direct UIDL roots. A picture is
described only when its clip is its whole rectangle; one partly hidden stays
CELL.

## Pulling pixels

`UPICSN-PULL` copies the pixels while the described picture still shows a
ready copy with the same digest and byte length, and answers `STALE`, with
nothing written, once it does not. The caller pulls in the same document
context it described in.
