# Pictures in the screen producer

`hybrid-screen-producer.f` shows the pictures ordinary `<media>` elements
draw as `IMAGE` statics, at the resolution the terminal shows them, while the
same widgets keep drawing them in CELL. Applications do nothing for this:
the [picture widget](../tui/widgets/picture.md) makes a rich copy when asked,
[UPICSN](../tui/uidl-picture-snapshot.md) describes it, and the producer
sends it to the terminal once and shows it.

## Composition and bounds

`RTHP-STORAGE-BYTES` and `RTHP-INIT` take `max-pictures` immediately after
`max-field-native`. Zero selects no picture bank. Each picture the arena can
take adds a 176-byte UPICSN descriptor, one 176-byte static record and its
40-byte correlation, one claim with its residual-planner events, and one
projection rectangle in each target bank. A static is a status field or a
picture, so `MAX-STATICS` is `max-status-native / 72` plus `max-pictures`.
`RTHP-FIRST-CAPACITIES` starts at zero pictures; with a memory source the
arena grows to the pictures a draw shows, half again as other content does.

The pictures the terminal holds are kept apart from the arena, in a table
from the memory source with one 96-byte entry for each resource the owner
holds room for. An entry names its resource, its size and digest, and the
picture it is a copy of: the document, the element and the picture's
revision, which every copy of one picture shares. An upload's pixels are
copied into a staging block from the same source, which goes back when the
upload ends. Without a memory source, or with a terminal that takes no
pictures, the producer sends no picture and every picture stays CELL. A
build then only counts the pictures its draw shows, asking none of them for
a copy, and a draw that shows any records `RTHP-PART-PICTURES` in the
fallback record, with `RTHP-WHY-LIMIT` for a terminal that takes no
pictures or `RTHP-WHY-MEMORY` for no memory source.

## Each build

Every build describes the pictures its draw shows with `RUHA-PICTURES@`
under the producer's ask: the surface's pixels, once the terminal has
answered, and the terminal's largest picture (`max_image_width`,
`max_image_height`, and `total_resource_bytes` for its bytes), within the
room the owner holds once the terminal has refused more (see below).
Describing asks each picture's widget for a copy of that size. A bank too
small says how many pictures there are; the arena grows and the build
describes them again.

A described picture becomes an `IMAGE` static, after the status fields, when
the terminal holds a resource for it, its document is one the frame carries,
its whole rectangle lies on the surface, its paint order fits a claim, and
no other root claims any of its cells. The resource is the picture's own
copy once the terminal holds one with the copy's size and digest. While a
new copy is still on its way, decoding or not yet sent, the newest copy of
the same picture the terminal holds shows instead, so a replacement keeps
the picture on screen as [AKASHIC-RICH-TERMINAL.md](AKASHIC-RICH-TERMINAL.md)
section 5.4 asks. Another picture's copy never shows: a different file
opened in the same element stays CELL until its own copy arrives.

The static fits the resource inside the picture's cells (`CONTAIN`), opaque,
over a backdrop the renderer paints so the CELL picture beneath never shows
through. Its correlation and claim name the document, the element's source
index, generation zero and root key one. Every other picture stays CELL. The
fixed audit counts pictures apart from status fields: the neutral copy holds
a status field's record and text, and the provider counts what a picture
takes.

## The lane

While a frame is live, `RTHP-STEP` runs the picture lane's one job at a time.
Frames go out between an upload's frames, taking turns with them, so an upload
never holds up the screen. `RTHP-PREPARE` waits only while one of the job's
frames awaits its answer, when the engine takes no update, and for the pixel
question and a drop, each one short exchange, so no frame is built at a pixel
size about to change or shows a picture being given back.

1. On a new surface it asks how many pixels the whole surface has. An answer
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
5. When a frame is live, it sends a copy the latest build described as ready
   and the terminal does not hold. The owner must hold room for one more
   resource and its bytes. When it does not, the producer asks the terminal
   for exactly that, through the same request and answer as a frame that
   needs more space, but as the lane's own request. During a replacement the
   old copy still counts, so the ask covers both. The table grows to the
   resources the owner holds, the copy is pulled into staging with
   `RUHA-PICTURE-PULL`, and it is sent as the next resource ID. Once the
   terminal holds it, the frame on screen is stale and the draw is built
   again showing it, after which the old copy goes back by step 3.

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
reports `RTHP-PART-PICTURES` with the reason on every draw. The producer
never crops a picture to fit.

An upload whose picture no longer shows is stopped, so the link carries no
picture that will not be seen. Once a draw, while the upload is queued, the
lane asks `RUHA-PICTURE-SHOWS?` whether the element still shows that
picture's revision, and cancels the upload when another picture or none took
the element, or the document went or is hidden. A stopped upload is simply
forgotten. Once its last frame awaits the terminal it can only finish, and
the picture then goes back like any other no frame wants.

A picture that cannot be sent for any other reason waits for a newer draw:
the terminal refused the upload itself, Desk's memory had none, or the copy
changed between the build and the pull, in which case the draw that changed
it describes it again.

## Frames that change

A DELTA keeps the statics lane when every picture keeps its place; one that
shows a new resource, or a changed opacity or backdrop, is replaced in place
with `STATIC-REPLACE`, which swaps a replaced picture's reference in one
transaction. A picture that appears, goes, or moves changes the lane's shape
and takes a complete replacement, as status fields do.
