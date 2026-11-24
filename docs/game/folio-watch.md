# Folio Watch — visual design

Status: Proposed, 2026-11-23. Nothing in this document is accepted or built.
Section 10 lists the choices it asks the author to make.

This document will hold Folio Watch's design, as section 3.1 of the
[plan](GAME-LIBRARY-PLAN.md) provides. This first part proposes how the game
looks. The rules, the creatures and the balance runs' numbers follow in
stage 5.

## 1. The look

Stage 4's skeleton draws the reading room as plain glyphs: shelves as `▒▒`,
floor as `·`, the archivist as `@`. Every lit tile looks alike, however near
the lamp, and a remembered tile differs from a lit one only by being dimmed.
The game's premise is a dark archive in which a hand lamp and a few wall
lamps make pools of warm light, and every decision the player makes turns on
where that light falls.

The proposal therefore makes light the first thing a player sees. Lit tiles
glow warm, brightest at the lamp and fading toward the edge of its reach.
Tiles the archivist remembers but cannot see turn cool and dim. Inkmites and
threatened folios stand out in alarm colours, and a guttering lamp
flickers. Each tile becomes a small two-cell picture, the board grows to fill
its pane, and each inkmite's tile shows its mood and its heading.

## 2. The rules it keeps

Every effect comes from a general feature of the canonical text grid that any
applet could use. The game gains no drawing API. It still builds one `TGRID`
model through `game/board.f` and its token word, and it chooses meanings,
never colours, sizes or animation. CELL shows everything the rich renderer
shows, by its own means: colour ramps from the 256-colour palette, the DIM
and BLINK attributes, centred text. The renderer owns representation: it
takes each colour from its theme, sizes the glyphs, and decides whether and
how anything moves. The wire carries meanings, as STX1's style runs already
do: "a renderer's theme chooses how each meaning looks; the wire carries no
colour, font, or size" (`rich_terminal/semantic_content.py`).

Three additions to the text grid carry the design. Each item gains a tone
and an intensity (section 3) and an unsteady mark (section 4), and a content
flag declares a grid's items tiles of one picture (section 5). They belong
to the canonical widget below the applet layer, and Grid and Daybook have
ordinary uses for them. Everything else is the game's own content:
its tile texts and the meanings it assigns.

## 3. Light and colour: tone and intensity

### 3.1 Meaning and wire form

An item's **tone** says what kind of attention its content draws, and its
**intensity** says how strongly, on four steps from 0 to 3.

| Tone | Value | Means |
|---|---:|---|
| NEUTRAL | 0 | No particular kind; intensity alone shades it, as in a heat map |
| WARM | 1 | Lit, active or current: lamp light, today, a busy day |
| COOL | 2 | Remembered, past or at rest: what the archivist saw earlier, last week |
| ALERT | 3 | Needs attention: a creature, a threatened folio, an overdue item, a negative figure |
| GOOD | 4 | Settled well: a finished task, a positive total |

At intensity 0 a tone touches the item lightly, and intensity 3 is its
strongest. NEUTRAL at intensity 0 is the item as it looks today, so every
existing grid keeps its look.

The STX1 item header has no free field, but its 16-bit state word uses only
bits 0 and 1, CURRENT and UNAVAILABLE, and both validators refuse every
other bit today (the host's `SEMANTIC_TEXT_STATE_MASK`, the guest's
`_USCOL-ITEM-STATE-MASK`). The proposal assigns:

| Bits | Field |
|---|---|
| 2–3 | Intensity, 0 to 3 |
| 4–6 | Tone, 0 to 4; 5 to 7 stay refused |
| 7 | Unsteady (section 4) |
| 8–15 | Reserved, refused as now |

The native item's state cell (`USCOL-ITEM-STATE-OFFSET`) takes the same
bits. They are admitted for `TEXT_GRID` items only; `TEXT_AREA` rows stay
state zero. The layout, the sizes and the cost of validation stay as they
are, since each validator widens one mask.

### 3.2 How the renderers show it

The rich renderer's theme gives each tone a family of four background tints
and a text colour that reads on them, and intensity picks the step. In the
reference appearance the tint fills the item's rectangle under its text; in
the flowing appearance it colours the item's channel, a glow inside its
rounded rectangle. The existing marks keep their precedence: the primary
item's selection fill, CURRENT's accent border, and UNAVAILABLE's dimming,
which applies on top of the tint, so a remembered tile is cool and dim at
once.

CELL needs ramps chosen by hand. The 256-colour palette's nearest matches
for the rich theme's dark tints are greys, which would lose the hue. At
intensity 0 only the text takes the tone's colour; from 1 to 3 the
background takes it, and the text takes a colour that reads on it:

