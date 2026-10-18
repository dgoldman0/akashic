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
| 7 | Pictures | File Explorer | Large |
| 8 | Frames during uploads | Every screen while a picture uploads | Medium |
| 9 | Pictures the terminal decodes | File Explorer | Medium to large |
| 10 | Screen changes that cost what they change | Desk and every applet | Medium to large |
| 11 | Uploads that read as they send | File Explorer | Medium |
| 12 | Documents | File Explorer | Large |
| 13 | Decompression | File Explorer | Medium |
| 14 | PDFs | File Explorer | Large |

Work goes in this order. Part 6 depends on nothing before it, so it may move
earlier if that is useful. Part 7 depends on nothing in parts 5 and 6 either.

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

**Today.** A little of this part exists. Sound Lab's settings are canonical
typed fields (`tui/widgets/field.f`), published as `FIELD` controls that the
wheel adjusts, and the labels of a UIDL `<status>` bar are published as
`STATUS_FIELD` objects. Both have been selected in the Desktop profile since
2026-09-30 ([FIELD-PRODUCER.md](FIELD-PRODUCER.md),
[STATUS-FIELDS-PRODUCER.md](STATUS-FIELDS-PRODUCER.md)). A `FIELD` of kind
TEXT can carry only committed text, with no caret, selection or scrolling,
and nothing publishes one. Everything else is painted text:

- **Prompts.** One shared prompt (`tui/widgets/prompt.f`, over
  `tui/widgets/input.f`) serves Desk and eight applications: about 40
  prompts, one of them masked. It paints over the status row as foreground
  paint, and the aggregate adapter then withholds every semantic slice of
  the document beneath. So while a prompt is open, its application's menus,
  text areas, grids and lists all go out as residual glyphs, and Sound Lab's
  fields drop to CELL.
- **Dialogs.** One shared dialog (`tui/widgets/dialog.f`) asks the nine
  questions of File Explorer, Pad, Grid, the Agent and Sound Lab, such as
  closing with unsaved changes or deleting a file. It runs its own blocking
  input loop, so all of Desk stops until it is answered, and it ignores the
  mouse.
- **Confirmations by typed word.** Daybook (DELETE, DISCARD and RELOAD),
  Library (DISCARD) and Streams (REMOVE) ask the user to type a word into a
  prompt.
- **Desk's own screens.** The launcher, schedule approval, permissions,
  shutdown, sandbox access and the sandbox inspector are overlay documents
  of labels around a canonical list. The lists are item views. Their titles,
  questions and hints are residual, and nothing says the screen is a dialog
  or that it is modal.
- **Toasts.** About 300 calls in ten applications go through the app shell's
  one toast bar (`ASHELL-TOAST`), which is foreground paint with no meaning:
  an error looks like a success.
- **Toggles and choices.** Menu items that toggle or choose, such as File
  Explorer's Show Hidden and Sort, Pad's panels and the Agent's Access
  presets, show no checked state. The Agent's settings rows, the Worlds valve
  and Streams' source switches are painted.
- **Status.** Library, Sound Lab, Streams, Worlds, Observatory, Grid's
  formula bar and Desk's agent state paint their status instead of using
  status labels.

No application uses UIDL's own `<input>`, `<toggle>`, `<dialog>` or visible
`<action>` elements, and nothing shows a progress bar.

**Decided on 2026-10-14.**

- Dialogs stop freezing Desk. A dialog is modal only for its own
  application: Desk and the other applications keep running, and the dialog
  takes the mouse.
- Confirmations by typed word become confirm dialogs. The destructive button
  is never the default.
- Notices carry a meaning: info, success, warning or error, the severities
  status fields already have. Toasts that report a failure or a warning are
  marked where they are raised; the rest stay plain.
- The work goes through the shared widgets applications already use: the
  prompt, the dialog, the app shell's toast, the field and the list. UIDL's
  input, toggle, dialog and action elements, and progress bars, wait for a
  real use.

**Plan.**

1. **Contract,** in both copies of APT-1-RETAINED-1 and APT-1-WIRE, and in
   MegaPad's SEMANTIC-CONTENT-1:
   - *Text fields that show typing.* A TEXT `FIELD` carries its caret, an
     optional selection anchor, its scroll in cells and a placeholder, and a
     `MASKED` flag. A masked field's value holds one mask character for each
     character, never the secret. `SELECTED` means the field has the
     keyboard, and only then does the terminal draw the caret. `PLACE` and
     `EXTEND` name a position in a writable TEXT field as they do in a text
     area. TEXT fields lose `ACTIVATE`, which nothing sends.
   - *Modal regions.* A region flag, `MODAL`, makes the region's rectangle a
     modal scope. Its barrier already keeps points from the regions beneath;
     the flag also lets the renderer show what lies beneath as inactive. A
     prompt or a dialog sits in a modal region over its application's pane,
     and a modal screen of Desk's in one over the whole screen.
   - *Dialogs and buttons.* Two control kinds behind a new feature bit 17,
     `RET_DIALOGS`. A `DIALOG`'s label is its title, and its content gives
     its message lines, its severity and a `NOTICE` flag. A `BUTTON`'s
     content says whether it is the default, the cancel or a destructive
     button, and it takes `ACTIVATE`. A dialog's buttons, fields and lists
     are roots of their own inside its rectangle, above it in the same
     region. Within a region the topmost control takes a point, as the hit
     map already orders them. A notice is a `DIALOG` with the `NOTICE` flag
     and no buttons, in a region that covers only itself.
   - *Catching up.* APT-1-WIRE gains what RETAINED-1 already has: `ACTIVATE`
     on `TASK`, `LAUNCHER` and `FIELD`, the `ADJUST` event, and `TASKBAR` and
     `FIELD` among the surfaces where no raw gesture starts.
2. **MegaPad.** The codec, the scene and terminal checks, the guest module's
   writers, the reference renderer and its hit map, the viewer's routing,
   the shared-viewer transport and the flowing appearance, for the whole
   contract at once.
3. **Prompts.**
   - The prompt publishes a TEXT field from its input's own state: label,
     text (masked when the prompt masks), caret, selection, scroll and
     placeholder. Draw observation finds it, as it finds the other canonical
     widgets.
   - The producer puts the field in a modal region over its pane. The
     document beneath keeps its semantics, inactive under the modal region,
     except for a root the prompt's paint covers, such as the status field
     the prompt replaces. Foreground paint that is not a captured overlay,
     such as the Agent's own panels, keeps today's rule.
   - `PLACE` and `EXTEND` reach the input widget, which sets its caret and
     selection from scalar offsets.
   - Desk's Ask prompt, on the taskbar row, goes out the same way through
     the shell producer.
4. **Dialogs.**
   - The dialog widget stops blocking. An application opens a dialog with
     a callback for its answer, and the app shell, or Desk's applet host,
     draws it over the application and gives it the application's input
     until it closes. It takes the mouse in CELL too. The nine call sites
     move to callbacks.
   - The dialog publishes a `DIALOG`, and a `BUTTON` for each answer, in a
     modal region over its pane.
   - The confirmations by typed word become confirm dialogs.
   - Desk's screens mark their title and message in their UIDL, so they go
     out as a `DIALOG` around their lists, modal over the whole screen.
     Schedule approval keeps its rule: Allow stays unavailable until the
     request has been read to its end.
   - The Agent's approval review shows Approve and Deny as buttons. Approve
     stays unavailable until the review's last row has been shown, as today.
5. **Notices.** The app shell's toast publishes a notice with its meaning,
   in a region of its own. Toasts that report failures and warnings are
   marked where they are raised.
6. **Toggles, choices and ranges.**
   - UIDL menu items gain a checked state taken from the application's
     state. CELL draws it, and the menu snapshot publishes it as `CHECKED`:
     Show Hidden, Sort, Pad's panels and the Access presets.
   - The Agent's settings rows become `CHOICE` fields and the Worlds valve
     an `INTEGER` field, through the canonical field widget.
   - Streams' Sources and Burrows views become card lists whose check boxes
     switch a source on and off.
7. **Status.** Painted status moves to UIDL status labels: Library, Sound
   Lab's output and playback lines, Streams, Worlds, Observatory and Desk's
   agent state. Grid's formula bar becomes a read-only TEXT field.
8. **Measure.** Guest steps for a key typed into a prompt, for opening and
   answering a dialog, and for showing a notice, rich and CELL.

**Checks,** in order:

- Contract: codec vectors and refusals for the new field state, `DIALOG`,
  `BUTTON` and modal regions; the terminal's checks; off-screen compositor
  checks of the reference renderer; and hit-map checks that a modal region
  stops points beneath it, that the topmost control takes a point, and that
  `PLACE`, `EXTEND` and `ACTIVATE` reach the right control.
- Widgets: CELL byte oracles for the prompt and the dialog, unchanged except
  where the mouse now works; the dialog's callbacks; and each application's
  own tests and standalone smoke once its call sites move.
- Producer: capture and lowering of prompts, dialogs and notices; refusal
  leaving CELL; a document under a prompt staying semantic; and input
  reaching the widgets.
- Desk with each application through the physical viewer as its step lands:
  File Explorer's rename, go-to and delete; Pad's Open prompt and its
  close-tab question; Daybook's task prompt and confirmations; the Agent's
  masked credential prompt; Sound Lab's exact-value prompt; Desk's launcher
  and shutdown screens.
- The full Desktop journey once at the end, with new milestones.

**Done when** the Desktop journey, in the physical viewer, renames a file in
File Explorer through a semantic field, answers a dialog with a semantic
button and shows a notice with its meaning; while a prompt or a dialog is
open, the rest of its application stays rich and inactive beneath it; and
Desk keeps running while a dialog waits.

