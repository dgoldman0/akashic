# Rich experience plan

Status: agreed plan, 2026-09-26. It sets the order of the next functional
work on the rich terminal and gives a rough approach for each part. Exact wire
records still go into the APT-1 contracts before any part is switched on.

## Why

A functional review of the current applets found that the rich Desktop works
but feels thin in seven places. The mouse only works on menus and tabs. Text
is limited to narrow, left-to-right characters in one host font. Text areas
are plain. Lists, trees, fields and dialogs show as painted text with no
structure. Plots and pictures are specified but switched off.

The foundation stays as it is: the complete CELL fallback, one projection of
the ordinary draw lifecycle, canonical widgets, and input bound to the
acknowledged frame. The
[ecosystem inventory](DESK-RICH-TERMINAL-ECOSYSTEM-INVENTORY.md) still
describes the target families (its section 6) and the architecture rules (its
section 8). This plan replaces its tranches D to F with a fixed order.

## Decisions

These were decided on 2026-09-26:

- The mouse comes first, because it is small and every applet gains from it.
- The first text pass includes right-to-left text in Hebrew and Arabic, not
  only wide characters and emoji.
- Styled text is described by meaning, not by colour, so each display can
  choose its own look.
- File Explorer previews of QOI images are the first use of pictures.

## Order

| # | Work | Main applets | Size |
|---|---|---|---|
| 1 | Mouse and scrolling everywhere | Desk and every applet | Small to medium |
| 2 | Wide text, emoji, right-to-left and fonts | Streams, Pad, File Explorer, Daybook | Large |
| 3 | Styled text and links in text areas | Pad, Library | Medium |
| 4 | Lists and trees | File Explorer, launcher, Daybook, Streams, Agent | Large |
| 5 | Fields, buttons, dialogs and status | Prompts everywhere, Agent, Sound Lab | Large |
| 6 | Plots and waveforms | Sound Lab, Observatory | Medium |
| 7 | Pictures | File Explorer | Medium |

Work goes in this order. Part 6 depends on nothing before it, so it may move
earlier if that is useful.

## Rules for every part

- **Contract first.** Each part changes the protocol contracts before any
  code. These are the APT-1 documents, which are mirrored in Akashic and
  MegaPad and must stay identical, and MegaPad's SEMANTIC-CONTENT-1. The
  project is unreleased, so contracts change in place and no old version is
  kept alongside.
- **Ordinary sources only.** Meaning comes from UIDL types and canonical
  widgets below the applet layer. Applets move onto shared widgets. They never
  gain a terminal API or a scene of their own.
- **CELL stays complete.** Every new feature also draws correctly in CELL.
- **One feature bit per new family.** It is advertised only when capture,
  lowering, refusal, the physical view and any return route are all complete.
- **Input stays bound to the acknowledged frame**, and the application stays
  in charge of its own state.
- **Device cost counts.** New work done on every draw, such as grapheme, bidi
  or style handling, needs a cheap path for plain left-to-right text, measured
  in guest steps.
- **Checks.** Lightweight tests run while building. Work on an applet is
  checked on that applet: its own tests and standalone smoke, then Desk with
  just that applet on the rich terminal
  (`local_testing/physical_desktop_acceptance.py --applet NAME`). Each part
  ends with new milestones in the physical Desktop journey
  (`local_testing/physical_desktop_acceptance.py`), which runs once all the
  pieces are right, as regression, one run at a time under the existing
  guards.

## 1. Mouse and scrolling everywhere

**Today.** The rich viewer resolves clicks only through its semantic hit map,
which has targets for menus, menu items and tabs. A click anywhere else, such
as on the taskbar, a Desk tile or a list row, is dropped, and the wheel does
nothing. The wire already carries cell-position pointer input, and the
guest's APT-1 shell already turns it into ordinary mouse events, which Desk
and the list widget handle. The text area widget has no mouse handling at
all, even in CELL.

**Plan.**

1. Viewer: a press, release, drag or wheel that lands on residual content,
   outside every semantic target, goes to the guest as raw pointer input at
   that cell, bound to the acknowledged revision. Semantic targets keep
   priority. Raw input is never sent over a control that the renderer lays
   out itself, such as a text area, because the cell under the pointer may
   not be the one the guest drew there.
2. Ordinary widgets: text areas, input fields and text grids learn click to
   place the caret or pick a cell, drag to select, and wheel to scroll. Trees
   learn click to select and expand. This helps CELL on a real terminal too.
3. Contract: control events gain point, drag and scroll kinds for text areas
   and text grids. They name an item key and scalar offset taken from the
   renderer's own layout, which is what SEMANTIC-CONTENT-1 says the current
   event shape lacks. The guest turns them into the same ordinary widget
   actions.
