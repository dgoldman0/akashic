# Pictures in the screen producer

`hybrid-screen-producer.f` shows the pictures ordinary `<media>` elements
draw, their own or the figures of a document they show, as `IMAGE` statics,
at the resolution the terminal shows them, while the same widgets keep
drawing them in CELL. Applications do nothing for this:
[UPICSN](../tui/uidl-picture-snapshot.md) describes each picture as its
file, when the terminal decodes the file's format, or as a rich copy the
[picture widget](../tui/widgets/picture.md) makes when asked, and the
producer sends it to the terminal once and shows it. While the rich side
takes a picture, its CELL view shows only what the picture is.

## Composition and bounds

`RTHP-STORAGE-BYTES` and `RTHP-INIT` take `max-pictures` immediately after
`max-dialog-native`. Zero selects no picture bank. Each picture the arena can
take adds a 192-byte UPICSN descriptor, one 208-byte static record and its
40-byte correlation, one claim with its residual-planner events, which a
figure leaves unused, and that claim kept whole in each target bank. A static is a status field or a
picture, so `MAX-STATICS` is `max-status-native / 72` plus `max-pictures`.
`RTHP-FIRST-CAPACITIES` starts at zero pictures; with a memory source the
arena grows to the pictures a draw shows, half again as other content does.

The pictures the terminal holds are kept apart from the arena, in a table
from the memory source with one 80-byte entry for each resource the owner
holds room for. An entry names its resource, its size, the bytes the owner
holds for it decoded, the format it was sent in, and the picture it is a
copy of: the document, the element, the root key, which tells an element's
figures apart, and the picture's revision, which every copy of one picture
shares. An upload reads its bytes a chunk at a time into
one block from the same source, the size of its largest chunk, which goes
back when the upload ends; the lane never holds a whole picture.

Without a memory source, or with a terminal that takes no pictures, the
producer sends no picture and every picture stays CELL. A build then only
counts the pictures its draw shows, asking none of them for a copy, and a
draw that shows any records `RTHP-PART-PICTURES` in the fallback record,
with `RTHP-WHY-LIMIT` for a terminal that takes no pictures or
`RTHP-WHY-MEMORY` for no memory source.

## Each build

Every build describes the pictures its draw shows with `RUHA-PICTURES@`
under the producer's ask: the picture files the terminal decodes
(`image_formats`), the surface's pixels, once the terminal has answered, and
the terminal's largest picture (`max_image_width`, `max_image_height`, and
`total_resource_bytes` for its bytes, decoded), within the room the owner
holds once the terminal has refused more (see below). A picture whose file
the terminal decodes, within those bounds, is described as that file at its
own size. Describing asks every other picture's widget for a copy of the
pixels its rectangle covers. A bank too small says how many pictures there
are; the arena grows and the build describes them again.