| Tone | 0: text | 1: background / text | 2 | 3 |
|---|---|---|---|---|
| WARM | 137 | 94 / 223 | 136 / 16 | 178 / 16 |
| COOL | 60 | 17 / 67 | 24 / 153 | 31 / 16 |
| ALERT | 167 | 52 / 217 | 88 / 224 | 124 / 231 |
| GOOD | 108 | 22 / 151 | 28 / 194 | 34 / 16 |
| NEUTRAL | as today | 236 / 252 | 238 / 254 | 241 / 231 |

`TGRID`'s CELL draw (`_TGRID-DRAW-STYLE`) already gives typed values their
colours (numbers 81, formulas 42, errors 203), the primary item REVERSE,
CURRENT an underline and UNAVAILABLE the DIM attribute. A tone other than
NEUTRAL sets the text colour in place of the role's; the attributes stay as
they are, and the primary item's REVERSE still wins.

### 3.3 What Grid and Daybook would use it for

Grid could shade a column by value, NEUTRAL from intensity 0 to 3, as a heat
map. It could show a negative figure ALERT at intensity 0, so that only its
text turns red, and mark a total GOOD. Daybook's month could warm each day by
the number of its events, one, two, or three and more, show past days COOL at
intensity 0, and mark a day with an overdue reminder ALERT, while today stays
CURRENT. Neither changes until it opts in.

### 3.4 How Folio Watch lights the room

The game gives each visible tile WARM at an intensity set by its distance
from the nearest light: 3 within 1.5 tiles, 2 within 2.5, and 1 out to the
light's radius. On a ring one tile past that reach the light fades into the
dark: the archivist sees those tiles faintly, at intensity 0, but the
inkmites do not count them as light. A guttering lamp reaches at most
intensity 2. A tile the archivist remembers but no light reaches is COOL at
intensity 0 and UNAVAILABLE, so it shows cool and dim; a tile never seen
stays blank and UNAVAILABLE, as now. The archivist's tile is WARM 3 and
CURRENT. A folio on a lit desk takes its tile's light, and a folio that an
inkmite is eating is ALERT 3 and unsteady wherever it is remembered.

The hand lamp's intensities need only each tile's distance from the
archivist, for the tiles the turn's reveal already lights, with the reveal
reaching one tile further for the faint ring. The wall lamps' pools stay in
a fog layer of their own, recomputed only on the turns a lamp is lit,
refilled or gutters, as section 3.1 of the plan already sets.

## 4. Motion: the unsteady mark

Bit 7 of an item's state marks its emphasis **unsteady**: its light, or its
claim on attention, wavers. A renderer that animates moves the item's
intensity one step up or down at irregular moments, a few times a second; a
renderer that does not shows it steady. In the game a guttering lamp and a
folio being eaten are unsteady. Daybook could mark an overdue reminder so,
and Grid a cell whose formula refers to itself.

The motion belongs to the renderer and costs the guest nothing: no frame
goes out while a lamp flickers. The rich viewer recomposes the regions that
hold unsteady items on its own timer and holds them still under a
reduced-motion setting. CELL draws an unsteady item with the BLINK
attribute, which a terminal shows as its own blink or ignores.

Dawn needs nothing new. Over the night's last turns the game raises every
visible tile's intensity a step at a time as the room fills with morning.

## 5. The board filling its pane

At 132 by 38 Desk gives the game a pane of 34 by 132 cells, and at 280 by 84
one of 80 by 280; the 12 by 48 cell board sits small in the middle of
either. Both renderers already stretch a text grid's viewport across its
widget: `TGRID`'s CELL draw and the rich renderer's `_paint_text_grid` each
divide the region among the viewport's rows and columns. The board today
declares the whole region as its viewport and centres the map inside it. If
`game/board.f` declared the map's window as the viewport instead, keeping
the root equal to the region as `TGRID-BIND` requires, each tile would grow
to about 5.5 by 2.8 cells at 132 by 38 and 11.7 by 6.7 at 280 by 84. That
change stays inside the game library.

Grown tiles still draw like a spreadsheet's cells. The rich renderer frames
each item with a border and padding and writes its text at the font's size
against the item's left edge, and CELL writes the text on the first row of
the item's rectangle. A new content flag, **TILES** (bit 3 of the STX1 content
flags, beside READ_ONLY and the two direction bits), says that the grid's
items are tiles of one picture. Under it the rich renderer draws the items
edge to edge without borders or padding and centres each item's text,
scaled to fill the item. CELL centres the text in the item's rectangle and
fills the rectangle with the item's tone. A tile's text then needs no
padding space: the archivist is `@`, not `@ `. Daybook's month could use
TILES for a wall calendar with large dates, and Valley Relay and Garden
Automata would use it as this game does.

## 6. Tile art