4. The real device's touch screen uses the same path.

**Done when** the journey clicks the taskbar and a list row, places Pad's
caret and selects text with the mouse, and scrolls Pad and a list with the
wheel.

**Status.** Done on 2026-09-26. The first physical journey run is recorded
in `local_testing/evidence/pointer-journey-20260926.md`. A follow-up, recorded
in `local_testing/evidence/pointer-followups-20260926.md`, finished what that
run left open. Input fields now keep a selection that a drag or Shift makes,
and app prompts in Desk receive clicks and drags. The text grid passes wheel
steps to its owner, and Daybook moves its date a week per step; that step
can become a setting once applets have settings. Pad's line and column
readout now changes in the same frame as the caret. Touch will reach the
same raw pointer route when the device's panel exists.

## 2. Wide text, emoji, right-to-left and fonts

**Today.** Akashic has Unicode 15.1 width tables (`text/cell-width.f`), but
the screen buffer cannot store a two-cell character or a combining mark. So
every wide character (Chinese, Japanese, Korean and most emoji), every
separate combining mark and every bidi control becomes U+FFFD. The CELL wire
carries one scalar per cell and no width flags. Text areas count one scalar
per column. Nothing handles right-to-left text. The viewer uses whatever font
the host calls "monospace", draws bold and italic synthetically, and has no
fallback font.

**Scope.** Wide characters, combining marks, emoji sequences and flags, and
right-to-left text in Hebrew and Arabic, including Arabic letter joining.
Indic and other complex scripts, and mirroring the whole interface for
right-to-left users, are later work.

**Plan.**

1. Contract. Pin one width rule that both sides use: the Unicode 15.1 tables
   already in `cell-width.f`. CELL gains a wide lead cell, a continuation
   cell, and a way to attach extra scalars to a cell for combining marks,
   emoji sequences and flags. That storage comes from negotiated bounds, not a
   fixed limit. Text areas and grids count columns by width, and offsets stay
   scalar offsets. Semantic text carries logical order and a paragraph
   direction.
2. Characters and widths in Akashic. A new grapheme module (Unicode text
   segmentation) finds whole user-visible characters. The screen buffer
   stores wide cells, continuation cells and the extra scalars. Drawing is
   width-aware, including a wide character cut by an edge. The width-one
   projection stays only for invalid input.
3. Right-to-left in Akashic. A new bidi module (the Unicode Bidirectional
   Algorithm) and Arabic joining. Drawing puts each line into visual order,
   picks joined Arabic letter forms for the cell grid, and mirrors brackets.
   Editing keeps text in logical order: the caret is drawn at its visual
   place, and clicks map back to logical positions. Lines with no
   right-to-left characters skip all of this.
4. Widgets. Input fields, text areas, text grids, lists, trees and labels
   measure by width and move the caret by whole characters.
5. Viewer fonts. A defined font set replaces the host's "monospace": one
   monospace family with real bold and italic faces, plus fallbacks for CJK,
   Hebrew, Arabic, symbols and emoji. Wide glyphs span two cells, and a
   missing glyph shows a visible box. The viewer orders and shapes semantic
   text itself, since it owns that layout. Fonts belong to the terminal and
   never appear in UIDL; the real device's terminal will choose its own set.

**Done when** Pad and Daybook show typed text that mixes English with
Chinese, accents built from combining marks, emoji sequences, flags, Hebrew
and Arabic, correctly in both CELL and rich, and the caret and mouse land on
the right characters. Both bidi implementations are checked against Unicode's
bidi conformance data.

**Contract.** Written on 2026-09-26. The shared rules are a new mirrored
document, [APT-1-TEXT.md](APT-1-TEXT.md). It pins Unicode 15.1.0 and the
exact data files, defines a character as an extended grapheme cluster, and
gives one width rule for scalars and one for characters (flags, emoji
presentation, and stray marks included). Invalid UTF-8 and control scalars
become U+FFFD; that is the only width-one projection left. Each row is one
bidi paragraph (LTR, RTL, or first-strong AUTO), whole characters are
reordered, mirrored brackets are shown at odd levels, and Arabic letters take
their joined presentation forms, one cell each. Lam with alef keeps two cells
in this pass instead of forming a ligature. A point on a character names the
position before it, and the caret belongs to the character that starts at
it.

