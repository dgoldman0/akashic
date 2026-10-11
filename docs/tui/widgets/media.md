# akashic/tui/widgets/media.f — Media Widget

**Prefix:** `MEDIA-` (public), `_MEDIA-` (internal)  
**Provider:** `akashic-tui-media`  
**Dependencies:** `widget.f`, `draw.f`, [picture.f](picture.md),
[textarea.f](textarea.md), [media/](../../media/source.md) source,
VFS source and kinds, `memory-source.f`, `string.f`

## Overview

Given a file, the media widget finds what kind of thing it is
([media/kind.f](../../media/kind.md)) and shows it through the matching
view:

| Kind | View |
|---|---|
| QOI, PNG or JPEG picture | A [picture widget](picture.md) |
| Text, HTML | A [text area](textarea.md) holding the whole file |
| Anything else | The file's facts |

Each view is a canonical widget the media widget draws through
`WDG-DRAW-IN`, so CELL shows each one completely and a rich terminal sees
the same canonical widgets it sees anywhere else: in UIDL a `<media>`
element showing text is captured as a `TEXT_AREA`, exactly as a
`<textarea>` is. Focus and keys go to the view shown. HTML shows as its
text for now. CELL decodes QOI pictures and shows a PNG's or JPEG's format
and size; a rich terminal that decodes the file shows the picture.

The facts view says the file's name, its kind and size (for example
`binary data, 7 bytes` or `PNG picture, 12K`), and why it shows only that:

| Note | Message |
|---|---|
| `MEDIA-N-NO-VIEW` | No preview for this kind of file yet |
| `MEDIA-N-MEMORY` | Not enough memory to show this file |
| `MEDIA-N-READ` | The file could not be read |

A file that could not be opened shows only its name and the note.

### Files and memory

The widget owns the file it shows: `MEDIA-OPEN-VFS` opens it, and the next
open, `MEDIA-CLEAR` or `MEDIA-FREE` closes it. A picture keeps its file open
while it shows, since the copy it decodes reads from it; a text file is read
whole and closed at once.

Views and the file's name take memory from the widget's memory source,
each block sized to what it holds: the text area's buffer is the file's
size, so a file is never cut. When that memory refuses the text the widget
shows the facts with `MEDIA-N-MEMORY` instead. `MEDIA-HEAP` is a memory
source on the machine heap with no budget of its own; UIDL gives it to each
`<media>` element.

Picture decoding runs from `MEDIA-SERVICE`, which the UIDL host calls each
pass (`UTUI-SERVICE`), and only once the picture has been drawn.

## API

| Word | Stack | Meaning |
|---|---|---|
| `MEDIA-NEW` | `( rgn msrc -- widget )` | A media widget showing nothing. |
| `MEDIA-OPEN-VFS` | `( path-a path-u vfs widget -- ior )` | Show the file at `path` in `vfs`. A nonzero ior says it could not be opened or read, and the widget says so. |
| `MEDIA-ALT!` | `( alt-a alt-u widget -- )` | A text alternative for pictures in place of the file's name, or `0 0` for the name. The caller keeps the text alive while it is set. |
| `MEDIA-CLEAR` | `( widget -- )` | Show nothing and close the file. |
| `MEDIA-SERVICE` | `( widget -- changed? )` | Decode one slice of a picture being shown. True when what the widget shows changed; the widget is then dirty. |
| `MEDIA-PENDING?` | `( widget -- flag )` | A picture shown is still decoding. |
| `MEDIA-FREE` | `( widget -- )` | Close the file and give back everything, the widget included. |
| `MEDIA-KIND@` | `( widget -- kind )` | `MEDIA-K-*`, or -1 when no file is known. |
| `MEDIA-SIZE@` | `( widget -- bytes )` | The file's size. |
| `MEDIA-NAME@` | `( widget -- a u )` | The file's name, the part of its path after the last slash. |
| `MEDIA-VIEW@` | `( widget -- view )` | `MEDIA-V-NONE`, `-PICTURE`, `-TEXT` or `-FACTS`. |
| `MEDIA-NOTE@` | `( widget -- note )` | Why the facts show: `MEDIA-N-*`. |
| `MEDIA-VIEW-WIDGET@` | `( widget -- view-widget \| 0 )` | The picture widget or text area the current view draws. |
| `MEDIA-PICTURE@`, `MEDIA-TEXT@` | `( widget -- widget \| 0 )` | The picture widget, made on first use, and the current text area. |

## In UIDL

```xml
<media id="preview"/>
<media id="logo"><rep modality="visual" src="/pictures/logo.qoi" text="Logo"/></media>
```

UIDL-TUI makes the widget when the document loads. An app gives an empty
element a file with `S" preview" UTUI-BY-ID UTUI-WIDGET@ MEDIA-OPEN-VFS`
and marks the element dirty. An authored visual `<rep>` with a `src` shows
that file from the current VFS, with the rep's `text` as the pictures' text
alternative. There is no read-only text area yet, so the text view's text
can be edited in place, though nothing writes the file.