**Status.** Done on 2026-10-17. The closing runs are recorded in
`local_testing/evidence/part5-desktop-journey-20261017.md`. Prompts are
`TEXT` fields in a modal region over their pane. Since 2026-10-15 a dialog
asks without stopping Desk and goes out as a `DIALOG`, with a `BUTTON` for each answer, in a modal region
over its pane ([DIALOG-PRODUCER.md](DIALOG-PRODUCER.md)). In the physical
viewer, Desk with Pad answers Pad's close-tab question and Desk with File
Explorer its delete question, each through its Cancel button. A dialog
covers the roots it lies over, which go out as residual glyphs until it
closes. The confirmations by typed word are confirm dialogs too: Daybook's
delete, reload and close questions, Library's close with a create pending
and Streams' source removal. Desk with Daybook answers the delete question
for its daily reminder through Cancel. An application that asks while its
prompt is open goes out as CELL until one of them closes, since the shell
allows one overlay a pane; Daybook and Library refuse a close while their
prompt is open. Desk's screens are UIDL dialogs too: the launcher, the
sandbox's access prompt and inspector, and the schedule's approval and
permissions frame their lists in a `<dialog>` whose title and leading
labels are its message, and it goes out as a `DIALOG` around its contents.
In the shell frame a screen is an overlay pane over the panes beneath it,
its document in a modal region over the whole screen, so the panes and the
taskbar show inactive while it is open; in the physical viewer Desk with
File Explorer opens its launcher that way. A screen may cross the divider
between two tiles: its overlay pane lies over the chrome of the panes
beneath it, and its own glyphs cover the divider. The Agent's
approval review asks in the shared dialog: its message, the request's
paragraphs broken by the shared line rule as untrusted text, scrolls, and
Approve once (F6) is a read-first button that cannot be chosen until a
paint has shown the last line, beside Deny (F7), the default and cancel
button. In the physical viewer Desk with the Agent approves a request
through the Approve once button, with the Agent's menu inactive beneath
the dialog. Notices are done too. The app shell's toast is a notice with a
meaning, neutral, info, success, warning or error, a status field's
severities; it keeps its own copy of its text and fits the screen, and a
press on it lands on it. Applications mark the failures and warnings they
raise where they raise them. Desk's shell model carries the notice a paint
shows, and with dialogs the shell candidate shows it as a `DIALOG` with the
`NOTICE` flag in a region of its own above the taskbar, which stays rich
beneath it. In the physical viewer Desk with Daybook shows the reminder as
a neutral notice, and Desk with File Explorer warns that a path typed into
Go to was not found. Without dialogs, and for an application run without
Desk, a notice is still paint. A review of the dialogs found four faults,
now fixed: a dialog too short for any message row counted its message read;
a Desk shutdown that applications deferred to their questions stopped once
they agreed, and now goes on; the reference renderer started right-to-left
dialog text and button labels at the left; and a wheel over a dialog went
nowhere in the physical viewer, where a dialog that is not a notice now
takes `SCROLL`. Toggles and choices are done. A UIDL menu item can be
checked from its application's state, every CELL menu keeps a two-cell
mark column for it, and the menu snapshot carries it as `CHECKED`: File
Explorer's Show Hidden and sort orders, Pad's panels and the Agent's Access
presets. The Agent's run settings are four `CHOICE` fields that the shared
field widget draws in its panel; in the physical viewer Desk with the Agent
moves Reasoning with an adjustment and Model with an activation. The
Worlds valve is an `INTEGER` field over the run's own range; Worlds is in
no Desktop profile, so a standalone CELL smoke and the Observatory/Worlds
slice check it. Streams' sources and Burrows are card lists now, and a
source's card carries a check box that is checked while the source is
enabled: SEMANTIC-CONTENT-1 lets a `CARDS` item be `CHECKABLE`, with its
box on its first row and its first field narrower to make room, and the
shared list draws, hit-tests and publishes it. In the physical viewer Desk
with Streams adds a feed source through its prompt and switches it off by
its card's check box. That check found that Streams' prompt left its paint
on the status bar's row after closing, which hid the whole Streams document
from the rich frame; Streams now repaints the status bar, as five other
applications did, and Grid and Library do too. Status is done as well.
UIDL's string pool now gives each attribute the room its value holds, so
status text whose length changes no longer uses the pool up over a long
session. Worlds says its run state, its last action's outcome and its last
replay in status labels, in place of a painted footer; Observatory's state
label says how its profile went, or why it was refused; and Sound Lab
leaves its output and playback to its status labels, its lamps kept with
fixed captions. Streams and Library already said their status in labels,
and what they paint beside them is content. Desk's agent state is a status
field: Desk's shell model carries it, the shell candidate shows it in a
region of its own across the taskbar row past the entries, with a severity
for each state, and a change of state goes out as a DELTA. In the physical
viewer Desk with the Agent shows it through the approval review. Grid's
formula bar is a read-only TEXT field through the shared field widget, its
value the cell's source as a display shows it; Grid is in no Desktop
profile, so its CELL smoke and its own tests check it. A UIDL status label
still goes out neutral, since UIDL gives a label no severity; the first
application whose status needs one adds it. The measures of step 8 are
recorded in `local_testing/evidence/part5-interaction-costs-20261017.md`,
from File Explorer, Daybook and the Agent with Desk. A key typed into Desk's
Ask prompt is a DELTA of about 4 to 6 million guest steps. A key typed into
an application's prompt is a START, mostly 12 to 15 million steps a frame,
of which about 3 to 6 million lie outside the rich producer, what a CELL
session spends; a PLACE or an EXTEND on the same prompt is a DELTA of 2 to
3.5 million. Opening or closing a prompt or a dialog, and a notice coming
or going, add or remove a region, so each is a START by design, about 6 to
27 million steps in the rich producer; a notice shown costs about 12.7
million there and 0.5 million in Desk's paint. Answering a dialog costs 24
to 35 million steps outside the producer, since the application paints far
more after its dialog closes than after its prompt does. Two costs remain
to cut: typing into an application's prompt should be a DELTA, as typing
into Desk's is, but the producer does not match those draws, for a cause
not yet found; and a dialog that closes should not cost its application
more paint than a prompt that closes.

The full Desktop journey closed the part. In the physical viewer it renames
a file in File Explorer through its rename prompt, a semantic field, and
checks File Explorer's neutral notice. Delete then asks File Explorer's
question; Alt+1 gives Pad focus while it waits and Alt+2 brings File
Explorer back, its question still open and holding File Explorer alone,
and the question's Cancel button answers it. Sound Lab's frequency is set
through its exact-value prompt, with Sound Lab rich and inactive beneath
it, and F5 renders it again. The launcher, which crosses the divider
between File Explorer's tile and the Agent's, goes out in the shell's
frame, modal over everything beneath it. File Explorer's own journey
completes its rename, and the Agent's scrolls its approval review with the
wheel. The closing runs found one more fault: the app shell started a
notice's time when the notice was raised, so a paint that came late, as on
the busy Desktop, could show no notice at all. A notice's time now counts
from when the first output that shows it has gone out (part 6 moved it
there from the first paint, for frames slower than the notice).

**Not in this part.** Progress bars and busy indicators. UIDL's input,
toggle, selector and range elements in documents that use them.
Adjusting splits. Editing a grid cell in place. Plots and vector lines,
which are part 6.

## 6. Plots and waveforms

**Today.** MegaPad supports `GROUP`, `POLYLINE`, `PLOT` and `WAVEFORM`
from the guest module's writers to the screen: codec, scene checks,
reference renderer and shared view. Series and waveforms are done on the
Akashic side: the data-graphics model carries them, Sound Lab's waveform
uses that model, the canonical widget draws it in CELL too, and the Desktop
advertises the series family (see [SERIES-PRODUCER.md](SERIES-PRODUCER.md)).
That family covers `PLOT` too, but nothing in Akashic sends one: the
data-graphics model has no plot record and the engine no plot kind.
Nothing sends `GROUP` or `POLYLINE` either, and the Desktop does not
advertise `VECTOR`. Two applications paint their plots by hand:

- **Observatory's projection.** One dot a column over a painted baseline,
  each dot picked by sample index rather than by tick. Observatory is in no
  Desk profile, and neither is Worlds, whose Analyze hands Observatory its
  telemetry.
- **Sound Lab's frequency landmarks.** A painted line from 0 Hz to 4 kHz,
  with the letters P and C where its pitch and spectral centroid lie.

The contract has one weak point here. `VECTOR` has a limit on the points in
one line, `max_path_points`, but no budget for points, so a terminal must
keep room for every object it grants to be a line of the largest size. That
is reserving the maximum. Text and series samples are budgets an owner
reserves and grows instead.

**Decisions,** made on 2026-10-18:

- A line's points come out of a budget, like samples. `RET_FORMATS` offers
  a total and `OWNER_OPEN` reserves a share; each record already has a
  reserved field at offset 56 to carry it.
- Sound Lab's landmarks become vector lines: the line itself, and a marker
  for the pitch and one for the centroid. The letters stay as text in the
  row above the markers, so CELL still says which is which. Observatory's
  plot becomes a `PLOT` over its exact series, with its baseline a vector
  line. No new markers are added, and `GROUP` stays unused, since nothing
  needs it.
- Each application keeps one data-graphics graph, as Sound Lab does today:
  the plot and the lines join its readouts.
- Observatory is checked on a Desk profile with Worlds beside it, so its
  plot shows Worlds' own telemetry after Analyze.

**Plan.**

1. **Contract,** in both copies of APT-1-RETAINED-1:
   - `RET_FORMATS` offset 56 becomes `total_path_points`, positive exactly
     when `VECTOR` is set and at least `max_path_points`.
   - `OWNER_OPEN` and `OWNER_RESIZE` offset 56 become `path_point_quota`:
     the points of the owner's `POLYLINE` objects. Like the sample-slot
     quota it bounds each scene target, active and hidden alike, never
     shrinks within an owner generation, is summed against
     `total_path_points` across live owners, and must be zero without
     `VECTOR`. A line that would exceed it is a quota failure.
   - The worst-case rule (`object_quota * max_path_points`) goes.
   - Section 16.1's list of the reference profile's features, long out of
     date, is corrected.
2. **MegaPad.** The guest module's discovery and owner writers, the codec,
   the scene's quota ledger, the server, the module's documentation, the
   conformance vectors, and a server test that sends a `POLYLINE` and a
   `PLOT`, which no test does yet.
3. **Model.** The data-graphics model gains a `PLOT` record (its series,
   range, line and fill colours, and fill and points flags) and a
   `POLYLINE` record (stroke width, colour, closed flag and its points
   relative to its rectangle), with builders, accessors and validation.
4. **CELL.** The canonical widget draws a plot as a line through every
   sample, placed by timestamp as a waveform is, with the fill below it and
   a mark at each sample when its flags ask, and a vector line as line
   characters along its segments. Both are clipped as the rest of the
   widget is.
5. **Capture, lowering and refusal.** The instrument planner lowers `PLOT`
   (with the series family) and `POLYLINE` (with the vector family) as two
   more instrument kinds and counts their frames, points and quota need. A
   graph is left out whole, to CELL, when its terminal lacks the family, a
   line has more points than the terminal allows, or a frame cannot fit.
   The engine checks the new kinds, the APT-1 provider sends them and
   carries the point budget through discovery and the owner's quotas, and
   the screen producer asks for the points it needs and keeps an unchanged
   plot or line in a DELTA.
6. **Desktop profile.** It advertises `VECTOR`. The point limit and the
   point budget derive from the data-graphics bank Desk already selects,
   since every point takes 16 bytes of it, as the profile's other budgets
   derive from Desk's banks.
7. **Observatory.** Its series and plot join its graph, with banks sized to
   the series it holds and grown when a larger one arrives. The painted
   plot goes.
8. **Sound Lab.** The landmarks join its graph as three vector lines. The
   painted line and letters go; the letters return as text above the
   markers.
9. **Measure.** Guest steps for frames that carry Observatory's plot and
   Sound Lab's lines, rich and CELL.

**Checks,** in order:

- Contract and MegaPad: discovery and owner quotas in the guest module's
  tests, the codec's vectors, the scene's quota refusals, and a `POLYLINE`
  and a `PLOT` through the server.
- Model and widget: record extents, references and refusals; CELL byte
  oracles for plots and lines, including clipping.
- Lowering: each kind lowered exactly; whole-graph refusal leaving CELL;
  reuse of an unchanged plot and line.
- Observatory: its own tests and the Observatory/Worlds slice, then a new
  Desk profile with Worlds and Observatory through the physical viewer.
  Observatory's plot of its starting series goes out as a `PLOT` over a
  series holding exactly those samples. Worlds runs and Analyze hands the
  run's telemetry over; the plot's series then holds exactly the samples
  Observatory shows in its table and readouts. A rerun keeps the plot.
- Sound Lab: a new Desk profile with Sound Lab alone through the physical
  viewer. A render shows the three lines with the markers at the pitch and
  centroid it reports; a new frequency and another render move the pitch
  marker.
- The full Desktop journey once at the end, with Sound Lab's lines as new
  milestones.

**Done when** Observatory's plot of Worlds' telemetry goes out as a `PLOT`
over an exact series in the physical viewer, its baseline a vector line;
Sound Lab's frequency landmarks go out as vector lines that move when it
renders new settings; the same widget draws both in CELL; the Desktop
advertises `VECTOR` with a point budget its owner reserves as it needs; and
the full Desktop journey passes with the new milestones.

