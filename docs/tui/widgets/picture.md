# akashic/tui/widgets/picture.f — Picture Widget

**Prefix:** `PICT-` (public), `_PICT-` (internal)  
**Provider:** `akashic-tui-picture`  
**Dependencies:** `widget.f`, `draw.f`, `color.f`,
[media/picture.f](../../media/picture.md), `memory-source.f`

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
places cells. A rich terminal shows the same picture at its own resolution
from the same source.

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
never waits. A widget that is never drawn never decodes. A new size, from a
resize, starts a new copy.

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
| `PICT-SOURCE!` | `( source alt-a alt-u widget -- )` | Show the picture in `source`, with `alt` as its text alternative; a zero source shows nothing. Gives back the old copy. |
| `PICT-ALT!` | `( alt-a alt-u widget -- )` | Change the text alternative alone. |
| `PICT-SERVICE` | `( budget widget -- changed? )` | Decode about `budget` source pixels of the copy, at least one row. True when the copy just finished or failed, so what the widget shows changed; the widget is then dirty. |
| `PICT-STEP-PIXELS` | `( -- n )` | The budget the UIDL host gives a widget each pass (16,384). |
| `PICT-PENDING?` | `( widget -- flag )` | This widget's copy is decoding. |
| `PICT-WORK?` | `( -- flag )` | Some picture widget, in any document, is decoding. Hosts check it first, so a pass with no pictures costs nothing. |
| `PICT-CELL-COPY@` | `( widget -- pic \| 0 )` | The copy CELL shows, for inspection. |
| `PICT-FREE` | `( widget -- )` | Give back everything, the widget included. |

The [media widget](media.md) makes picture widgets for the pictures it
shows; a UIDL `<media>` element is the usual way to get one.