Each tile is two cells. Every glyph below is in DejaVu Sans Mono, the face
Akashic's journeys and the play command give the viewer, and takes one cell
under the shared text rules. The check behind that ran
`rich_terminal.text_rules.string_width` and each face's character map, over
the viewer's font chain of DejaVu Sans Mono and then the Noto faces
fontconfig finds, for every candidate glyph. It dropped the candidates the
primary face lacks (`⁘ ⦀ ⫼ ※ ⁂`). Many of the glyphs kept have the
Unicode East Asian width "ambiguous": the project's rules give them one
cell, as the skeleton's `▒` and `·` already show, but an outside terminal
set for a CJK locale may draw them two cells wide.

| Tile | Glyphs | Code points | Notes |
|---|---|---|---|
| Floor | `·` | U+00B7 | as now |
| Rug | `░░` | U+2591 | a woven texture that warm light turns into carpet |
| Shelf | `▮▯`, `▯▮`, `▮▮` | U+25AE, U+25AF | book spines; the pattern follows the tile's position, so a run of shelves reads as books of different bindings |
| Desk | `╤╤` | U+2564 | a table on legs |
| Desk with a folio | `╤▤` | U+2564, U+25A4 | a page of text lying on the desk |
| Folio being eaten | `╤▦` | U+25A6 | the page crosshatched; ALERT 3, unsteady |
| Wall lamp, full | `☼☼` | U+263C | two flames |
| Wall lamp, guttering | `☼∘` | U+263C, U+2218 | one flame out; unsteady |
| Wall lamp, out | `∘∘` | U+2218 | |
| Nest | `∴∵` | U+2234, U+2235 | dark holes where inkmites stir |
| Archivist | `@` | U+0040 | CURRENT; `@▤` while carrying a folio |
| Inkmite | `ж` or `Ж`, and an arrow | U+0436, U+0416, U+2190–U+2199, U+21D0–U+21D9 | section 7 |

## 7. Inkmites: mood and heading

The fun rules ask that a player read each inkmite at a glance: where it is
going, and what it will do next. An inkmite's tile carries both in its two
cells. The first is the creature, a small `ж` while it moves and a capital
`Ж` while it feeds; the second is an arrow toward where it is going, single
while it creeps and double while it flees.

| Mood | Tile | Tone and intensity | Reads as |
|---|---|---|---|
| Lurking | `ж` | COOL 1 | still, waiting in the dark |
| Creeping | `ж` and a single arrow, such as `ж↘` | ALERT 1 | moving toward the folio the arrow points at |
| Feeding | `Ж` and an arrow at the folio, such as `Ж↑` | ALERT 1, unsteady; the folio ALERT 3, unsteady | eating, and the folio's tile flickers with it |
| Scattering | `ж` and a double arrow, such as `ж⇘` | the light where it stands | caught by light and fleeing that way |

Inkmites live in the dark and flee the moment light reaches them, so a
lurking, creeping or feeding inkmite never stands on a lit tile, and under
stage 4's rule, which shows what stands on lit tiles only, the board would
rarely show one. Two rules for stage 5, which its balance runs would test,
close that gap. An inkmite on the faint ring one tile past a light's reach
shows as a silhouette, at intensity 1 in its mood's tone, as the table
gives. A feeding inkmite also marks its folio's remembered tile ALERT and
unsteady, wherever it is, as if the archivist heard it scratching. A lost
folio then never comes as a surprise, since its tile flickered first.

## 8. The reading room, mocked up

It is turn 14 of a night. The archivist stands on the west side of the rug
with the hand lamp, radius 4. The north-west and south-east wall lamps burn
full, the north-east lamp gutters, and the south-west lamp is out. One
inkmite feeds on the folio on the north-east desk from the dark just past the
guttering lamp's reach, a second creeps toward the folio on the east desk,
and a third, caught by the hand lamp south-east of the archivist, flees
south-east. This is CELL at one cell per glyph, as a small pane draws it
without the TILES flag, with the light stopped by shelves:

```
          ▮▮☼☼▯▮                ▯▮☼∘▮▯
          · · · ·   · · ·       · · ·
      ▮▯▯▮▮▮· · ╤╤╤▤╤╤· · · · ╤╤╤▦╤╤· · ▮▮
        ▯▮▮▮· · · · · · · · · · Ж↑· · ж↘
        · · · ░░░░░░░░░░░░░░░░░░  ·
        ╤▤╤╤· · ░░░░░░░░· ░░░░░░░░
      · · · · ░░@ ░░░░░░░░░░░░░░  ·
        · · · · · · · · · · · · · · · · ·
          ▮▮· · ╤╤╤▤╤╤ж⇘· · · ╤╤╤▤╤╤· · ▮▮
          ▮▮· · · · · · · · · · · · · · ▮▮▮▯
          · · · · · · ·       · · · · ·
                ▮▮              ▯▮☼☼▮▯
```