**Status.** Done on 2026-10-18. The closing runs are recorded in
`local_testing/evidence/part6-desktop-journey-20261018.md`, and the measures
of step 9 in `local_testing/evidence/part6-plot-line-costs-20261018.md`.
Both copies of the contract give vector lines a point budget, and MegaPad's
guest module, codec, scene and server carry it. The data-graphics model
has `PLOT` and `POLYLINE` records, which the canonical widget draws in CELL;
the instrument planner, the rich engine, the APT-1 provider and the hybrid
producer send them within the owner's point quota, and leave a graph to
CELL whole when its terminal cannot draw it. The Desktop profile advertises
`VECTOR`, its point limit and budget derived from Desk's data-graphics bank.
In the physical viewer, Desk with Observatory and Worlds shows Observatory's
plot of its own series, and after Analyze of Worlds' run, as a `PLOT` over
the exact series with its baseline a line, its status and CELL panel showing
the run in the same frame. Desk with Sound Lab shows its frequency landmarks
as three lines, whose pitch mark moves when Sound Lab renders a new
frequency, and CELL draws the same landmarks. The full Desktop journey
checks the landmark lines at Sound Lab's `soundlab-instruments-live` and
`soundlab-rerendered` milestones. The plots and lines themselves cost
little: about 0.1 to 0.3 million guest steps a frame to lower and 0.2 to 0.4
million to draw in CELL. The frames that carry them are STARTs of the whole
screen, 8.5 to 21.5 million steps in the rich producer, since these Desks send
no DELTA, as part 5 found for applications' prompts. Where a rich plot or
waveform leaves its background clear, CELL's drawing of it shows beneath, as
since the series work.

**Not in this part.** `GROUP`. Appending to a live series. Labels and axis
ticks as objects of their own; they stay text. A graph is still left out
whole when one of its records is unsupported, so a terminal without
`VECTOR` shows Sound Lab's and Observatory's instruments in CELL; splitting
a chart into a graph of its own waits for a terminal that needs it. Two
renderer limits the consumers here do not meet, since their lines are
opaque and thin: translucent wide strokes blend twice at joins, and
diagonal strokes draw thinner than asked.

**Found on the way.** A capability handler runs from Desk's request pump
while another application's UIDL context is live, so the UIDL elements it
sets are that application's. Observatory's handler set its status label and
marked its body for repaint that way, so after Analyze its CELL panel kept
the old series under the new plot. It now leaves both to its own tick,
which Desk runs in its context before painting. Handlers in Daybook (agent
run), File Explorer (reveal), Grid (set and save), Pad (open), Sound Lab
(shape, frequency, amplitude, duration, render, play and save) and Streams
(drafts, refreshes and source enabling) still set UIDL elements from there,
and they stay open: each can do as Observatory does, or Desk can run a
handler in its instance's context.

A press can be lost too. The terminal accepts it bound to the frame on
screen, but when the guest replaces that frame with a START before it reads
the press, as when a notice ends, the press names a control the new frame
no longer has, and the guest drops it without a word. One canonical
Desktop run stalled that way: it pressed File Explorer's task while Sound
Lab's render notice showed, the notice ended first, and File Explorer never
took focus. The journey now waits for the notice to end; the dropped press
stays open.

Three faults found on the way are fixed. Worlds' Analyze had never worked
inside Desk: Worlds sent it as a component, and the request bus held a
component's mutating request for an approval Desk never asks for, so Worlds
now sends it as the user's own. Sound Lab's right-aligned `4 kHz` label
wiped its landmark caption in CELL, so it is painted first. And a notice
could end before a rich frame carrying it was revealed: its time started at
the paint, and on the busy Desktop a START took longer than the notice to
be taken. A notice's time now starts when the output that shows it has gone
out.

## 7. Pictures

**Today.** MegaPad's side is complete: immutable raw RGBA8 resources, a
chunked upload checked by a SHA3-256 digest, IMAGE objects with stretch,
contain and cover, and resource quotas that `OWNER_RESIZE` can grow. The
Desktop does not advertise it. Akashic has none of it. Its engine has no
upload or IMAGE operations and never asks for resource quota, nothing shows
a picture file, and UIDL's `<media>` element draws nothing.

The only picture decoder is QOI (`render/qoi.f`). It needs the whole file and
a full surface, does not check the picture's size or its allocations, and
frees its table with `FREE DROP`, which drops a cell of its caller's stack.
File Explorer's preview is a read-only text area. It never looks at what a
file is, so a binary file shows as text, and the text area's fixed 4096-byte
buffer silently cuts the 32 KiB the applet reads.

**Decided on 2026-10-10.**

- Pictures are the first step in turning File Explorer's preview into a media
  viewer: pictures, then documents, then sound, each with its own plan. Video
  is not planned.
- Pages and documents never travel as pictures. They go as styled text that
  the terminal draws.
- One model and one widget serve both CELL and rich.
- The terminal tells the client how many pixels a picture area has, so the
  device never decodes, holds or sends more pixels than the screen can show.
- The 115,200 baud serial speed is a placeholder. Compression, a faster link,
  and uploads that let frames through are chosen from the measurements this
  part records, not assumed now.

**Plan.**

1. **Contract.** First bring Akashic's copies of APT-1-RETAINED-1 and
   APT-1-RETAINED-1-OWNERSHIP back in line with MegaPad's; both lack
   `OWNER_RESIZE`, and that is their only difference. Then add three things
   to both repositories' copies. MegaPad implements them in its codec,
   terminal checks and reference renderer.
   - *How many pixels.* The client asks how many pixels a picture placed in
     a given number of columns and rows would cover on the selected surface.
     The terminal answers with a width and height, or zero when it cannot
     say. The answer holds for the presentation epoch, and the client asks
     again after the geometry changes. It is advice only: the terminal still
     scales whatever it is given.
   - *Backdrop.* An IMAGE flag asks the renderer to paint its own background
     over the object's whole rectangle before the picture. Without it,
     contain's letterbox bars and any transparent pixels show the CELL
     preview underneath, so one picture appears twice.
   - *Giving space back.* Today a reservation never shrinks within an owner
     generation, so one large picture would hold its space for the rest of
     the session, space that other owners of the same terminal may need. An
     owner may lower its resource count and bytes, down to what it is using.
2. **Decoding.** Rewrite the QOI decoder to resume where it stopped. It reads
   file chunks the caller gives it into a state record the caller owns, and
   writes rows in the wire's R, G, B, A byte order. It checks the header and
   the `width * height * 4` arithmetic, fails cleanly on short or corrupt
   data, allocates nothing itself, and has no `FREE DROP`. The whole-file
   `QOI-DECODE` goes; only its test uses it. The encoder stays, for tests and
   the sample picture, with its own `FREE DROP` fixed, in its own module
   (`render/qoi-encode.f`), so a decoder never loads the surface renderer.
3. **Media basics,** in a new `media/` directory below the widgets:
   - *Sources.* A small read-at-offset interface. A VFS file is the first
     kind; fetched bytes, such as Streams images, can be another later.
   - *Kinds.* Recognizes a file from its first bytes, then its name: QOI and
     text (valid UTF-8 with no NUL in its first block), and PNG, JPEG, GIF,
     BMP, WAV and HTML without decoding them, so the preview can say what a
     file is even before it can show it.
   - *Picture model.* Holds a source and makes scaled copies on request: the
     picture at no more than a given width and height, keeping its shape,
     never enlarged, and scaled down by averaging while it decodes. Each copy
     records its size, byte length and SHA3-256 digest, computed in the same
     pass. Its storage comes from the caller's memory source and fits that
     copy exactly. The work runs in bounded slices from the app shell's
     per-pass service, driven by the UIDL host rather than by each applet, so
     Desk stays responsive. A copy is pending, ready, or failed with a reason.
4. **Widgets and UIDL.**
   - *Picture widget* (`tui/widgets/picture.f`). Holds a picture model and a
     text alternative, and fits the picture inside its area, centred. In CELL
     it asks for a copy two pixels per cell high and draws it with upper-half
     blocks, mapping each pixel with `TUI-RESOLVE-COLOR`. While the picture
     loads, when it cannot be shown, or when the area is too small, it shows
     a labelled placeholder that gives the reason. It publishes a neutral
     snapshot: its rectangle, fit and text, the picture's identity, and a
     copy source the rich side can ask for its own size.
   - *Media widget* (`tui/widgets/media.f`), which UIDL-TUI makes from
     `<media>`. Given a source, it shows the matching view through
     `WDG-DRAW-IN`: the picture widget for pictures, the canonical text area
     for text, and a short facts view (name, size and kind) for anything
     else. Focus and keys go to the view shown. The text area's
     buffer is sized to the file from the caller's memory; if that memory is
     refused, the view says so instead of cutting the text. Because each view
     is a canonical widget drawn the ordinary way, the text area keeps its
     rich path and only the picture is new. An authored `<media>` with a
     visual `<rep src=...>` and a text `<rep>` uses the same path, for later
     uses such as app icons and Streams images.
5. **Rich path.**
   - *Engine.* Resource upload (begin, chunk, commit, drop and abort, paced
     by credit) over MegaPad's `PT-RESOURCE-*` words, as the provider's one
     job at a time; IMAGE as a kind of static in the neutral static
     envelope, defined and replaced with the other statics; the pixel
     question; and resource quotas in limits, needs and resize.
   - *Capture.* UIDL-TUI observes the `<media>` elements that show a picture
     directly, and a picture snapshot beside the data-graphics one describes
     them. Each picture carries a revision, new with every source the
     widget is given, so the rich side can tell a new size of the same
     picture from a different picture.
   - *Producer.* The picture claims its widget rectangle and lowers to one
     IMAGE with the backdrop flag. A newly shown picture goes out first as
     its CELL preview. The producer asks the terminal how many pixels the
     whole surface has, asks each picture for a copy of the pixels its
     rectangle covers, and once the copy is ready it uploads it; the next
     frame adds the IMAGE. No frame can be sent during an upload, so the
     screen waits; step 8 measures how long. A copy already on the terminal
     is reused while anything refers to it. A replacement follows
     [AKASHIC-RICH-TERMINAL.md](AKASHIC-RICH-TERMINAL.md) section 5.4: a new
     ID, the upload while the old copy still shows, the swapped reference,
     then the old resource dropped. An upload whose picture no longer shows,
     because its source changed or its document went, is stopped.
   - *Space.* The producer asks for exactly the resource count and bytes it
     needs, including the overlap during a replacement, and gives space back
     when a picture goes. If the terminal says no, the producer fits a
     smaller copy into the space it already holds, since a smaller picture is
     still the whole picture. If it holds none, the picture stays CELL and
     the fallback record says why. It never crops to fit, and a refused
     picture never strips another family.
6. **File Explorer.** `<media id=preview>` replaces the preview text area.
   Selecting a file gives the media widget a source, instead of reading bytes
   into the applet's 32 KiB buffer, which goes. Nothing decodes while the
   Preview tab is hidden, because the widget only asks for copies when it is
   drawn. Ctrl+O still opens every file in Pad; opening by kind waits for a
   viewer applet and Desk's routing by media type.
7. **Sample picture.** The Desktop disk gains a small QOI picture, made and
   encoded in Python when the disk is built, like the other sample files.
8. **Measure.** Record guest steps for decoding, scaled copies, digests and
   the CELL draw; the bytes uploaded; and how long the screen waits during an
   upload. These numbers decide whether compression, a faster link or uploads
   that let frames through come next.

**Checks,** in order:

- Decoder: exact pixels against a Python reference on generated pictures,
  short and corrupt files, huge declared sizes, resumed decoding against one
  pass, and a balanced stack.
- Model: scaled copies against a Python averaging reference, digests against
  Python's SHA3-256, and memory taken only from the caller.
