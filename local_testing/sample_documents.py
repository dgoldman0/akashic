"""The Desktop's sample documents: the notes and lists a person keeps.

A Desktop image, Desk with Pad and File Explorer, carries these beside the
other samples (akashic_tui._sample_files).  Each is a short plain text or
Markdown file that Pad opens and File Explorer previews, the Markdown ones
as documents.  None holds a date or a link, so an image's copy is the same
on every day and no preview leads to a file that is absent.

They also make the Desktop's root folder a list worth scrolling.  File
Explorer sorts its detail table by name, and on the canonical Desktop the
table shows DESKTOP_TABLE_ROWS rows.  The physical journey's wheel step
(rich_terminal_desktop_acceptance.py) turns the wheel one detent over that
table, so the root must list at least one detent more than the table shows,
with the journey's pointer file shown before and after the turn.  The root's
own files meet that with a detent to spare on either side: the files the
image is built with, without the source chunks a linked profile adds and
without the files Desk and its applets create as they start
(test_akashic_tui_packaging.py checks it).

Desk with a single applet carries none of them.  The checks of File
Explorer alone find each row and each folder in the first view of its table
and of its tree, and with these files beside a linked image's source chunks
that root would no longer fit either view.
"""

from __future__ import annotations

# The rows File Explorer's detail table shows on the canonical Desktop, at
# the rich terminal's 280 by 84 cells: the journey's own count of the rows in
# view there.
DESKTOP_TABLE_ROWS = 35

_DOCUMENTS = {
    "birdwatching.md": """\
# Birds at the pond

Seen from the bench by the reeds, early in the morning.

- two herons standing in the shallows
- a kingfisher on the dead branch
- swallows low over the water before rain

Bring the small binoculars next time.
""",
    "book-notes.md": """\
# Notes on the lighthouse novel

The keeper counts ships to stay awake. *Nothing happens* for a hundred
pages, and it is the best part.

## A line worth keeping

> The lamp does not ask who is out there.

## To look up

- how the lens was turned before electricity
""",
    "bread-recipe.md": """\
# Plain loaf

- 500 g flour
- 350 g water
- 10 g salt
- a pinch of yeast

1. Mix and leave overnight.
2. Fold twice in the morning.
3. Bake hot in a covered pot, then uncovered until dark.
""",
    "chores.txt": """\
Chores this week

sweep the stairs
water the plants on the landing
take the glass to the container
oil the gate hinge
air the blankets
""",
    "errands.txt": """\
Errands

post office: stamps, and the parcel
key cutter: one copy of the shed key
library: return the atlas
shoe repair: collect the boots
""",
    "garden-plan.md": """\
# Garden plan

## Beds

1. Beans along the fence.
2. Lettuce where the shade falls at noon.
3. Herbs by the kitchen door.

## To do

- turn the compost
- mend the hose
- label the seed trays
""",
    "gift-ideas.txt": """\
Gift ideas

a pocket notebook with squared paper
wool socks
a jar of the dark honey
a small brass compass
seeds for the balcony
""",
    "haiku.txt": """\
Kettle starts to sing
before the window brightens
steam on the cold glass

One leaf on the step
the broom leans against the wall
both of us waiting
""",
    "ideas.md": """\
# Ideas

- A clock that shows only the next thing to do.
- A map of the neighbourhood drawn from memory, then checked on foot.
- Letters to read in ten years.

*Pick one and start small.*
""",
    "kitchen-inventory.txt": """\
Kitchen inventory

rice        2 bags
lentils     1 jar
oats        half a bag
olive oil   1 bottle
tea         plenty
salt        low
""",
    "letter-draft.txt": """\
Dear neighbour,

Thank you for watering the tomatoes while we were away. They have
doubled, and the first ones are nearly red. Come by on Sunday and take
a basket home.

With thanks from the house with the green door
""",
    "meeting-notes.md": """\
# Allotment committee

## Agreed

- The shared shed gets a new lock.
- The water is turned off at the first frost.

## Open

- Who keeps the spare key?
- A day for the autumn clean-up.
""",
    "morning-routine.md": """\
# Morning

1. Open the window.
2. Drink a glass of water.
3. Stretch for ten minutes.
4. Write three lines before reading anything.

**No screens before breakfast.**
""",
    "music-practice.md": """\
# Practice plan

- scales, slowly, both hands
- the difficult bar, ten times without the pedal
- one piece for pleasure

Stop while it still sounds good.
""",
    "packing-list.txt": """\
Packing list

rain jacket
walking boots
two pairs of socks a day
water bottle
map and pencil
torch with spare batteries
first aid kit
""",
    "plant-care.md": """\
# Plant care

- **Fern**: water twice a week, keep in shade.
- **Basil**: water every day, full sun.
- **Cactus**: water once a month, full sun.

Turn the pots a quarter each week.
""",
    "reading-list.md": """\
# To read

- a history of lighthouses
- the long novel about the river
- anything on how bridges are built

## Finished

- the field guide to mosses
""",
    "repair-log.md": """\
# Bicycle repairs

- Front tyre patched; the thorn was still in it.
- Chain cleaned and oiled.
- Rear brake cable replaced.

Next: true the back wheel.
""",
    "shopping-list.txt": """\
Shopping

bread
apples
onions
butter
candles
string
""",
    "soup-recipe.md": """\
# Lentil soup

- one onion, two carrots, a stick of celery
- a cup of red lentils
- a litre of stock

Soften the vegetables, add the lentils and the stock, and simmer for
twenty minutes. Finish with lemon.
""",
    "study-plan.md": """\
# Study plan

## This month

1. Read one chapter a day.
2. Work the exercises on paper.
3. Explain each idea aloud to an empty chair.

## Later

- past papers, timed
""",
    "thoughts.txt": """\
Thoughts

A tidy desk is a promise to tomorrow.
Mend it while it is small.
Write it down before it is perfect.
Leave the path better than you found it.
""",
    "travel-notes.md": """\
# The coast path

*Three days, north to south.*

- The first day is all cliffs and wind.
- Fill both bottles at the harbour; there is no water after it.
- The ferry runs only at high tide.

Take the inland track if the fog comes down.
""",
    "walk-routes.md": """\
# Walks from the front door

1. **The short loop**: round the pond and back, half an hour.
2. **The hill**: up past the orchard, an hour and a half.
3. **The long way**: along the canal to the lock, home by the lane.
""",
}

# Name to content, as an image carries them.
SAMPLES = {name: text.encode("ascii") for name, text in _DOCUMENTS.items()}
