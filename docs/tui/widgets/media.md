# akashic/tui/widgets/media.f — Media Widget

**Prefix:** `MEDIA-` (public), `_MEDIA-` (internal)  
**Provider:** `akashic-tui-media`  
**Dependencies:** `widget.f`, `draw.f`, [picture.f](picture.md),
[textarea.f](textarea.md), [document.f](document.md),
[media/](../../media/source.md) source, VFS source, kinds and documents,
[markup/markdown.f](../../markup/markdown.md),
[utils/fs/link-path.f](../../utils/fs/link-path.md), `memory-source.f`,
`string.f`

## Overview

Given a file, the media widget finds what kind of thing it is
([media/kind.f](../../media/kind.md)) and shows it through the matching
view:

| Kind | View |
|---|---|
| QOI, PNG or JPEG picture | A [picture widget](picture.md) |
| A kind the widget has a document reader for: Markdown, and PDF once an owner adds its reader | A [document view](document.md) |
| Text, HTML | A [text area](textarea.md) holding the whole file |
| Anything else | The file's facts |

Each view is a canonical widget the media widget draws through
`WDG-DRAW-IN`, so CELL shows each one completely and a rich terminal sees
the same canonical widgets it sees anywhere else: in UIDL a `<media>`
element showing text is captured as a `TEXT_AREA`, exactly as a
`<textarea>` is. Focus and keys go to the view shown. HTML shows as its
text for now. CELL decodes QOI and PNG pictures and shows a JPEG's format
and size; a rich terminal that decodes the file shows the picture.

The facts view says the file's name, its kind and size (for example
`binary data, 7 bytes` or `PNG picture, 12K`), and why it shows only that:

| Note | Message |
|---|---|
| `MEDIA-N-NO-VIEW` | No preview for this kind of file yet |
| `MEDIA-N-MEMORY` | Not enough memory to show this file |
| `MEDIA-N-READ` | The file could not be read |
| `MEDIA-N-LOCKED` | The file is protected by a password |

A file that could not be opened shows only its name and the note.

### Files and memory

The widget owns the file it shows: `MEDIA-OPEN-VFS` opens it, and the next
open, `MEDIA-CLEAR` or `MEDIA-FREE` closes it. A picture keeps its file open
while it shows, since the copy it decodes reads from it, and so does a
document, whose view reads a block's text only when it reaches the block; a
text file is read whole and closed at once.

Views, the document and the file's path take memory from the widget's
memory source, each block sized to what it holds: the text area's buffer is
the file's size, so a file is never cut. When that memory refuses the text
or the document the widget shows the facts with `MEDIA-N-MEMORY` instead.

### Documents

The widget keeps a document reader for each kind
([media/document.f](../../media/document.md)). It starts with Markdown's
(`markup/markdown.f`), and an owner adds others with `MEDIA-READER!`. File
Explorer adds [pdf/document.f](../../pdf/document.md)'s for PDFs before it
opens a preview, so the PDF reader is loaded only by applications that show
PDFs, not by every application with a `<media>` element. A file of a kind
with no reader shows as its kind otherwise shows: a PDF without its reader
shows its facts. A document whose reader says it needs a password
(`DOC-S-LOCKED`) shows its facts with `MEDIA-N-LOCKED`.

A document's contents ([media/document.f](../../media/document.md)) show
in place of the document: the key `c` shows them as a canonical
[list](list.md), each entry's title indented two cells a level, and the
first selected. Enter goes where the chosen entry goes in the document, as
`DOCV-GO-ENTRY` does, and shows the document; `c` or Escape shows the
document again where it was. A document with no contents ignores `c`. The
contents take the same region as the document, so a narrow preview loses
nothing to them, and the view in use is `MEDIA-V-CONTENTS`. A rich
terminal sees the contents as the list's CELL cells for now; the media
element's capture publishes its text and document views.

A Markdown document's figures and links name files by paths from the
document's folder, resolved as [link-path.f](../../utils/fs/link-path.md)
resolves them. A figure's picture is opened from the same file system, and
one that cannot be opened shows its name. A link to one of the document's
own headings scrolls the view. Any other link goes to the owner's follow
word, set with `MEDIA-FOLLOW!`, as the path it names with `LPATH-S-OK`, or
with no path and the `LPATH-` status that says why it names none: a scheme
such as `https:`, no path at all, or one too long. File Explorer selects
the file a link names, in its folder, and previews it. `MEDIA-HEAP` is a memory
source on the machine heap with no budget of its own; UIDL gives it to each
`<media>` element.

Picture decoding, for a picture or a document's figures, runs from
`MEDIA-SERVICE`, which the UIDL host calls each pass (`UTUI-SERVICE`), and
only once the picture has been drawn.

## API

| Word | Stack | Meaning |
|---|---|---|
| `MEDIA-NEW` | `( rgn msrc -- widget )` | A media widget showing nothing. |
| `MEDIA-OPEN-VFS` | `( path-a path-u vfs widget -- ior )` | Show the file at `path` in `vfs`. A nonzero ior says it could not be opened or read, and the widget says so. |
| `MEDIA-ALT!` | `( alt-a alt-u widget -- )` | A text alternative for pictures in place of the file's name, or `0 0` for the name. The caller keeps the text alive while it is set. |
| `MEDIA-CLEAR` | `( widget -- )` | Show nothing and close the file. |
| `MEDIA-READER!` | `( reader kind widget -- )` | Show files of `kind` as documents `reader` reads, or for 0 as the kind otherwise shows; from the next open. |
| `MEDIA-FOLLOW!` | `( follow-xt ctx widget -- )` | Where a document's links to files go: `( path-a path-u status ctx -- )`. The path stays valid only while the word runs. Zero follows no such link. |
| `MEDIA-SERVICE` | `( widget -- changed? )` | Decode one slice of a picture being shown, or of a document's figure. True when what the widget shows changed; the widget is then dirty. |
| `MEDIA-PENDING?` | `( widget -- flag )` | A picture shown, or a document's figure, is still decoding. |
| `MEDIA-FREE` | `( widget -- )` | Close the file and give back everything, the widget included. |
| `MEDIA-KIND@` | `( widget -- kind )` | `MEDIA-K-*`, or -1 when no file is known. |
| `MEDIA-SIZE@` | `( widget -- bytes )` | The file's size. |
| `MEDIA-PATH@` | `( widget -- a u )` | The path the file was opened by. |
| `MEDIA-NAME@` | `( widget -- a u )` | The file's name, the part of its path after the last slash. |
| `MEDIA-VIEW@` | `( widget -- view )` | `MEDIA-V-NONE`, `-PICTURE`, `-TEXT`, `-FACTS`, `-DOCUMENT` or `-CONTENTS`. |
| `MEDIA-NOTE@` | `( widget -- note )` | Why the facts show: `MEDIA-N-*`. |
| `MEDIA-VIEW-WIDGET@` | `( widget -- view-widget \| 0 )` | The picture widget, text area or document view the current view draws. |
| `MEDIA-PICTURE@`, `MEDIA-TEXT@`, `MEDIA-DOCUMENT@`, `MEDIA-CONTENTS@` | `( widget -- widget \| 0 )` | The picture widget, the document view and the contents' list, each made on first use, and the current text area. |

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