- Widgets: CELL byte oracles for the block preview, letterboxing, every
  placeholder and the facts view, then File Explorer's own tests and
  standalone smoke. From here every terminal shows the CELL preview.
- Rich: engine and producer tests for a missing capability, refused space,
  the smaller-copy path, replacement, abort and unchanged CELL output, and
  off-screen compositor checks.
- Desk with only File Explorer through the physical viewer: select the
  picture and see it rich, switch tabs and back, select a text file and then
  the picture again, and repeat once with a terminal that refuses the space.
- Advertise the image bit in the Desktop profile, then run the full Desktop
  journey once as regression.

**Done when** the Desktop journey selects the sample picture in File Explorer
and its Preview shows the picture rich in the physical viewer, CELL shows the
block preview on its own, and a terminal that lacks the feature or refuses
the space leaves the CELL preview with the reason recorded.

**Status.** The "done when" was met on 2026-10-10, but for one physical run:
with a terminal that refuses the space. The runs and step 8's measurements
are recorded in `local_testing/evidence/pictures-journey-20261010.md`. The
Desktop journey, now 55 stages, selects sunset.qoi in File Explorer and
shows its Preview rich over its CELL half blocks. The picture stays shown to
the end, and the final CELL frame shows the half blocks on their own. Desk
with only File Explorer shows the picture rich three times, around tab
switches and a text file's preview. A terminal that refuses the space, one
the picture would need more of than it offers, and one that takes no
pictures each leave the CELL preview with the reason recorded; the producer
tests prove all three. The hosted Desktop terminal never refuses its one
owner a request within its advertised limits, so that run needs a way to
make the terminal refuse; it is held off for now by choice. The runs also
found a text area defect, since fixed: drawn behind a hidden tab, it
scrolled to the caret against an empty viewport, so File Explorer's text
preview showed blank rows.

The measurements say the pause matters most: while an upload is open the
terminal takes no frame, so the whole screen waits for every upload's bytes,
at any link speed. On the device, the SHA3-256 digest is three quarters of a
rich copy's steps, and the CELL copy computes one nothing reads.

**Not in this part.** Reset, resize and reconnect, which stay open
qualifications for every family. PNG, the next picture format, which needs an
inflater, and JPEG. Zoom and pan, which ask for a new scaled copy of part of
the picture. Compression and a faster link, which the measurements leave for
later; uploads that let frames through are part 8. A viewer applet and opening
files by kind. Documents and sound in the media widget. Animated pictures. An
e-paper look for pictures, which belongs to that terminal's sink. A read-only
text area: the text view's text, like today's preview, can be edited in place,
though nothing writes the file. The colour cube snap's defect for components
48 to 63 ([color.md](../tui/color.md)), which darkens some CELL pictures.

## 8. Frames during uploads

**Today.** A picture upload stops the whole screen. RETAINED-1 allows one
upload at a time and no transaction beside it (its section 8), so from
`RESOURCE_BEGIN` to `RESOURCE_COMMIT` no frame, rich or CELL, can go out.
MegaPad's terminal treats a transaction begun during an upload as fatal, its
guest module answers WOULD-BLOCK, and Akashic's engine and screen producer
wait for the upload as well. Every frame therefore waits for the whole
upload, whatever the link's speed. The sample picture is 64 KB on the wire,
and a picture filling a preview can be 11.5 MB. A chunk may also be as large
as a frame's payload, 917,576 bytes on the Desktop, so a frame let through
between chunks could still wait behind most of a picture.

**Decided on 2026-10-11.** An upload never freezes the screen. Frames keep
going while a picture uploads, and the picture shows CELL, or its older copy,
until the terminal holds the new one.

**Plan.**

1. **Contract,** in both copies of APT-1-RETAINED-1:
   - *Frames between chunks.* An open upload no longer excludes
     transactions. Between the upload's frames, that is after BEGIN's
     result, after each chunk's covering CREDIT and before COMMIT, the client
     may run complete CELL and PRESENT transactions. Resource frames still go
     only outside a transaction and with no TX_RESULT outstanding, so a chunk
     never lands inside a frame. Owner requests, RESOURCE_DROP, the pixel
     question and a second upload still wait for the upload to end. A frame
     can show only committed resources, as today, so it never names the one
     uploading.
   - *Chunk size.* A frame then waits behind at most one chunk. The terminal
     sets `max_resource_chunk_bytes` so that one chunk crosses its own link
     in about a frame's time, since it knows its link and the client does
     not. The client sends chunks of that size.
   - *Reset.* When a soft reset finds a transaction and an upload both open,
     the transaction ends under the base rule first and the upload is
     aborted after it, because resource frames never go inside a
     transaction.
2. **MegaPad.** The terminal accepts CELL and PRESENT transactions while an
   upload is open, still refuses resource frames inside a transaction, and
   follows the new reset order. The guest module's `PT-TX-BEGIN` and
   `PT-PRESENT-BEGIN` stop answering WOULD-BLOCK for an open upload. The
   hosted terminal gains an option to pace its link at a chosen rate, so a
   physical run can see frames pass during an upload; unpaced, an upload
   ends within milliseconds.
3. **Akashic engine.** A CELL or retained update may begin while an upload
   job sits between frames, and the job's next frame waits while an update
   is open or its result is outstanding. When a frame and a chunk are both
   ready they take turns, so neither the screen nor the upload stalls the
   other. The job's coherence rules change to match.
4. **Akashic producer.** `RTHP-PREPARE` stops waiting for an upload. It still
   waits for the pixel question and a drop, each one short exchange. The
   lane keeps one job at a time, its stale-upload check still runs once a
   draw, and the frame after the commit shows the picture.

**Checks,** in order:

- Terminal and guest module: a transaction between chunks is accepted, a
  chunk inside a transaction is refused, transaction begins succeed with an
  upload open, and a reset with both open follows the new order.
- Engine: updates begin between an upload's frames, job frames wait for an
  open update, and the two take turns when both are ready.
- Producer: frames are prepared during an upload, and the IMAGE follows the
  commit.
- Desk with only File Explorer on a paced link: the terminal's frame log
  shows frames between the sample's chunks, and an input sent during the
  upload is answered before the picture arrives.
- The full Desktop journey once, as regression.

**Done when** no frame waits for a whole upload: on the physical viewer the
screen keeps answering input while a picture uploads, and the picture
appears once its upload commits.

**Not in this part.** Choosing chunk sizes from the device side by measuring
the link. Drops and pixel questions alongside an upload. Compression and a
faster link, which bring a picture sooner but no longer hold up the screen.

**Status.** Done on 2026-10-11. The runs are recorded in
`local_testing/evidence/frames-during-uploads-20261011.md`. On a link paced
to 100,000 bytes a second, with 100-byte chunks, Desk with only File Explorer
answered an input sent while the sample uploaded. The terminal committed the
answering frame with 124 of the sample's 640 chunks taken and the upload
still open, and the picture appeared once the upload committed. The full
Desktop journey passed as regression.

The first paced run failed. A refused update sent the producer down a full
rebuild beside the upload, and the guest then closed its session with the
upload open. Now the engine's step that takes an update's answer sends the
upload's next frame, and the producer prepares no frame while one of the
upload's frames awaits its answer.

Two defects stay open. The guest module's PT-CLOSE does not abort an open
upload before CLOSE, so a teardown during an upload fails the session. A
frame that needs more room during an upload records a terminal refusal as
its reason.

## 9. Pictures the terminal decodes

**Today.** The terminal takes one picture format, raw RGBA8 (RETAINED-1
section 8), so the guest does all the picture work. It decodes the file,
scales it to the area, hashes the copy with SHA3-256 and sends the raw pixels;
the terminal only draws them. The photo check (`--applet photo`: Desk with
File Explorer and a 2160 by 1620 photograph) passes. The terminal shows a
2145 by 1609 copy in the 2145 by 1638 preview, one pixel per pixel. But on
the simulator, from opening the Preview:

- the CELL view came after 43 s,
- the rich copy was ready after 174 s,
- and its upload took 47 s more, 3.7 minutes in all.

In guest steps the photo costs about 6.6 billion. The QOI decode takes 524
steps a pixel, 1.8 billion for the file. The rich copy takes 4.2 billion, of
which the digest is 1.4 billion. The CELL copy takes 2.3 billion, because it
decodes the whole file again. The link carried 13.8 MB of raw pixels for an
8.1 MB file. The upload's 47 s is a host cost: the guest ran only 87 million
steps in that time, so the hosted terminal took the bytes at about 300 KB a
second.

The CELL view is coarse by nature: half blocks, two dots a cell, in the 256
xterm colours. The viewer draws the block characters from its font, which
leaves thin gaps between them.

**Decided on 2026-10-11.** The terminal decodes pictures natively. A picture
travels as its file's bytes, and the guest neither decodes nor scales it for
the rich terminal. While the terminal shows a picture, the guest makes no
CELL copy of it. It makes one only when CELL is what shows the picture, and
then decodes the file once. Resources lose their SHA3-256 digest: every frame
already carries a CRC32C and chunks are checked for order and length, an
unsigned digest does not stop anyone who can change frames, and pictures are
known by their document, element and revision.

**Plan.**

1. **Contract,** in both copies of APT-1-RETAINED-1:
   - `RET_FORMATS`' `image_format` becomes the set of picture formats the
     terminal decodes: raw RGBA8 as today, and QOI, PNG and JPEG files.
   - `RESOURCE_BEGIN` names one of them, the picture's width and height, and
     the bytes it sends: width times height times four for raw pixels, the
     file's length otherwise. It carries no digest. The owner's resource
     bytes count the decoded picture, width times height times four,
     whatever the format, since that is what the terminal holds.
   - At COMMIT the terminal decodes the file. One that does not decode, or
     decodes to another size, fails with RET_BAD_CONTENT and destroys the
     upload, so no commit leaves a picture uncertain.
   - IMAGE objects do not change. The terminal fits each picture into its
     rectangle and scales it smoothly.
2. **MegaPad.** The hosted terminal decodes the three file formats with a
   native library and advertises them. The guest module carries the format
   and the file's length in RESOURCE_BEGIN. The viewer scales pictures
   smoothly, and draws block characters as exact rectangles, so CELL pictures
   have no gaps. The hosted terminal's 300 KB a second for uploads is found
   and removed; that gain is host-only.
3. **Akashic engine.** An upload names its format and sends a file's bytes
   as they are; raw pixels stay for terminals that decode no format the file
   uses. Uploads carry no digest. The limits snapshot carries the formats the
   terminal decodes.
4. **Akashic producer and picture widget.**
   - When the terminal decodes a picture's format, the producer sends the
     file from the widget's source. It makes no copy, asks no pixel question
     and needs no scaling. The picture's identity is its document, element and
     revision, as the lane already keeps.
   - While the picture shows rich, the widget's CELL view shows a placeholder
     beneath it, with the picture's name and size, and decodes nothing. Once
     CELL is what shows the picture, the widget makes its CELL copy.
   - A terminal that decodes no format the picture uses still gets today's
     raw copy at the area's size. Both copies then come from one decode, and
     no copy is hashed.
   - File Explorer previews PNG and JPEG files on a rich terminal that
     decodes them. CELL shows their facts until the guest can decode them.

**Checks,** in order:

- Contract: conformance vectors for each format, a file that does not
  decode, one that decodes to another size, and the decoded-size charge.
- Terminal and guest module: uploads in each format, refusals, smooth
  scaling, and exact block characters in off-screen compositor checks.
- Engine and producer: a file sent as it is when its format is advertised,
  the raw copy otherwise, no CELL decode while a picture shows rich, and one
  CELL copy, from one decode, once CELL shows it.
