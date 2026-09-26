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
- **Checks.** Lightweight tests run while building. Each part ends with new
  milestones in the physical Desktop journey
  (`local_testing/physical_desktop_acceptance.py`), run one at a time under
  the existing guards.

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