CELL keeps its 8-byte cells. Attribute bits 7, 8, and 9 mark a wide lead, its
continuation, and a cell whose extra scalars follow in a new tail at the end
of each `CELL_SPAN`. Transactions grow by four bytes per tail word. When tails
would not fit the negotiated payload or transaction bounds, the client sends
that transaction with its cluster cells degraded to U+FFFD, so tails never
make a transaction fail. `GLYPH_RUN` text is visual-order display text that
the renderer segments and slots by width; it never reorders or joins it.

STX1 gains a paragraph direction in content flag bits 1 and 2. Text area
columns now count cells, and a tab is one cell. A text area row that resolves
to right-to-left is mirrored: it starts at the viewport's right edge and its
horizontal origin counts from there. Offsets stay scalar offsets.

**Status.** Done on 2026-09-27. The physical journey run is recorded in
`local_testing/evidence/mixed-text-journey-20260927.md`. Pad and Daybook take
the mixed text in CELL and rich, and clicks and the caret land on whole
characters. Both bidi implementations pass every case of Unicode's two bidi
test files. Labels, menu bars, tabs, text grids and dialogs now measure text
in cells too. Text longer than one TEXT event is sent as several events,
split between characters. Desk can run with a single applet on the rich
terminal, to check an applet's work before the full journey. Desk's taskbar,
hotbar and launcher still measure their labels in bytes; they only ever show
ASCII app titles, so they can wait until non-ASCII titles are allowed.

## 3. Styled text and links in text areas

**Today.** Text areas carry plain text only, and STX1 has no inline styling.
Akashic already has a syntax highlighter (`text/syntax.f`) with Forth,
Markdown and plain scanners, but nothing uses it. Pad shows no highlighting,
even in CELL.

**Plan.**

1. Ordinary side first. The canonical text area gets an optional style
   source: spans marked by meaning, such as keyword, comment, string, number,
   heading, emphasis, strong, code, link and error. Pad fills it from the
   existing highlighter by file type, which also covers Daybook's Markdown
   file when Daybook hands it to Pad. Library's document view is the second
   consumer. CELL shows each meaning through a theme palette.
2. Contract. Semantic text gains style runs: a start offset, a length and a
   meaning from a list defined in the contract. No colours go on the wire.
3. Viewer. A theme maps each meaning to a look. A colour screen can use
   colour, and e-paper can use weight and underline.
4. Links. The wire marks a span as a link. Clicking it sends an activate
   event through part 1's text-position events, and the application looks up
   the target and decides what happens, such as opening a file. Nothing opens
   a host browser.

Headings stay on the cell grid. They use weight and colour, not bigger text.

**Done when** Pad shows highlighted Forth and Markdown in CELL and rich, and
clicking a Markdown link in Pad opens the file it names.

**Contract.** Written on 2026-09-27. In MegaPad's SEMANTIC-CONTENT-1, each
STX1 item now ends with style runs: a start and a length in Unicode scalars
and one of ten meanings, which are keyword, comment, string, number,
heading, emphasis, strong, code, link and error. Runs are in order, do not
overlap, and two runs with the same meaning never touch. Only text areas
carry them for now. A character takes the meaning of the run over its first
scalar. Runs carry no colour, font or size. Each renderer's theme picks the
look, never moves a character out of its cells, and must make links look
different from plain text.

APT-1-WIRE and RETAINED-1 add a fifth control event, `FOLLOW`. It names a
position on a link character, as `PLACE` names one. The terminal sends it
for a press on a link with Ctrl held, or for a plain press on a link in
read-only text. So in editable text such as Pad, a plain click still places
the caret, and Ctrl-click follows the link. The application decides what
following does, and no link target crosses the wire.

**Status.** Done on 2026-09-27. The physical journey run is recorded in
`local_testing/evidence/styled-text-journey-20260927.md`. Pad highlights
Forth and Markdown by file name in CELL and rich, including Daybook's
Markdown file when Daybook hands it to Pad. Ctrl and a click on a Markdown
link opens the file it names, relative to the linking file's folder; a link
with a scheme such as `https:` is refused with a message. The viewer's
reference theme gives each meaning a colour, uses the font's real bold and
italic faces, and underlines links. Two parts of the plan are not done.
Library's document view still draws its text by hand, so it is not yet a
second user of the style source, and there is no e-paper theme yet.
Highlighting adds 11% to a full redraw of 60 lines of Forth and 8% for
Markdown. Publishing scans each row again, about 3.4 million guest steps
per pass for 60 lines of Forth; keeping the runs between passes is left for
later.

## 4. Lists and trees

**Today.** File Explorer's tree and list, the Desk launcher and taskbar,
Daybook's agenda, Streams cards and the Agent transcript are all painted
text. Rich output shows them, but with no items, selection or structure.