- Guest steps for the photo before and after, against today's 6.6 billion.
- The photo check and File Explorer's check through the physical viewer,
  then the full Desktop journey once, as regression.

**Done when** the photo check shows the photograph rich and sharp within
seconds of opening its Preview on the simulator, the guest decodes nothing
for it, and CELL shows a picture only when CELL is what the screen shows.

**Not in this part.** Decoding PNG and JPEG on the guest, for CELL. Making
copies at the area's size of very large files to save link bytes; they go as
they are while within the terminal's limits. Animated pictures.

**Status.** Done on 2026-10-11. The runs are recorded in
`local_testing/evidence/pictures-terminal-decodes-20261011.md`, against the
baseline in `local_testing/evidence/photo-check-20261011.md`. The terminal
decodes QOI, PNG and JPEG files, and the producer sends a picture's file as
it is when the terminal decodes its format. While the rich side shows a
picture, its CELL view says what the picture is and decodes nothing; the
CELL copy is made only once CELL shows the picture. The photo check passed
in 56.5 s instead of 279.4 s. The photograph showed sharp and in full colour
6.9 s after its Preview opened, instead of 223.5 s, after 0.27 billion guest
steps instead of 7.5 billion. File Explorer's check and the full Desktop
journey passed as regression.

The first run after the guest work moved still took 18 s, all of it host
time. The simulator's TYPE wrote one byte per call, Pillow's QOI decoder
read one byte per call, and the guest module fed each frame's CRC one cell
per call. Each now works in bulk. These gains are host-only.

Four defects stay open. A file the terminal refuses as damaged is sent
again on each newer draw. A picture whose cells another root claims can
show its label in CELL while nothing rich shows it. The file pull reads the
whole file into staging at once. Claims stay through a soft reset until the
producer rebuilds. Part 11 fixed the first and the third.

## 10. Screen changes that cost what they change

**Today.** Opening File Explorer's Preview in the photo check, until the
photograph shows, costs about 270 million guest steps
(`local_testing/evidence/tab-change-profile-20261011.md`). Desk and File
Explorer's drawing is 7.5% of that. The rest is publishing what they drew:

- Each changed cell passes through four layers (APTSCB, RTAPTSCB, RTAPT and
  PT), and the publisher, the span's memory, the engine's storage layout and
  its cell counts are checked again for every cell: 30% of the steps.
  Publishing costs about 1,500 to 2,100 steps a cell.
- Two of the change's five PRESENT transactions send the whole 280 by 84
  screen, 23,520 cells, where at most the preview changed. One replaces
  "Loading the picture" with the picture's label. The other changes nothing in
  CELL at all: the APT adapter promotes a retained-only request to a complete
  CELL snapshot.
- Each rich frame scans the whole screen twice for residual glyphs, once in
  the hybrid producer and once in Desk's shell producer: 24% of the steps.

Typing, scrolling and menus pay the same costs. On a 2 GHz chip at one to two
clocks an instruction, the tab change's guest work alone would take 0.13 to
0.27 s, up to half of the 0.5 s an e-paper panel that refreshes twice a second
allows. At the 100 MHz FPGA target it would take about 10 s.

**Decided on 2026-10-11.** The guest's cost per screen change is cut. A
speed-up removes only work it proves redundant, and says how.

**Plan.**

1. **Measure.** The two measurements behind this part become tools: a guest
   word profile over a window of a physical run, and a record of what each
   PRESENT carries in the performance trace. Both are host-side and change
   nothing the guest or the terminal does.
2. **Send only what changed.** A retained-only change sends a PRESENT with no
   CELL cells, as RETAINED-1 already allows, once the screen shows its CELL
   plane is unchanged. A redraw sends a delta of the cells that changed.
   Complete snapshots stay for a new session, a reset, a resize and a
   terminal's request. Why the adapter promotes a retained-only request to a
   snapshot is established first; whatever it protects keeps its own check.
3. **A picture's first draw is its last.** When the rich side takes pictures
   of a file's format, the picture widget draws what the picture is from its
   first draw, not "Loading the picture" and then its label. The capture's
   claim still decides: a picture the rich side does not take after all is
   drawn from its CELL copy at the next pass.
4. **Check once a span, write in bulk.** Each layer of the CELL path checks
   its state once for a span and writes the span's cells in one pass, where it
   shows that nothing it checks can change within the span. A check that can
   change stays per cell.
5. **Scan only what changed.** The residual glyph planners scan only the rows
   a draw changed, and the hybrid producer and Desk's shell producer share one
   scan.

No contract changes: PRESENT already carries retained-only changes and CELL
deltas.

**Checks,** in order:

- For each step, unit and byte-oracle checks: a retained-only change
  publishes no CELL cell; a redraw publishes exactly the cells that changed;
  complete snapshots still follow a new session, a reset, a resize and a
  terminal's request; a failing check still refuses before any cell is
  written; and limited or shared scans give exactly the frames full scans
  give.
- The photo check and File Explorer's check, measured with the two tools
  against `tab-change-profile-20261011.md`.
- Typing cadence (`local_testing/physical_typing_cadence.py`), and typing's
  guest steps a key with the profile, before and after.
- The full Desktop journey once, as regression.

**Done when** opening the photo's Preview, until the photograph shows, costs
at most 100 million guest steps, and no PRESENT carries a CELL cell that did
not change, apart from the complete snapshots above.

**Not in this part.**

- A picture's first appearance as a retained delta rather than a complete
  replacement.
- Native code for the hosted terminal's CRC-32C and QOI decoding and the
  simulator's CRC model. That is host-only, about 3 s of the photo's 7 s
  today.
- Smaller copies of large picture files for small previews.

**Status.** Done on 2026-10-11. The runs are recorded in
`local_testing/evidence/screen-changes-20261011.md`, against the baseline in
`local_testing/evidence/tab-change-profile-20261011.md`. Opening the photo's
Preview, until the photograph shows, costs 88.4 million guest steps instead
of 266.7 million, and its PRESENTs carry only the 15,224 CELL cells that
changed, with no complete snapshot. In the photo check, File Explorer's check
and the full Desktop journey, the only complete CELL snapshot is each
session's first. File Explorer's eight tab changes cost 563 million guest
steps instead of 1,421 million. A retained-only change sends no CELL cell,
a picture's label is drawn right the first time, the CELL feed checks once a
span, Desk's shell producer takes the hybrid producer's glyph runs where its
own claims leave them whole, the hybrid producer plans again only rows whose
claim rectangles came or went, and a rebuild of the same draw keeps its
glyph plan. Typing's guest work a frame is unchanged, about 23 million
steps, and its cadence is within the spread of runs; the full Desktop
journey passed as regression.

## 11. Uploads that read as they send

**Today.** Before an upload begins, the picture lane reads the whole picture
into one staging block from Desk's memory: the file as it is, or the raw copy
the widget already holds, which is then held twice. The engine sends the
block a chunk at a time, and each chunk is copied into its frame as it goes,
so only one chunk ever needs to be in memory. The photo's upload sets aside
its whole 8.1 MB file. The largest picture the rich side can show is bounded
by the memory Desk can find for one file, not by what the terminal holds.

When the terminal refuses a file as damaged, the upload fails, every picture
goes back to CELL, and each newer draw sends the same file again, whole.
These are two of the four defects part 9 left open.

**Decided on 2026-10-11.** Pictures come before documents. A PDF can hold
many pictures, some large, inside one big file, and a damaged one must not be
sent again and again. PDFs follow in their own part, as a reading view: the
text reflowed with its meanings, and the document's pictures in place. The
terminal does not become a page renderer. The PDF part also improves UIDL and
the rich terminal in general: each problem a PDF raises is solved with an
ordinary element that other applications can use too.

**Plan.**

1. **Engine.** An upload names its picture and its length, but takes no
   bytes. Once the terminal has begun it, the job waits for each chunk in a
   new state, WANTS, and says where the chunk starts and the most it may
   carry: the terminal's chunk limit, within one frame. The caller reads that
   much and hands it over with `RTE-RESOURCE-FEED`, and the next frame sends
   it. The caller may reuse its block once the job asks again or ends. An
   upload waiting for a chunk is cancelled like one waiting to send. When the
   terminal refuses an upload's bytes (`RET_BAD_CONTENT`), the job's outcome
   says so, as `RTE-S-SOURCE`, rather than INVALID.
2. **Producer.** For each upload the lane takes one block from Desk's memory,
   the size of its largest chunk, and gives it back when the upload ends. As
   the job asks, the lane reads each chunk into the block from the picture's
   source: `UPICSN-PULL` and `RUHA-PICTURE-PULL` read at an offset. A raw
   copy is read the same way from the widget's copy, so it is held once. Each
   read also checks that the element still shows that picture, so an upload
   whose picture went stops before its next chunk, and the separate check
   once a draw (`RUHA-PICTURE-SHOWS?`) goes.
3. **Refusals.** When the rich side cannot send a picture because of the
   picture itself, its widget remembers why until it is given another
   source: the terminal refused the bytes as damaged, or they could not be
   read. The picture is then described as failed, so the rich side neither
   takes nor sends it, and CELL shows it: from its CELL copy for QOI, and
   otherwise with the reason, "The picture is damaged" or "The picture could
   not be read". Other pictures stay rich. A failure that is not the
   picture's, such as the terminal's room or Desk's memory, is handled as
   today.
4. **Measure.** The guest steps of the photo's Preview until the photograph
   shows, against part 10's 88.4 million, and the largest block the lane
   takes.

No contract changes: the wire already carries an upload a chunk at a time,
and `RET_BAD_CONTENT` already says the terminal refused the bytes.

**Checks,** in order:

- Engine: an upload asks for each chunk in turn and sends exactly what it is
  given; a chunk given out of turn, too long, or overlapping the engine's
  storage is refused; cancelling an upload that waits for a chunk aborts it;
  and a refused COMMIT reports SOURCE.
- Producer: a file goes in chunks, byte for byte; the lane's block is its
  largest chunk; a picture that goes between chunks stops its upload; a
  refused file is sent once, CELL gives the reason, other pictures stay rich,
  and a new source tries again.
- Widget: CELL byte oracles for each reason.
- Desk with File Explorer through the physical viewer: the photo check, File
  Explorer's check, and a damaged picture file on the disk, which the
  terminal is sent once while CELL says why and the screen keeps answering
  input. Then the full Desktop journey once, as regression.

**Done when** an upload holds at most one chunk of its picture in the guest's
memory, the photo's Preview shows the photograph within 90 million guest
steps, and a picture the terminal refuses is sent once and shows CELL with
the reason while other pictures stay rich.

**Not in this part.** Part 9's other two defects: a picture whose cells
another root claims shows its label with nothing rich, and claims stay
through a soft reset. Part 8's two: PT-CLOSE does not abort an open upload,
and a frame that needs more room during an upload records a terminal refusal.
A picture inside a larger file, such as a PDF's, which the PDF part brings
with a source for a span of another source. Smaller copies of large picture
files for small previews.

**Status.** Done on 2026-10-11. The runs are recorded in
`local_testing/evidence/uploads-read-as-they-send-20261011.md`. The engine
asks for each chunk of an upload in turn, and the lane reads it from the
picture's source into one block the size of the terminal's chunk: the
photo's 8.1 MB file went in nine chunks from one 917,576-byte block, and its
Preview showed the photograph after 88.5 million guest steps, against part
10's 88.4 million. A picture the terminal refuses is remembered by its
widget. In the new damaged-picture check (`--applet damaged`), damaged.png
went to the terminal once, CELL said "The picture is damaged", and the
Preview shown again sent nothing more; the producer tests show the other
pictures staying rich. File Explorer's check and the full Desktop journey
passed as regression.