The ask also says the rich side takes the pictures it describes, so their
CELL views show the picture's name, format and size and decode nothing
([claims](../tui/uidl-picture-snapshot.md#claims)). Once the lane fails to
send a picture, it stops saying so until it starts sending one, or a build
describes none, and lets every claim go. Every claim goes too whenever the
producer shows no picture: an empty frame, a fault, the lane switched off,
or the producer's end. CELL then shows each picture, decoding a CELL copy
where it needs one.

A described picture becomes an `IMAGE` static, after the status fields, when
the terminal holds a resource for it, its document is one the frame carries,
the part of it shown lies on the surface, and its paint order fits a claim.
The static is the picture's whole rectangle, which may reach off the
surface, with the part shown as its clip when that is not all of it, so a
picture partly scrolled out shows that part at its whole size. An element's
own picture claims the part shown, which no other root may claim. A figure
takes no claim: the part shown must lie inside the claim of its own
document's root, the DOCUMENT control drawn over it. That control leaves
the figure's rows unpainted, and at one paint order the terminal paints
objects before controls, so the picture shows through.

The resource is the picture's own copy once the terminal holds one with the
copy's size and format. While a new copy is still on its way, decoding or
not yet sent, the newest copy of the same picture the terminal holds shows
instead, so a replacement keeps the picture on screen as
[AKASHIC-RICH-TERMINAL.md](AKASHIC-RICH-TERMINAL.md) section 5.4 asks.
Another picture's copy never shows: a different file opened in the same
element stays CELL until its own copy arrives.

The static fits the resource inside the picture's cells (`CONTAIN`), opaque,
over a backdrop the renderer paints so the CELL view beneath, the picture or
what it is, never shows through. Its correlation names the document, the
element's source index, generation zero and its root key, one for an
element's own picture and a figure's block key; an element's own picture's
claim names the document and the element. Every other picture stays CELL. The fixed audit
counts pictures apart from status fields: the neutral copy holds a status
field's record and text, and the provider counts what a picture takes. It
finds each figure inside its document's claim, and every other static
holding the next claim, exactly the part of it shown.

## The lane

While a frame is live, `RTHP-STEP` runs the picture lane's one job at a time.
Frames go out between an upload's frames, taking turns with them, so an upload
never holds up the screen. `RTHP-PREPARE` waits only while one of the job's
frames awaits its answer, when the engine takes no update, and for the pixel
question and a drop, each one short exchange, so no frame is built at a pixel
size about to change or shows a picture being given back.

1. On a new surface, when a described picture needs a copy made, it asks
   how many pixels the whole surface has. An answer
   that changes the pixels of a draw with pictures leaves the frame on screen
   stale, so the draw is built again and asks for copies at that size. A
   terminal that cannot answer leaves the pixels unknown, and pictures CELL.
2. While the frame on screen was built before the latest such change, the
   lane waits for the frame built again.
3. It gives back a picture no frame shows, on screen or waiting, and the
   latest build did not describe.
4. Once no described picture is on its way, it gives back the room no
   picture uses: the owner keeps exactly the resources its pictures take and
   their bytes. A terminal that keeps the room anyway is not asked again
   until another picture goes.
5. When a frame is live, it sends a file or copy the latest build described
   as ready and the terminal does not hold. The owner must hold room for one
   more resource and its decoded bytes. When it does not, the producer asks
   the terminal for exactly that, through the same request and answer as a
   frame that needs more space, but as the lane's own request. During a
   replacement the old copy still counts, so the ask covers both. The table
   grows to the resources the owner holds, and the file or copy is sent as
   the next resource ID in its format: a file as it is, for the terminal to
   decode, and a copy as RGBA8 pixels. Nothing is read yet. Each time the
   upload wants its next chunk (`RTE-RESOURCE-WANTS@`), the lane reads that
   span with `RUHA-PICTURE-PULL` into its block, which it takes from the
   memory source at the first chunk, and hands it over with
   `RTE-RESOURCE-FEED`. Once the terminal holds the picture, the frame on
   screen is stale and the draw is built again showing it, after which the
   old copy goes back by step 3.

Each target bank records the picture epoch it was built at, which counts
pixel answers, newly held pictures and changes in the room copies keep
within. A frame with an older epoch is not current. The unchanged-content
shortcut is taken only while no picture is in play, since pictures sit
outside the semantic aggregate.

## Refusals and failures

When the terminal refuses the lane more room, or the room would be more than
the terminal offers at all, the producer records why in its own field, so a
refused picture never keeps a frame from growing. It asks for no more room
until a build describes no picture. A smaller copy is still the whole
picture: when the owner holds a free resource and some bytes no picture
uses, every picture is described again within those bytes and the smaller
copy goes into the room already held. When the owner holds no such room, the
picture keeps what it shows, an older copy or CELL, and `RTHP-FALLBACK@`
reports `RTHP-PART-PICTURES` with the reason on every draw. The lane has
failed then, so CELL shows every picture, as above. The producer never crops
a picture to fit.

An upload whose picture no longer shows is stopped, so the link carries no
picture that will not be seen. While the upload waits to send a frame or
wants a chunk, the lane cancels it once the latest build no longer describes
its picture at that size and in that format: another picture or none took the
element, its copy changed size, or the document went or is hidden. Each
chunk's read checks the element itself too, and a read that finds the
picture no longer showing that file or copy cancels the upload and starts
nothing more in that draw, since the draw that changed the picture describes
it again. A stopped upload is simply forgotten. Once its last frame awaits
the terminal it can only finish, and the picture then goes back like any
other no frame wants.

A picture whose bytes the terminal refuses as no picture of their size
(`RTE-S-SOURCE`) is the picture's own failure, not the lane's. The lane has
its widget remember it with `RUHA-PICTURE-FAIL`, so CELL shows it and says
the picture is damaged, and the frame built again describes it as failed;
the lane waits for that frame, so it never sends the picture again until the
widget is given another source. A chunk whose file cannot be read is
remembered the same way by the read itself. The other pictures stay rich.

A picture that cannot be sent for any other reason waits for a newer draw:
the terminal refused the upload itself, or Desk's memory had no room for
the table or the chunk block. These are failures,
after which CELL shows every picture until the lane starts sending one. A
picture the terminal will not give back is no failure: the rich side still
shows its pictures.

## Frames that change

A DELTA keeps the statics lane when every picture keeps its place; one that
shows a new resource, or a changed opacity or backdrop, is replaced in place
with `STATIC-REPLACE`, which swaps a replaced picture's reference in one
transaction. A picture that appears, goes, or moves changes the lane's shape
and takes a complete replacement, as status fields do. A picture shown
through another clip has moved too.
