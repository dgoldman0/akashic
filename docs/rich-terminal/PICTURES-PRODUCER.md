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
take adds a 168-byte UPICSN descriptor, one 176-byte static record and its
40-byte correlation, one claim with its residual-planner events, and one
projection rectangle in each target bank. A static is a status field or a
picture, so `MAX-STATICS` is `max-status-native / 72` plus `max-pictures`.
`RTHP-FIRST-CAPACITIES` starts at zero pictures; with a memory source the
arena grows to the pictures a draw shows, half again as other content does.

The pictures the terminal holds are kept apart from the arena, in a table
from the memory source with one 72-byte entry for each resource the owner
holds room for. An upload's pixels are copied into a staging block from the
same source, which goes back when the upload ends. Without a memory source,
or with a terminal that takes no pictures, the producer describes and sends
no picture and every picture stays CELL.

## Each build

Every build describes the pictures its draw shows with `RUHA-PICTURES@`
under the producer's ask: the surface's pixels, once the terminal has
answered, and the terminal's largest picture (`max_image_width`,
`max_image_height`, and `total_resource_bytes` for its bytes). Describing
asks each picture's widget for a copy of that size. A bank too small says
how many pictures there are; the arena grows and the build describes them
again.

A described picture becomes an `IMAGE` static, after the status fields, when
its copy is ready, the terminal holds a resource with the copy's size and
digest, its document is one the frame carries, its whole rectangle lies on
the surface, its paint order fits a claim, and no other root claims any of
its cells. The static fits the resource inside the picture's cells
(`CONTAIN`), opaque, over a backdrop the renderer paints so the CELL picture
beneath never shows through. Its correlation and claim name the document,
the element's source index, generation zero and root key one. Every other
picture stays CELL. The fixed audit counts pictures apart from status fields:
the neutral copy holds a status field's record and text, and the provider
counts what a picture takes.

## The lane

While a frame is live, `RTHP-STEP` runs the picture lane's one job at a time.
The terminal takes no update while a job runs, so `RTHP-PREPARE` waits.

1. On a new surface it asks how many pixels the whole surface has. An answer
   that changes the pixels of a draw with pictures leaves the frame on screen
   stale, so the draw is built again and asks for copies at that size. A
   terminal that cannot answer leaves the pixels unknown, and pictures CELL.
2. It gives back a picture no frame shows, on screen or waiting, and the
   latest build did not describe.
3. When a frame is live, it sends a copy the latest build described as ready
   and the terminal does not hold. The owner must hold room for one more
   resource and its bytes; when it does not, the producer asks the terminal
   for that room and half again, through the same request and answer as a
   frame that needs more space. The table grows to the resources the owner
   holds, the copy is pulled into staging with `RUHA-PICTURE-PULL`, and it is
   sent as the next resource ID. Once the terminal holds it, the frame on
   screen is stale and the draw is built again showing it.

Each target bank records the picture epoch it was built at, which counts
pixel answers and newly held pictures. A frame with an older epoch is not
current. The unchanged-content shortcut is taken only while no picture is in
play, since pictures sit outside the semantic aggregate.

A picture that cannot be sent waits for a newer draw: the terminal refused
room or the upload, Desk's memory had none, or the picture needs more than
the terminal offers at all. `RTHP-FALLBACK@` then reports
`RTHP-PART-PICTURES` with the reason. A picture whose copy changed between
the build and the pull is described again by the draw that changed it.

## Frames that change

A DELTA keeps the statics lane when every picture keeps its place; one that
shows a new resource, or a changed opacity or backdrop, is replaced in place
with `STATIC-REPLACE`. A picture that appears, goes, or moves changes the
lane's shape and takes a complete replacement, as status fields do.