The damaged-picture check's first run found a defect, since fixed: the
engine step that took the terminal's refusal left the engine's own status at
REJECTED, and the frame prepared right after took it as INVALID. A job's
outcome is now the job's alone.

## 12. Documents

**Today.** File Explorer's preview shows a Markdown file as its source, in
the media widget's text view: a plain text area with one line of the file
on each row, no styling and no wrapping, which can even be edited in place,
though nothing saves it. Nothing in Akashic reads a document's structure.
Pad colours Markdown source line by line (`text/syntax.f`), and
`markup/readable-text.f` flattens HTML to plain text.

The rich terminal has nothing for a document either. Text areas show one
line per row and never wrap; only cards wrap text. No family carries
headings, paragraphs that reflow to the width, lists, quotes, code blocks or
pictures among the text. Only text areas follow links. A `<media>` element
shows one picture, and shows it rich only while its whole rectangle is on
the surface.

**Decided on 2026-10-11.**

- PDFs come in three parts: documents (this part), decompression (13) and
  the PDF reader (14). Each problem a PDF raises is solved by an element any
  application can use:

  | A PDF needs | The general element | Part |
  |---|---|---|
  | its text reflowed, with its structure | the document view | 12 |
  | pictures among its text | figures: several pictures in one element, shown in part when scrolled | 12 |
  | many pages | documents read and sent only as far as the view reaches | 12 |
  | links within it | links to a document's own headings | 12 |
  | compressed streams | an inflater, which also gives CELL its PNG pictures | 13 |
  | pictures inside the file | a source for a span of another source | 14 |
  | an outline | a document's outline as a tree of its headings | 14 |
  | encryption | MD5 and RC4 beside the AES Akashic has | 14 |

- A document is one general element: blocks (headings, paragraphs, list
  items, quotes, code, rules and figures) with part 3's inline meanings and
  links. Any source can make one and any application can show one. Markdown
  is the first source.
- Headings stay on the cell grid. Weight, colour and spacing set them apart,
  not larger text, as part 3 decided for text areas.
- The terminal breaks a document's lines and draws them in its own fonts and
  looks. Both sides break lines by APT-1-TEXT's rule, so they agree on every
  row, as they do for cards, and the client stays in charge of scrolling.
- The client sends only the blocks the view shows, so a long document costs
  the terminal only what is on screen. The client's model keeps a document's
  structure, and reads a block's text from the file only when the view
  reaches it.

**Plan.**

1. **Contract,** in MegaPad's SEMANTIC-CONTENT-1, both copies of
   APT-1-RETAINED-1, and APT-1-TEXT for code lines:
   - *The kind.* A new CONTROL kind, `DOCUMENT`, with its own body, `DOC1`,
     behind feature bit 16, `RET_CONTROL_DOCUMENTS`, which needs bit 9.
   - *Blocks.* DOC1 carries the blocks the viewport shows, in order. Each has
     a stable key, its kind (a paragraph, a heading and its level, a code
     block, a rule or a figure), the lists and quotes it sits in, and its
     text with style runs. A viewport row says how many rows of the first
     block are scrolled out, as in cards.
   - *Exact rows.* A block's indent comes from the lists and quotes around
     it. Its text breaks by Section 12 at the width left; code breaks only
     where a line reaches that width, by a new rule in Section 12; and the
     blank rows between blocks are given. The renderer chooses the look
     within those cells: list marks, quote bars, rules, a heading's look and
     a code block's background.
   - *Figures.* A figure block takes the rows the client gives its picture,
     then its caption's lines. The renderer leaves the picture's rows
     unpainted, so they show the picture's `IMAGE` when the terminal holds
     the picture, and the CELL view beneath otherwise. An `IMAGE` may lie
     partly outside the document's rectangle and is clipped to it, so a
     figure scrolled partly out of view shows the part in view.
   - *Input.* `SCROLL` works on documents, and `FOLLOW` names a position on
     a link in a document as in a text area. Documents are read-only, so a
     plain press on a link follows it.
2. **Document model** (`media/document.f`). A document is a sequence of
   blocks, each with a stable key, which a reader finds in a media source.
   The reader finds the document's structure in one pass over the source,
   keeping each block's kind, its lists and quotes, and where its text lies.
   A block's text and inline meanings are read from the source only when a
   view reaches the block, and kept while the block stays near the view.
   Headings have anchors, so a link can name one. Memory comes from the
   caller's memory source, sized to what it holds; when it is refused, the
   view says so. Library is the design check: its documents arrive in
   chunks, so a media source must be able to stand for them.
3. **Markdown** (`markup/markdown.f`), the first reader. It follows
   CommonMark for headings, paragraphs, block quotes, lists, code, thematic
   breaks, emphasis, strong emphasis, code spans, links, link reference
   definitions, pictures, autolinks, line breaks, backslash escapes and
   entities. Raw HTML shows as its text. A GitHub table shows as its lines,
   unbroken, as code does.
4. **Document view** (`tui/widgets/document.f`), the canonical widget. CELL
   draws each block with the style palette's looks, with list marks, quote
   bars, rules and code backgrounds, and each figure through a picture
   widget: a CELL copy for QOI, and the picture's facts otherwise. The keys
   and the wheel scroll it, and a press on a link follows it. It keeps each
   block's line count at its width, so a scroll lays out only the blocks
   that come into view. It publishes a neutral `DOCUMENT` entry with the
   viewport's blocks, and its figures' pictures to the picture snapshot.
5. **Media widget.** A Markdown file shows as a document: `MEDIA-KIND` calls
   text whose name ends in `.md` or `.markdown` `MEDIA-K-MARKDOWN`. An
   authored `<media>` whose `src` is a Markdown file shows the same way, so
   any application can show a document.
6. **Links.** The document view follows a link to one of its own headings
   itself. A relative path is resolved from the document's folder by the
   rule Pad uses today, which moves below the applets so that both share it.
   A target with a scheme, such as `https:`, is refused with a message. The
   application decides what a file link does: File Explorer selects the file
   it names, in its folder, and previews it.
7. **Rich path.** UIDL-TUI observes document views, and the collection
   snapshot captures their `DOCUMENT` entries, which the producer lowers to
   a `DOCUMENT` control with claims, refusal and CELL fallback, as item
   views have. For figures, the picture snapshot describes several pictures
   in one element, one for each figure in view, keyed by its block, and the
   producer shows a picture whose rectangle lies partly outside the
   document's, clipped to it.
8. **MegaPad.** The codec, the scene and terminal checks, the guest module's
   CONTROL writer, the reference renderer and its hit map, the viewer's
   routing, and the shared-viewer transport.
9. **Sample.** The Desktop disk gains a sample Markdown document with every
   block kind, a link to one of its headings, a link to another file, and
   sunset.qoi as a figure, long enough to scroll.
10. **Measure.** Guest steps for opening the sample, drawing it, a scroll
    step and following a link, in CELL and rich, and the bytes a scroll step
    sends.

**Checks,** in order:

- Markdown: blocks and inline meanings against the CommonMark reference
  parser, commonmark.js 0.30, on handwritten and random documents recorded
  as fixtures, and GitHub tables against markdown-it-py; short and odd
  input; a balanced stack; memory taken only from the caller.
- Lines: Akashic's and MegaPad's rows for the same documents agree row for
  row, on fixed and random documents.
- Document view: CELL byte oracles for each block kind, lists in quotes,
  right-to-left paragraphs, figures, scrolling and each kind of link; then
  File Explorer's own tests and standalone smoke.
- Contract: codec vectors and refusals, the terminal's checks, off-screen
  compositor checks of the reference renderer, and `SCROLL` and `FOLLOW`
  from its hit map.
- Producer: capture and lowering, refusal leaving CELL, unchanged CELL
  output, and figures several to an element and clipped.
- Desk with File Explorer through the physical viewer: preview the sample
  rich, scroll it with the wheel, see the figure rich and then partly
  scrolled out, and follow the heading link and the file link. Then the full
  Desktop journey once, with a new milestone: it previews the sample
  document rich.

**Done when** File Explorer previews a Markdown file as a document in CELL
and rich, with wrapped paragraphs, headings, lists, quotes, code and a
picture in the flow; the wheel scrolls it; following a link goes to its
heading or selects its file; and the terminal holds only the blocks in view.

**Not in this part.** HTML as a document, where `readable-text.f` could
become a second reader. Tables as tables. Moving between links with the
keyboard, since Tab moves focus between widgets. An outline, which part 14
brings, search, and selecting text. PNG and JPEG figures in CELL, which show
their facts until the guest can decode them, PNG after part 13. Larger
headings. Pad keeps showing Markdown as its source, since Pad edits it.

**Status.** Done on 2026-10-12. The runs are recorded in
`local_testing/evidence/documents-journey-20261012.md`. File Explorer
previews the sample guide as one DOCUMENT, in CELL and rich, with wrapped
paragraphs, headings, lists, quotes, code and sunset.qoi as a figure in the
flow. The terminal shows the figure as an IMAGE in the picture rows the
document leaves it, and only the part in view when it is scrolled partly
out. The wheel scrolls the guide, its link to its first heading scrolls
back, and its link to notes.md selects that file and previews it. DOC1
carries only the blocks in view. Desk with only File Explorer passed, then
the full Desktop journey, which previews the guide with its figure rich.

Step 10's counts: opening the guide takes 0.24 million guest steps.
Drawing it at File Explorer's full-screen size, 195 by 78 cells, takes 6.4
million while the rich side shows the figure, and 46 million for CELL alone,
which draws the figure in half blocks. A scroll step's draw takes 6.2 to 6.5
million rich and 15 to 17 million in CELL. The rich side's capture and DOC1
take 0.35 to 0.85 million a frame. A scroll step with the figure in view
sends 57 to 60 KB.

The first physical run stopped at the frame with the figure partly scrolled
out: MegaPad's shared-viewer transport decoded object offsets as unsigned.
It now carries them signed, as the scene does.

One thing stays open. A figure that moves makes every scroll step a full
replacement, and the step's later wheel turns restart it, so a step sends
about 38 KB of retained frames where a DELTA sent 2 KB or less. The
semantic-collection byte oracle, which needs about 131.6 million steps
since the DOC1 packer joined its closure, now has a 140 million limit; and
the grid-eval and grid-contracts profiles, whose closure needs 135 MP64FS
entries against MegaPad's 128, now link their modules into chunk files, as
the grid profile does, until EXT4 support lifts the limit.

## 13. Decompression

**Today.** Akashic has no inflater. Most of a PDF's text lies in Flate
(zlib) streams. A PNG's pixels are zlib too, so CELL cannot show PNG
pictures. The web clients ask servers for bodies with no compression
(`Accept-Encoding: identity`).

**Plan.**

1. **Adler-32** (`math/adler32.f`), beside the CRCs: `ADLER32-UPDATE
   ( adler a u -- adler' )` continues a sum from its last value, starting
   at 1, so a stream is summed a piece at a time. CRC-32 is already there
   as `CRC32-UPDATE`, on the CRC accelerator.
2. **Inflater** (`utils/inflate.f`), resumable like the QOI decoder. The
   caller owns its record and its window, a power of two up to 32 KB, and
   it allocates nothing. `INFL-INIT` names the wrapper: raw deflate, zlib or
   gzip. `INFL-FEED ( in-a in-u out-a out-u infl -- in-used out-used
   status )` takes whatever input the caller has and fills whatever output
   room it gives, and says whether it wants more input, has filled the
   output, has ended with its sum checked, or found the stream damaged, and
   why. It decodes Huffman codes through lookup tables it builds in its
   record for each block, so a symbol costs a lookup rather than a bit at a
   time. A zlib stream that needs a larger window than the caller gave, or
   a preset dictionary, is refused. Input after the stream's end is left
   for the caller.