**Plan.** One item-view family, as in inventory section 6.6. It has stable
item keys, an optional parent and depth, ordered fields, and selected,
current, checked, expanded and enabled state, plus a viewport. Its role says
whether it is a list, tree, table, sections or cards; the renderer never
guesses structure from indentation. Events select, activate, expand, collapse
and scroll by item key.

1. Akashic: the canonical list and tree widgets publish neutral snapshots, as
   the text area and text grid already do, followed by lowering, claims and
   refusal.
2. MegaPad: the model, view, hit map and events.
3. Consumers, in order: File Explorer, the launcher, Daybook's agenda
   (sections and checked items), then Streams cards and the Agent transcript,
   which reuse part 3's style runs and links. Library is the design check.

**Done when** the journey selects and opens a file in File Explorer and
launches an app from the launcher through item events.

**Contract.** Written on 2026-09-27. MegaPad's SEMANTIC-CONTENT-1 gains a
ninth control kind, `ITEM_VIEW`, with its own body, `ITM1`, behind a new
feature bit 10, `RET_CONTROL_ITEMS`, which needs bits 8 and 9. The body says
whether the view is a list, tree, table, sections or cards. It names its
columns, each a text or number column with an optional label, and carries
the items in the order the application shows them. Each item has a stable
key, a parent and depth, a role (an item or a section heading), its fields,
and its state: selected, current, expandable, expanded, checkable, checked
and unavailable. Fields are text with part 3's style runs. The viewport is a
range of that order; every item in it is carried, and so is the selected
item. Rules on parents, depths and order make a tree's shape explicit, so a
renderer never has to guess it.

APT-1-WIRE and RETAINED-1 add five control events that name one item:
`SELECT` for a press on an item, `OPEN` for a second press on it within the
terminal's double-press interval, `EXPAND` and `COLLAPSE` for a press on its
disclosure mark, and `CHECK` for a press on its check box. `SCROLL` also
works on item views. `OPEN` is the plan's "activate", and `CHECK` is there
for the check boxes in Daybook's agenda. The application decides what each
event does, and keys still reach it as before.

**Status.** The "done when" was met on 2026-09-27. The physical journey run
is recorded in `local_testing/evidence/item-views-journey-20260927.md`. The
canonical list and tree widgets publish item views and take item events by
key. File Explorer's folder tree and its Name, Size and Type table are rich,
and the journey scrolls the table, selects large.txt and opens it in Pad
with item events. Desk's launcher is now a small Desk-owned UIDL document
holding a canonical list, in an overlay slot of the applet host, and the
journey launches Sound Lab from it with `SELECT` and `OPEN`. Selecting a
file in File Explorer no longer switches to the Preview tab, so the row
stays in view to be opened. The run also showed an older File Explorer
defect, since fixed: it kept raw VFS entries, which go stale when another
applet replaces a file (Daybook saves by renaming a new copy over its
file), so a row could show another file or none. File Explorer now keeps
paths and copies of its rows.

On 2026-09-28 two more consumers were done, recorded in
`local_testing/evidence/item-views-consumers-20260928.md`. Daybook's agenda
is a canonical list in sections with check boxes, published as `SECTIONS`,
and a `CHECK` marks a task done. Streams' timeline and context are card
lists, published as `CARDS`, and web links in post text carry `LINK` style
runs. Desk with each applet passed through the physical viewer, and the
Desktop journey passed as regression at both commits. Library's design
check found that its record lists fit as tables of one query page each,
with page turning left to Library, and that its preview, wrapped document
text, belongs to part 3's text areas. The Agent transcript is not done. It
wraps each message, and its approval review counts the rows the user has
paged through, while card fields were one line each.

On 2026-09-28 the Agent transcript took wrapped card fields, in their
production form: each message becomes one card whose text wraps, and the
approval review moves out of the transcript into its own dialog. There the
Agent lays out every row itself and keeps Approve locked until the review's
last row has been shown, as today. The contract was written the same day.
In SEMANTIC-CONTENT-1 a card column may carry a `WRAP` flag, and a field in
such a column may hold line feeds. Its paragraphs break into lines by a new
rule, APT-1-TEXT Section 12: after spaces, and inside a word only when the
word is wider than the line. Card rows are exact on both sides: field 0's
lines are two cells narrower than the view and later fields' four, and a
new viewport row in the ITM1 header says how many rows of the first card
are scrolled out of view, so a long message scrolls line by line. The ITM1
header grows to 48 bytes, and card items no longer have check boxes.