The same tiles' tone and intensity, with W for WARM, C for COOL and A for
ALERT, written in lower case where the tile is unsteady:

```
          W3W3W3                W2w2W2
          W3W3W3W0  C0C0C0      W2W2W2
      W1W1W2W2W2W1W1W0W0C0C0W0W1a3W2W2W1W0
        W0W0W1W1W1W1W1W0W0C0C0W0a1W1W0A1
        W0W1W1W2W2W2W1W1W0C0C0C0  W0
        W0W1W2W3W3W3W2W1W0C0C0C0C0
      W0W1W1W2W3W3W3W2W1W1W0C0C0  W0
        W0W1W2W3W3W3W2W1W0C0W0W0W0W1W0W0W0
          W1W1W2W2W2W1W1W0W0W0W1W1W1W1W1W0
          W0W1W1W1W1W1W0W0W0W1W1W2W2W2W1W1W0
          W0W0W0W1W0W0W0      W2W3W3W3W2
                W0              W3W3W3
```

Read together, the two show the room as a player would meet it: a warm pool
around the archivist and the burning lamps, a cool band across the rug where
the archivist walked earlier, the north-east folio flickering red with the
feeding inkmite beside it, and the creeping one's silhouette pointing at the
east desk.

## 9. Cost, reach and a turn's cycles

The hours are estimates. The cycles are estimates on the device's cost
model, set beside stage 4's measured move of about 37 million cycles
(plan, Appendix A); stage 5 would measure each piece it builds.

| Piece | Builds | Touches outside the game | Hours | A turn, estimated |
|---|---|---|---:|---|
| 1. Tone and intensity | State bits in both validators, CELL ramps, the rich theme, documents | MegaPad `rich_terminal/semantic_content.py`, `rich_terminal/pygame_view.py` and `docs/rich-terminal/SEMANTIC-CONTENT-1.md`; Akashic `tui/semantic-collections.f`, `tui/widgets/text-grid.f`, `docs/tui/semantic-collections.md`, `docs/tui/widgets/text-grid.md` | 4–6 | 0.5–1.5 M, mostly CELL spans: each move shifts the whole lit pool's intensity, about 50 tiles, where one observed move of the skeleton changed 19 items |
| 2. Unsteady mark | The bit, the renderer's flicker, CELL's blink | The files of piece 1, and the redraw timer in MegaPad's `session_viewer.py` | 1.5–2.5 | none; the renderer animates without frames |
| 3a. Viewport over the map | `game/board.f` | none | 0.5 | about 0.1 M for the CELL draw's larger fills, at the 23 cycles a cleared cell that stage 4's two region sizes imply |
| 3b. TILES flag | The flag in both validators, seamless scaled tiles in the rich renderer, CELL's centring and fill | The files of piece 1 | 3–4 | with 3a, more CELL cells change per move, since each lit tile covers about 15 cells at 132 by 38: 0.5–2 M |
| 4. Tile art | The game's tile texts; a narrow test of each glyph's face and width | none | 1 | none; the grid's text grows by about 200 bytes |
| 5. Light falloff | Intensities from the reveal and the lamps' layer | none | 0.5–1, in stage 5 | under 0.1 M |
| 6. Inkmites' look | Their tiles and the two silhouette rules | none | 0.5–1, in stage 5 | none beyond the items |

All of it comes to 11 to 16 hours, 8.5 to 12.5 of them outside the game,
and one physical Desktop journey, since pieces 1, 2 and 3b change the rich
path. On the device the estimated 1 to 4 million cycles a turn add little to
the measured 37 million: the turn's budget still turns on the text grid's
validation and the rich frame.

## 10. Choices for the author

1. **Tone and intensity, and where they live.** In the state word's spare
   bits, as proposed, the layout and existing content stay unchanged, for
   4 to 6 hours. A field of their own would need a second STX1 version, and
   every codec, the capture and their tests would change, roughly twice the
   work. Recommendation: the state word.
2. **How the board fills its pane.** Declaring the viewport alone costs half
   an hour inside the game library, but its tiles draw like spreadsheet
   cells. Adding the TILES flag costs 3 to 4 hours more on the rich path.
   Recommendation: both, the viewport first.
3. **Unsteady items in CELL.** Blinking or steady. Recommendation: blinking,
   since the flicker carries news a CELL player also needs, a lamp running
   dry or a folio being eaten, and a terminal that dislikes blink drops it.
4. **The silhouette rules.** An inkmite shows past the light's edge, and a
   feeding one marks its folio. Recommendation: yes, to be tested by stage
   5's balance runs, since without them the fun rules' readable creatures
   cannot hold for creatures that live in the dark.
5. **The archivist's glyph.** `@` follows the custom of the genre, and a
   glyph of the project's own could replace it. Recommendation: keep `@`.