3. **PNG** (`render/png.f`), resumable like QOI, with the same statuses,
   so a picture's loop feeds either. It checks each chunk's CRC, takes
   PLTE and tRNS, inflates IDAT across chunks, undoes each row's filter,
   and hands back R, G, B, A rows for every colour type and bit depth,
   sixteen-bit samples by their high byte. The rows' filters are a word of
   their own, since PDF's Flate predictor is the same five filters. The
   caller gives the window and the two rows a filter needs.
4. **Pictures.** `PIC-START` decodes PNG for CELL as it decodes QOI, so
   File Explorer's preview shows PNG pictures in CELL. The rich side is
   unchanged: the terminal decodes PNG itself.
5. **Web clients.** The HTTP resource client, XRPC and the public author
   feed ask for gzip as well as identity, and inflate a gzip body as it
   arrives. The inflated bytes count against the same body limit as before,
   so a small compressed body cannot grow past the caller's bound.
6. **Measure.** Guest steps per output byte for stored, fixed and dynamic
   blocks, and for decoding the sample picture as PNG against QOI.

**Checks,** in order:

- Adler-32 against Python's `zlib.adler32` on fixed and random data, fed
  in pieces.
- The inflater against Python's zlib: every level and strategy, each
  wrapper, empty, tiny, random and highly repetitive data, the longest
  match and farthest distance, stored blocks of 65,535 bytes, fed a byte at
  a time and in random pieces into output of every size down to one byte.
  Damaged streams of each kind are refused with their reason, a cut stream
  never ends, and a wrong sum is refused.
- PNG against Pillow: each colour type and bit depth, each filter, a
  palette with transparency, odd widths, fed in pieces; a damaged CRC, a
  cut IDAT, a missing IEND and an interlaced file each refused.
- Pictures and File Explorer's own tests, then File Explorer's check and
  the damaged-picture check through the physical viewer as regression.
- The web clients' tests with gzip bodies, including one that inflates
  past the body limit.

**Done when** File Explorer's preview shows a PNG picture in CELL, the
inflater agrees with zlib on every check, and the web clients take gzip
bodies.

**Not in this part.** Compressing. Interlaced PNG in CELL, which shows the
picture's facts. Gzip files of several members. Colour profiles and gamma,
which CELL ignores.

**Status.** Done on 2026-10-12. The record is
`local_testing/evidence/decompression-20261012.md`. Adler-32, the inflater
and the PNG decoder agree with zlib and Pillow on every check. Pictures decode
a PNG copy for CELL as they decode QOI, so File Explorer's preview shows a PNG
picture in CELL; the media widget's tests show it, and the physical File
Explorer and damaged-picture checks passed on the final tree. The HTTP
resource client, XRPC and the public author feed ask for gzip. The buffered
exchange inflates a gzip body into the response buffer, which serves as the
inflater's window, so a client carries only the inflater's 3 KB record. The
body as sent and as inflated each count against the caller's limit.

Step 6's counts: the inflater gives a byte of text for 60 guest steps with
dynamic codes, 62 with fixed codes, and 0.1 from a stored block. The sample
picture decodes in 120 steps a pixel from QOI, and from PNG in 146 to 689
depending on its filters; Pillow's PNG takes 613. The first count showed
eight-bit RGBA rows converted a sample at a time; they now go out with one
move.

The staged XRPC drivers cannot run as checked in, because they never load
MegaPad's networking.f. Their new gzip stage passed through a scratch wrapper
that loads it.

## 14. PDFs

**Today.** File Explorer calls a PDF a binary file and shows its name and
size. Nothing in Akashic reads one. Part 12's document model reads a
document's whole structure when it opens, which suits a Markdown file but
not a PDF of hundreds of pages. Part 13 gave the inflater and PNG's five
filters, which a PDF's Flate filter and its predictors use. The rich
terminal already takes JPEG files. Akashic's AES is AES-GCM on MegaPad's
engine, which has no other mode, and Akashic has no MD5 or RC4.

**Decided on 2026-10-11.** A PDF is read as a document through part 12's
view: its text reflowed with its meanings, and its pictures in place. The
terminal does not become a page renderer. PDFs open in File Explorer's
preview first; a reader applet comes later. Many PDFs are encrypted with an
empty password, and those are read too.

**Decided on 2026-10-12,** and reviewed the same day:

- *A document grows as it is read.* A reader may leave parts of a document
  unread, and reads a part's blocks when a view comes near it. A PDF's
  parts are its pages, so opening a long PDF costs its first pages, not
  all of them. A link or an outline entry that names a far page reads that
  page alone; the pages between stay unread until the view reaches them.
  Markdown still reads its structure at once.
- *A page's start is a block.* DOC1 gains a block kind, `PAGE`, whose text
  is the page's label. The renderer marks it as a break, and a link or the
  outline can name a page through it.
- *The outline is a general element.* A document's contents are its
  headings, or the PDF's own outline when it has one. File Explorer's
  preview shows them as a tree, and choosing one scrolls the document to
  it. A Markdown document gets the same tree. Step 9 settled the rest: the
  tree takes the document's place, so a narrow preview loses nothing to
  it; the key c shows it, Enter goes to the chosen entry and shows the
  document, and c or Escape shows the document again; it shows headings
  of levels 1 to 3, and a PDF's outline whole. An entry with entries
  under it starts open unless the document says it starts closed, as a
  PDF's outline may; Right and Left open and close it. A PDF without an
  outline lists its pages, since finding its headings would read every
  page.
- *AES is MegaPad's engine's.* PDF encryption uses AES in CBC mode:
  AESV2 decrypts with AES-128, and AESV3 decrypts with AES-256 after
  deriving its key with AES-128 encryption and SHA-256, SHA-384 and
  SHA-512. MegaPad's AES engine, which has only GCM, gains CBC encryption
  and decryption, so the chip carries AES's inverse cipher too, and the
  BIOS gains SHA-384 beside SHA-512. On 2026-10-12 this was narrowed:
  CBC goes into the emulator and Akashic's driver now, and the RTL AES
  block's rebuild is tracked as its own task, MegaPad's
  `ROADMAP-v1.0.md` item 50.

**Plan.**

1. **Contract,** in MegaPad's SEMANTIC-CONTENT-1: the DOC1 block kind
   `PAGE` (6). Its text is the page's label, laid out as a paragraph's; the
   renderer marks the break in the cells the label leaves. It sits in no
   container. No new feature bit: `RET_CONTROL_DOCUMENTS` covers it.
2. **A growing document** (`media/document.f`). A reader's structure pass
   may give a document in parts, each read when asked: a PDF has a part
   for each page, known when it opens. The document view asks for a part
   when it comes within a screen of it, so a part that is not read takes
   no room until then. Links and the outline name a part, so they can name
   pages not read yet, and following one reads that part alone; Home and
   End read the first and last parts. Markdown gives its blocks at once,
   without parts.
3. **The file** (`pdf/`). A lexer and object parser over a media source,
   reading objects only when asked: cross-reference tables and streams,
   object streams, and incremental updates, newest first. A file whose
   cross-reference is damaged is read by scanning for its objects. Streams
   decode through Flate, with the PNG and TIFF predictors, ASCIIHex,
   ASCII85, LZW and RunLength filters. The page tree gives each page's
   resources and content streams.
4. **Text** (`pdf/font.f`, `pdf/content.f`). Each font maps its codes to
   Unicode: a ToUnicode map first, then a simple font's encoding (Standard,
   WinAnsi, MacRoman or PDFDoc, with Differences, through glyph names), and
   a composite font's Identity encoding with its ToUnicode map. A code with
   no character becomes U+FFFD. The content stream's text operators give
   each run of text with its position, size and font, through form
   XObjects and marked content.
5. **Reading order and structure** (`pdf/layout.f`). A tagged PDF gives
   its blocks from its structure tree: headings, paragraphs, lists, quotes,
   code and figures, with artifacts such as page numbers left out. Without
   tags, a page's runs become lines by position, lines become paragraphs by
   their spacing and indent, and a paragraph whose text is larger or bolder
   than the page's body text becomes a heading. A word split by a hyphen at
   a line's end is joined.
6. **Pictures.** An image drawn on a page becomes a figure where it falls.
   A JPEG goes to the terminal as a file through a new source for a span of
   another source (`media/source.f`), and CELL shows its facts. The guest
   decodes a Flate picture, gray, RGB or indexed, eight bits a sample, for
   CELL, and the terminal takes it as a QOI file the guest writes. Other
   pictures show their facts.
7. **Links and the outline.** A link to a page or a place in the file
   scrolls to it. A link to the web is refused with a message, as part 12
   does. The outline, or the headings when there is none, is the
   document's contents.
8. **Encryption** (`math/md5.f`, `math/rc4.f`, `math/aes.f`,
   `pdf/crypt.f`). The standard security handler with the empty user
   password: revisions 2 to 4 with RC4 of 40 to 128 bits, and AESV2 and
   AESV3 through MegaPad's AES engine in CBC, with SHA-384 for AESV3's
   key. A file that needs a password shows its facts and says so.
9. **File Explorer.** `MEDIA-KIND` calls a file that starts `%PDF-` a PDF,
   and the preview shows it as a document with its contents.
10. **Samples.** The Desktop disk gains PDFs written at image build by a
    deterministic Python writer, as sunset.qoi is: several pages with
    headings, paragraphs, a list, a JPEG photograph and a Flate picture,
    links to a page and to the web, and an outline; a tagged and an
    untagged copy; and an RC4-encrypted copy with the empty password.
11. **Measure.** Guest steps to open a 100-page PDF, show its first page,
    scroll into an unread page, and follow a link, and the memory a
    document holds.

**Checks,** in order:

- MD5 and RC4 against Python's `hashlib` and a reference RC4.
- The lexer and objects on hand-made files; cross-reference tables and
  streams, object streams and incremental updates as qpdf writes them; a
  damaged cross-reference read by scanning.
- Each filter against Python, and the predictors against PNG's filters.
- Text: each standard encoding, Differences, ToUnicode maps and Identity
  fonts against what pdftotext reads from the same files.
- Layout: the tagged and untagged samples give the expected blocks.
- Encryption: qpdf's RC4 revisions, AES-128 and AES-256 read with the
  empty password; a file with a user password refused.
- The document view reads pages as it scrolls, and only those; a link to
  a far page reads that page alone.
- File Explorer's check through the physical viewer, previewing a PDF in
  CELL and rich, then the Desktop journey.

**Done when** File Explorer previews the sample PDF as a document in CELL
and rich: its text reflowed with its headings, paragraphs and lists, each
page's start marked, its JPEG shown rich and its Flate picture in CELL and
rich, its links followed, its contents listed, and its RC4-encrypted copy
read with the empty password; and pages are read only as the view reaches
them, a link to a far page reading that page alone.

**Status (2026-10-12).** Steps 1 to 10 are done: File Explorer previews a
PDF as a document, read a page at a time, with its pictures, links,
contents and page labels, and a link or a contents entry shows the place
its destination names. Step 11 is measured. File Explorer's check
through the physical viewer previews the sample PDF in CELL and rich, and
the Desktop journey passes after it
(`local_testing/evidence/pdf-journey-20261012.md`). AES-encrypted PDFs
open too, and both journeys pass again with the AES reader
(`local_testing/evidence/pdf-aes-regression-20261012.md`). On 2026-10-13
the contents became a tree, each entry open or closed as the document
says; the `fexplorer` smoke and both journeys pass with it, File
Explorer's closing the outline's title entry through the rich side
(`local_testing/evidence/contents-tree-20261013.md`).