MegaPad implements the contract in its codec, terminal check and reference
renderer. In Akashic the line rule is `text/text-lines.f`, with `TROW-LINE`
laying out each line from its paragraph's levels, and both match MegaPad's
implementation on fixed and random text. The canonical list's card mode
takes wrapping columns: CELL draws each card on exactly the rows the rich
renderer gives it, the view scrolls by screen rows, and the item view
carries the `WRAP` flags, the line feeds, and the viewport row, which
random lists check against MegaPad's own row count.

The Agent now uses it. Its transcript is a canonical card list in a new log
mode: one card per message, with the role and state as its header and the
message's text as a wrapping field. A log has no selection; its keys and wheel
scroll it, and it follows the newest message until the reader scrolls away.
The list keeps each wrapping field's line count with a copy of the text it
counted and reuses the count only while the bytes are the same, so a long
conversation is not laid out again on every frame. Line breaking has a cheap
path for text whose characters are each one cell wide and never reorder, and
layout of other text got faster. The approval review is a dialog of its own
over the transcript. It lays out every row itself and keeps F6 locked until
it has shown the last row of the review as it stands.

Desk with only the Agent checked this through the physical viewer, and the
Desktop journey passed as regression; both runs are recorded in
`local_testing/evidence/agent-transcript-20260928.md`. The Agent starts from
a long stored conversation, so its transcript is taller than the view. The
check scrolled it with an item `SCROLL`, returned to the end, asked for a
reviewed change, and approved it in the dialog. That run also found and fixed
a dialog that said "F6 locked" after showing its last row. With the Agent
transcript, every consumer part 4 named is done. The Desktop journey itself
has no Agent steps: there the Agent starts with an empty conversation.

## 5. Fields, buttons, dialogs and status

**Today.** Prompts, dialogs, toasts, progress bars and status lines are
painted text. After part 1 they can be clicked, but only as painted cells.

**Plan,** following inventory sections 6.4, 6.5 and 6.8:

1. Fields: one-line input with a label, value, placeholder, caret, masked
   mode, validation, and submit or cancel. The canonical input and prompt
   widgets are the source.
2. Dialogs: overlays with a title, contained controls, default and cancel
   actions, and a modal focus scope.
3. Buttons, checkboxes, choices and ranges, from the UIDL action, toggle,
   selector and range types.
4. Notices, toasts, progress and textual status.

Consumers include File Explorer rename and go-to, Streams search, Agent's Ask
and masked credential prompts, Agent settings, Daybook task checkboxes and
Sound Lab parameters. Agent approval stays in Agent's hands, with its
existing checks.

**Done when** the journey renames a file through a semantic field and
answers a dialog with a semantic button.

## 6. Plots and waveforms

**Today.** MegaPad already supports vector lines, bounded series, plots and
waveforms from wire to screen. The Desktop does not advertise them, because
Akashic cannot produce them. The data-graphics model stops at readouts,
meters and status, and Sound Lab draws its waveform out of text characters.

**Plan.**

1. Extend the data-graphics model with series, plots, waveforms and polyline
   markers. The canonical data-graphics widget draws them in CELL too.
2. Sound Lab moves its waveform onto that model instead of drawing it itself.
3. Akashic gains capture and a separate series and object producer plane,
   with refusal.
4. Advertise the series and vector bits once complete. Observatory is the
   second consumer.

**Done when** the journey shows Sound Lab's waveform through the series path
and CELL still shows it.

## 7. Pictures

**Today.** MegaPad supports RGBA image upload and image objects with stretch,
contain and cover. Akashic has no image path. It can decode QOI
(`render/qoi.f`) but not PNG or JPEG.

**Plan.**

1. An ordinary image concept, from the UIDL media type or a canonical image
   widget, with a CELL fallback such as a coarse block-character preview or a
   labelled placeholder.
2. An Akashic resource-upload plane, kept separate from controls, plus image
   objects.
3. File Explorer previews QOI files. Advertise the image bit once complete.
4. Later: Streams post images, which first need image fetching and a PNG or
   JPEG decoder, and app icons.

**Done when** the journey previews a QOI image in File Explorer.

## Not in this plan

- Indic and other complex scripts, and mirroring the interface for
  right-to-left users.
- Editing inside the terminal itself. That would change a core design
  decision.
- Copy and paste with the host clipboard, the bell, and cursor styles.
- Reset, resize and reconnect qualification, e-paper damage and cadence, and
  the physical UART and panel. These remain the open stages in
  [AKASHIC-RICH-TERMINAL.md](AKASHIC-RICH-TERMINAL.md) section 0.1.
- Idle waiting, where the guest sleeps until input or its next deadline. It
  is a separate device track; this plan neither blocks it nor waits for it.
- Repairing or retiring the legacy test scripts, and the failing KDOS file
  test.
