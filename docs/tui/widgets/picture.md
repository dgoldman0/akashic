# akashic/tui/widgets/picture.f — Picture Widget

**Prefix:** `PICT-` (public), `_PICT-` (internal)  
**Provider:** `akashic-tui-picture`  
**Dependencies:** `widget.f`, `draw.f`, `color.f`,
[media/picture.f](../../media/picture.md), `memory-source.f`, `string.f`

## Overview

Shows one picture from a [media source](../../media/source.md), fitted
inside the widget and centred, keeping its shape and never enlarged. The
source and the text alternative are borrowed: the caller keeps them alive
until it sets others or frees the widget.

In CELL each cell is an upper half block (U+2580). Its foreground is the
upper pixel and its background the lower one, so a cell holds two
square-ish pixels. The widget asks [media/picture.f](../../media/picture.md)
for a copy as wide as the widget in cells and twice as high, which is the
most CELL can show, and keeps two palette indices a cell, so a redraw only
places cells.

A rich terminal shows the same picture at its own resolution from the same
source. Given a source, the widget reads the file's format and the
picture's size from its first bytes (`PIC-FILE`, `PICT-FILE@`). A terminal
that decodes that format takes the file as it is (`PICT-FILE-READ`), so no
copy is made. For any other terminal the rich side asks the widget for a
rich copy no larger than the pixels the widget's area covers there
(`PICT-RICH-ASK`) and reads it once ready (`PICT-RICH@`). The rich copy is
the widget's: it goes when the rich side asks for another size, when the
widget shows another picture, and when the widget is freed.

CELL decodes only QOI. A PNG or JPEG shows its format and size in CELL,
under its text alternative, for example `PNG, 1920 × 1080`, and decodes
nothing.

### While the rich side shows the picture

The rich side says whether it shows the picture, or is taking it to show
it (`PICT-CLAIM!`). While it does, CELL shows the same label, the text
alternative over the format and size, beneath the rich picture and decodes
nothing: a CELL copy still decoding stops, and one already made is kept for
later. So a picture the terminal decodes costs the guest no decoding at all.

`PICT-RELEASE-ALL` lets every claim go at once, when the rich side shows no
picture or can take none: an empty rich frame, a fault, a producer that
ends, or one that failed to send a picture. A widget
showing the label for a claim that has gone is pending again, so the host's
service pass marks it dirty, and its redraw makes the CELL copy.

Each source the widget is given takes a new revision (`PICT-REVISION@`), a
number no earlier source of any picture widget had. Copies of one picture at
any size share it, and another picture, or the same file given again, never
does, so the rich side can tell a new size of the picture it shows from a
different picture.

### Colours

Each pixel becomes the nearest palette colour (`TUI-RESOLVE-COLOR`). A
transparent pixel, and any cell outside the picture, is the background the
widget draws on (`DRW-BG@` when it draws). A partly transparent pixel is
blended onto that background first, each channel
`(c·a + bg·(255 − a) + 127) / 255`. A cell whose two pixels are both the
background stays a plain space, and the caller's style is as it was after
the draw.

### Decoding and placeholders

Drawing asks for a copy of the size the widget shows, and a copy that is
not ready yet is decoded by `PICT-SERVICE` in bounded slices, so drawing
never waits: the CELL copy first, since it is what shows until the rich
one is ready, then the rich copy. A widget that is never drawn never
decodes. A new size, from a resize, starts a new copy.

Until the picture is shown the widget says why, centred: the text
alternative on the row above, when there is room for it, and one of

| Message | When |
|---|---|
| Loading the picture | The copy is still decoding |
| This picture's format can't be shown yet | The source is not a picture `media/picture.f` decodes |
| The picture is damaged | A bad header, a short file, or a wrong end marker |
| The picture could not be read | The source failed |
| Not enough memory to show the picture | The memory source refused the copy or its colours |
| The picture could not be shown | Any other failure |

## API

| Word | Stack | Meaning |
|---|---|---|
| `PICT-NEW` | `( rgn msrc -- widget )` | A picture widget showing nothing. Its copies and colours come from the memory source `msrc`. |
| `PICT-SOURCE!` | `( source alt-a alt-u widget -- )` | Show the picture in `source`, with `alt` as its text alternative; a zero source shows nothing. Gives back the old copy and takes a new revision. |
| `PICT-ALT!` | `( alt-a alt-u widget -- )` | Change the text alternative alone. |
| `PICT-SERVICE` | `( budget widget -- changed? )` | Decode about `budget` source pixels, at least one row, of the CELL copy while it decodes and then of the rich copy. A claimed picture's CELL copy still decoding stops instead, and a label whose claim has gone gives way to the picture. True when what the widget shows, on either side, changed; the widget is then dirty. |
| `PICT-RICH-ASK` | `( max-w max-h widget -- ok? )` | Ask for a rich copy no larger than `max-w` by `max-h` pixels. A new bound gives back the copy there was and starts another; the bound asked before keeps the copy there is. False when nothing is shown or the memory source refused the copy's record. |
| `PICT-RICH@` | `( widget -- pic \| 0 )` | The rich copy asked for, pending, ready or failed, read with [media/picture.f](../../media/picture.md)'s words. |
| `PICT-REVISION@` | `( widget -- revision )` | Which picture the widget shows: new with every source, shared by all its copies; 0 before the first source. |
| `PICT-FILE@` | `( widget -- format width height )` | The file's `PIC-F-` format and the picture's size, as its file says; `0 0 0` for no source or a file that is no picture `PIC-FILE` knows. |
| `PICT-FILE-BYTES@` | `( widget -- bytes )` | The file's length; 0 with no source. |
| `PICT-FILE-READ` | `( a u offset widget -- ior )` | Read `u` bytes of the file at `offset` into `a`, as its source reads them. |
| `PICT-CLAIM!` | `( flag widget -- )` | The rich side says whether it shows the picture, or is taking it to show it. The CELL view follows at the next service pass or draw. |
| `PICT-CLAIMED?` | `( widget -- flag )` | The claim holds: set, and not let go since. |
| `PICT-RELEASE-ALL` | `( -- )` | Let every claim go at once. |
| `PICT-STEP-PIXELS` | `( -- n )` | The budget the UIDL host gives a widget each pass (16,384). |
| `PICT-PENDING?` | `( widget -- flag )` | One of this widget's copies is decoding, or it shows the label for a claim that has gone. |
| `PICT-WORK?` | `( -- flag )` | Some picture widget, in any document, is decoding or shows the label for a claim. Hosts check it first, so a pass with no pictures costs nothing. |
| `PICT-CELL-COPY@` | `( widget -- pic \| 0 )` | The copy CELL shows, for inspection. |
| `PICT-FREE` | `( widget -- )` | Give back everything, the widget included. |

The [media widget](media.md) makes picture widgets for the pictures it
shows; a UIDL `<media>` element is the usual way to get one.