- Step 11's counts (`local_testing/measure_pdf.py`), for a 100-page PDF of
  249 KB that xelatex writes with hyperref, shown at File Explorer's
  full-screen size of 195 by 78 cells. Opening it takes 3.3 million steps
  and holds 50 KB, with no page read. Its first page takes 9.1 million to
  read, its fonts with it, and 3.9 million to draw; later pages take 1.1
  to 7.1 million each to read, most about 6.5 million. A draw takes 3.8 to
  8.8 million at this size and 0.8 to 2.3 million at 64 by 36. A scroll of
  a screen takes 17,500 steps and reads the pages it brings within a
  screen, three here. Following the contents' link to the last section,
  the hundredth page, takes 9.1 million, reading the page alone and
  placing it; the view then reads four pages around it as it settles.
  Making the contents of 50 entries takes 2.2 million, and going to the
  middle entry, a page not read, 7.3 million. The document holds 164 KB
  once its first page is read and 313 KB after the link and the pages
  around it, 15 pages read in all; closing gives back every byte.
- The file holds each object stream it decodes until it is closed. This
  file keeps its small objects in four object streams of 10 to 21 KB
  decoded, and while the file layer held one at a time, a walk whose
  objects lay in two streams inflated each again whenever it crossed
  between them, about 1.5 million steps a time: the name tree's nodes
  and the page tree's lie apart, and so do a page's objects. Holding them
  took the first page from 14.3 million steps to 9.1 million, later pages
  from 8 to 21 million to about 6.5 million, the link to the last section
  from 27.1 million to 9.1 million, and the middle entry from 37.8 million
  to 7.3 million, for about 50 KB more held here. When memory refuses a
  stream, the file gives back the others and decodes it again. Following
  a link asks for its destination twice, for its page and then for its
  place, and the reader keeps the one found last, so it is looked up
  once.

- A document's contents reach a rich terminal as their tree: the media
  element's capture publishes the tree's item view while it shows them,
  as it publishes the text area or the document view it shows, each
  entry at its depth under its parent, open or closed. A rich terminal
  opens and closes entries as it does any tree's. The tree keeps what was
  opened and chosen while the document stays open.
  `MEDIA-CONTENTS-STORAGE-DISJOINT?` keeps a capture's banks clear of the
  entries' next siblings and of the document's contents.

- A link or a contents entry shows the place on its page that its
  destination names, not the page's start. Each page read keeps where its
  blocks lie (`PDF-BLOCK-LOW`, `PDF-BLOCK-ACROSS`), and `PDF-DEST` gives a
  destination's left as well as its top. Of the blocks across the left,
  then of those in that block's column, the one whose last line's middle
  is the highest at or below the top is shown first, so on a page of two
  columns a link to the second column's heading does not show the first
  column's beside it, and a picture centred above its caption is found.
  The view keeps a place a jump put at its top while the page below is
  read, until it scrolls; scrolling still stops at a page not read as at
  the document's end.
- Pages of columns read as their paragraphs. The layout finds the gutters
  between body lines side by side and each column's start, and judges a
  line short against its own column's end, not the page's: a two-column
  TeX article's first column had been a paragraph a line. A paragraph
  that runs to a column's foot goes on at the top of the next column, and
  a title or abstract over both columns spans them. A page whose lines
  only step down looks for no gutters, and on a two-column page the
  search costs about 160,000 steps, 2 percent of reading it.

- A page's start shows the label the file gives it (`pdf/labels.f`), such
  as iv or A-3, read once from every pair of the `/PageLabels` number tree
  (`PDF-NUMS-EACH`), so a PDF's page list labels every page too.
- Step 10's samples are on every image with File Explorer: `sample.pdf`,
  `tagged.pdf` and `encrypted.pdf`, written at image build by
  `local_testing/sample_pdf.py` with a baseline JPEG encoder in integer
  arithmetic (`jpeg_baseline.py`), so each is the same file on every host.
  Akashic reads all three as the same three-page document: its blocks, two
  lists, two pictures, code, links to a page and to the web, and its
  outline. The `fexplorer` smoke walks the plain copy through its link,
  its contents and its pictures' page, and opens the other two.
- A document's work, a part to read or a picture's file to make, now runs
  inside applications: hosts ran their service pass only while a picture
  widget was decoding, so a PDF's first page was never read there. Each
  view with such work is counted (`DOCV-WORK?`) beside the pictures
  (`PICT-WORK?`), in the app shell and in Desk's applet host.

- A document's contents are a general element (`DOC-CONTENTS`): its
  reader's, as a PDF's outline, or else its headings of levels 1 to 3. A
  PDF without an outline lists its pages. An entry starts closed when its
  reader says so (`DOC-CLOSE-ENTRY`), as a PDF outline item with a
  negative `/Count` does. The media widget shows them as a tree in the
  document's place with the key c; Enter goes to the chosen entry,
  reading a PDF's page alone if need be. Making them reads the outline and
  no page.

- A PDF's links are followed. The layout places each link of a page over
  the words its rectangle covers, in proportion within a run and snapped to
  whole words, and keeps the places through lines and blocks. A link to the
  web goes to the view's owner, which File Explorer refuses with a message;
  a link within the file keeps its destination, and following it reads the
  page it names, alone if need be, and shows the place it names there.

- A PDF's figures show their pictures. A document that holds its pictures
  gives each figure a maker (`media/picture.f`), which makes the picture's
  file a step at a time; the document view sizes the figure from it and
  makes the file from its service while the figure is shown. A PDF's
  samples become a QOI file that CELL shows cell for cell as it shows that
  QOI anywhere, and a JPEG stays a JPEG.

- A PDF is a document read a page at a time (`pdf/document.f`): a part for
  each page, each page its start, labelled with its number, then the blocks
  its layout gives, with their list items, quotes and blank rows. A page
  that cannot be opened says so, and a file that needs a password opens
  locked. `MEDIA-KIND` calls a file that starts `%PDF-` a PDF. The media
  widget keeps a document reader for each kind, Markdown's from the start;
  File Explorer adds the PDF reader to its preview, so only applications
  that show PDFs load the PDF modules. A locked PDF shows its facts and says
  it is protected. The Desktop image's source grows by about 226 KB to
  3.89 MB, with 27 MB of the disk still free.

- A document may come in parts. A reader adds its parts when the document
  opens and a part's blocks when asked, in any order, each where its part
  lies, and every block keeps the key it was given, so DOC1 keys stay the
  same as pages are read around them. The document view reads the parts
  within a screen of what it shows, one each service call, stops at a part
  not read as at the document's end, and keeps what it shows in place when
  a part above it is read. `DOCV-GO-PART` reads a far part alone. A part
  that fails to read is tried again only after the view changes.
- A page's start is the DOC1 block `PAGE`. MegaPad's codec refuses one in
  a container, and its reference renderer shows the label muted with a
  rule's line through the cells each of its lines leaves, one cell clear
  of it. Akashic's document model, DOC1 validator and document view do
  the same in CELL, and the view publishes the block as it is.

- The file layer reads cross-reference tables and streams, object streams
  and incremental updates, repairs a damaged file by scanning, decodes
  every filter listed, and walks the page tree with what each page
  inherits; the next page of a parent opens by reading only itself.
- Fonts map codes through ToUnicode maps, the four Latin encodings with
  Differences, an embedded Type 1 program's own encoding, the standard
  fonts' metrics, and composite fonts with Identity, embedded, UCS-2 and
  UTF-16 CMaps. The content interpreter gives runs of text through form
  XObjects and marked content. Pages that xelatex, pdflatex, LibreOffice and
  Ghostscript write read as pdftotext reads them.
- The layout gives a page's paragraphs, headings by size or a bold line,
  bullet and numbered items, and code with its indents, from the order its
  content shows its text; a hyphenated word is joined, and the page's
  number and any artifacts are left out. LibreOffice's and xelatex's
  documents lay out as their sources read. A tagged page takes its blocks,
  headings, code, list items, their numbers and quotes from its structure
  tree through the parent tree and role map, and still judges paragraphs
  by their lines, since producers map their own heading styles to P.
- Files encrypted by the standard security handler with the empty user
  password open: RC4 of revisions 2 to 4, AES-128 through revision 4's
  crypt filters, and AES-256 of revisions 5 and 6, as qpdf writes them. A
  file with a user password opens locked and says so.
- AES runs on MegaPad's engine, which now has CBC beside GCM in the
  emulator and its native and hosted models, with BIOS words `AES-MODE!`
  and `AES-CBC-IV!`; `math/aes.f` gains `AES-CBC-ENCRYPT` and
  `AES-CBC-DECRYPT` under the one AES guard, and its statuses are the
  module's (`AES-S-*`). The BIOS's SHA-512 stream gains SHA-384
  (`SHA384-INIT`, `SHA384-FINAL`) and `math/sha512.f` gains
  `SHA384-HASH`. Revision 6's algorithm 2.B borrows 4 KB from the file's
  memory source while it runs. Opening one of qpdf's one-page files takes,
  in hosted guest steps, 1.1 million for AES-128, 0.2 million for
  revision 5's AES-256 and 6.8 million for revision 6's. A stream read in
  pieces takes its IV at the start and holds back its last block, whose
  padding comes off. The RTL AES block has no CBC yet: its rebuild is
  MegaPad's roadmap item 50.
- A page's links and the outline are read with their titles as UTF-8
  (`pdf/navigate.f`). A link keeps its destination as it is and looks it
  up only when followed: an explicit page, a name through `/Dests`, a
  string through the name tree (`pdf/tree.f`, which the parent tree now
  shares), and down to the page's index (`PDF-PAGE-INDEX`). The outline
  and links of documents xelatex with hyperref and LibreOffice write read
  as MuPDF reads them. Scrolling to a followed link waits for step 9.
- A picture becomes a file the picture views show (`pdf/image.f`). A JPEG
  stays a JPEG, a span of the PDF's own source when stored as it is, else
  copied out a piece at a time, decrypted. Samples become a QOI file the
  guest writes: gray, RGB, CMYK made RGB, or indexed, of 1 to 16 bits,
  with `/Decode` and soft masks; inflated, unpredicted and encoded a row
  at a time (`render/qoi-rows.f`, a QOI encoder by rows), in steps, so
  neither samples nor pixels are held whole. Pictures xelatex and
  LibreOffice place read as their sources are. Each picture the content
  draws is a figure block where it falls among the text, artifacts and
  pictures smaller than the body text left out. Showing a figure in the
  document view waits for step 9.
- A page of a TeX document, about 2,800 characters, costs about 5.4
  million steps once its fonts are read: some 1.5 million to inflate its
  content, about 0.5 million to lex it, the rest to show its glyphs. The
  inflater's cost there, about 520 steps a compressed byte, is the largest
  single part, and step 11 measures it with the rest.
- An object stream's table of offsets is read once into an index when
  the stream is decoded, instead of again up to the object on each fetch:
  the object at index 52 of a stream costs 8,000 steps instead of 62,000.
  A page's index and a named destination cost about a third of what they
  did, the outline half.
- A picture of samples costs about 950 steps a pixel to make into QOI,
  some 610 of them the QOI encoder's, plus about 440 steps a compressed
  byte to inflate. Step 11 measures these with the rest.

**Not in this part.** Forms, annotations other than links, signatures and
attachments. JBIG2, CCITT and JPEG 2000 pictures, which show their facts.
Type 3 glyph shapes and vertical writing. Text in a scanned page, which is
only its picture. A reader applet.

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
