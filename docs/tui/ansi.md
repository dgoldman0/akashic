# akashic-tui-ansi — ANSI Terminal Escape Sequence Emitter

Stateless words that emit VT100/ANSI escape sequences to the KDOS
UART.  Every word is a thin wrapper around `EMIT` — no buffers, no
allocation, no state.  This is the bottom of the TUI stack.

```forth
REQUIRE tui/ansi.f
```

`PROVIDED akashic-tui-ansi` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Cursor Movement](#cursor-movement)
- [Screen Clearing](#screen-clearing)
- [Scrolling](#scrolling)
- [Text Attributes](#text-attributes)
- [Colors — Standard 16](#colors--standard-16)
- [Colors — 256 Palette](#colors--256-palette)
- [Colors — True-Color RGB](#colors--true-color-rgb)
- [Terminal Modes](#terminal-modes)
- [Queries](#queries)
- [Title](#title)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Stateless** | Every word emits bytes and returns — no mode tracking, no shadow state. |
| **Zero allocation** | No buffers beyond a 12-byte scratch for decimal number formatting. |
| **Pure KDOS I/O** | Uses only `EMIT` and `TYPE` — runs on any KDOS build. |
| **Thin wrappers** | Each word maps 1:1 to a documented VT100/ANSI escape sequence. |
| **Prefix convention** | Public: `ANSI-`. Internal: `_ANSI-`. |
| **Building block** | Higher layers (screen, draw, widgets) call these — user code rarely needs to. |
| **Not reentrant** | Scratch `VARIABLE`s for `_ANSI-NUM` are shared; call from one task only. |

---

## Constants

### Color Indices

| Name | Value | Color |
|------|-------|-------|
| `ANSI-BLACK` | 0 | Black |
| `ANSI-RED` | 1 | Red |
| `ANSI-GREEN` | 2 | Green |
| `ANSI-YELLOW` | 3 | Yellow |
| `ANSI-BLUE` | 4 | Blue |
| `ANSI-MAGENTA` | 5 | Magenta |
| `ANSI-CYAN` | 6 | Cyan |
| `ANSI-WHITE` | 7 | White |

### Other

| Name | Value | Meaning |
|------|-------|---------|
| `ANSI-ESC` | 27 | The ESC character (0x1B) |

---

## Cursor Movement

### `ANSI-AT`

```forth
ANSI-AT ( row col -- )
```

Move cursor to absolute position.  Both row and col are **1-based**
(top-left is 1,1).  Emits `ESC[row;colH`.

```forth
1 1 ANSI-AT         \ top-left corner
24 80 ANSI-AT       \ bottom-right of an 80×24 terminal
```

### `ANSI-UP`

```forth
ANSI-UP ( n -- )
```

Move cursor up `n` rows.  No-op if `n` is 0.  Emits `ESC[nA`.

```forth
3 ANSI-UP           \ move up 3 rows
```

### `ANSI-DOWN`

```forth
ANSI-DOWN ( n -- )
```

Move cursor down `n` rows.  No-op if `n` is 0.  Emits `ESC[nB`.

### `ANSI-RIGHT`

```forth
ANSI-RIGHT ( n -- )
```

Move cursor right `n` columns.  No-op if `n` is 0.  Emits `ESC[nC`.

### `ANSI-LEFT`

```forth
ANSI-LEFT ( n -- )
```

Move cursor left `n` columns.  No-op if `n` is 0.  Emits `ESC[nD`.

### `ANSI-HOME`

```forth
ANSI-HOME ( -- )
```

Move cursor to row 1, column 1 (top-left).  Emits `ESC[H`.

### `ANSI-COL`

```forth
ANSI-COL ( n -- )
```

Move cursor to column `n` (1-based) on the current row.  Emits `ESC[nG`.

```forth
40 ANSI-COL         \ jump to column 40
```

### `ANSI-SAVE`

```forth
ANSI-SAVE ( -- )
```

Save the current cursor position.  Restored later by `ANSI-RESTORE`.
Emits `ESC[s`.

### `ANSI-RESTORE`

```forth
ANSI-RESTORE ( -- )
```

Restore cursor position saved by `ANSI-SAVE`.  Emits `ESC[u`.

```forth
ANSI-SAVE
10 40 ANSI-AT  ." status"
ANSI-RESTORE       \ back to where we were
```

---

## Screen Clearing

### `ANSI-CLEAR`

```forth
ANSI-CLEAR ( -- )
```

Clear the entire screen but do **not** move the cursor.  Emits `ESC[2J`.
Typically followed by `ANSI-HOME` to reset position.

```forth
ANSI-CLEAR ANSI-HOME   \ blank slate
```

### `ANSI-CLEAR-EOL`

```forth
ANSI-CLEAR-EOL ( -- )
```

Clear from cursor to end of the current line.  Emits `ESC[K`.

### `ANSI-CLEAR-BOL`

```forth
ANSI-CLEAR-BOL ( -- )
```

Clear from beginning of line to cursor.  Emits `ESC[1K`.

### `ANSI-CLEAR-LINE`

```forth
ANSI-CLEAR-LINE ( -- )
```

Clear the entire current line.  Emits `ESC[2K`.

### `ANSI-CLEAR-EOS`

```forth
ANSI-CLEAR-EOS ( -- )
```

Clear from cursor to end of screen.  Emits `ESC[J`.

### `ANSI-CLEAR-BOS`

```forth
ANSI-CLEAR-BOS ( -- )
```

Clear from beginning of screen to cursor.  Emits `ESC[1J`.

---

## Scrolling

### `ANSI-SCROLL-UP`

```forth
ANSI-SCROLL-UP ( n -- )
```

Scroll the screen contents up `n` lines.  New blank lines appear at
the bottom.  No-op if `n` is 0.  Emits `ESC[nS`.

### `ANSI-SCROLL-DN`

```forth
ANSI-SCROLL-DN ( n -- )
```

Scroll down `n` lines.  New blank lines appear at the top.  No-op if
`n` is 0.  Emits `ESC[nT`.

### `ANSI-SCROLL-RGN`

```forth
ANSI-SCROLL-RGN ( top bot -- )
```

Set the scroll region to rows `top` through `bot` (both 1-based,
inclusive).  Lines outside this region do not scroll.  Emits
`ESC[top;botr`.

```forth
2 23 ANSI-SCROLL-RGN   \ rows 2-23 scroll; row 1 and 24 stay fixed
```

### `ANSI-SCROLL-RESET`

```forth
ANSI-SCROLL-RESET ( -- )
```

Reset the scroll region to the full screen.  Emits `ESC[r`.

---

## Text Attributes

All attribute words use the SGR (Select Graphic Rendition) mechanism.
Each emits a single `ESC[nm` sequence.

### `ANSI-RESET`

```forth
ANSI-RESET ( -- )
```

Reset **all** attributes (color, bold, underline, etc.) to defaults.
Emits `ESC[0m`.

### `ANSI-BOLD`

```forth
ANSI-BOLD ( -- )
```

Enable bold (bright intensity).  `ESC[1m`.

### `ANSI-DIM`

```forth
ANSI-DIM ( -- )
```

Enable dim (faint intensity).  `ESC[2m`.

### `ANSI-ITALIC`

```forth
ANSI-ITALIC ( -- )
```

Enable italic.  `ESC[3m`.  Not supported on all terminals.

### `ANSI-UNDERLINE`

```forth
ANSI-UNDERLINE ( -- )
```

Enable underline.  `ESC[4m`.

### `ANSI-BLINK`

```forth
ANSI-BLINK ( -- )
```

Enable blink.  `ESC[5m`.  Often disabled in modern terminals.

### `ANSI-REVERSE`

```forth
ANSI-REVERSE ( -- )
```

Enable reverse video (swap foreground/background).  `ESC[7m`.

```forth
ANSI-REVERSE ." SELECTED " ANSI-NO-REVERSE
```

### `ANSI-HIDDEN`

```forth
ANSI-HIDDEN ( -- )
```

Enable hidden text (invisible).  `ESC[8m`.

### `ANSI-STRIKE`

```forth
ANSI-STRIKE ( -- )
```

Enable strikethrough.  `ESC[9m`.

### `ANSI-NORMAL`

```forth
ANSI-NORMAL ( -- )
```

Remove bold and dim, returning to normal intensity.  `ESC[22m`.

### Turn-Off Counterparts

| Word | SGR | Turns off |
|------|-----|-----------|
| `ANSI-NO-ITALIC` | `ESC[23m` | Italic |
| `ANSI-NO-UNDERLINE` | `ESC[24m` | Underline |
| `ANSI-NO-BLINK` | `ESC[25m` | Blink |
| `ANSI-NO-REVERSE` | `ESC[27m` | Reverse video |
| `ANSI-NO-HIDDEN` | `ESC[28m` | Hidden |
| `ANSI-NO-STRIKE` | `ESC[29m` | Strikethrough |

---

## Colors — Standard 16

### `ANSI-FG`

```forth
ANSI-FG ( color -- )
```

Set foreground to one of the 8 standard colors (0–7).  Emits
`ESC[30+colorm`.

```forth
ANSI-RED ANSI-FG  ." Error!" ANSI-RESET
```

### `ANSI-BG`

```forth
ANSI-BG ( color -- )
```

Set background to one of the 8 standard colors (0–7).  Emits
`ESC[40+colorm`.

### `ANSI-FG-BRIGHT`

```forth
ANSI-FG-BRIGHT ( color -- )
```

Set foreground to a bright (high-intensity) color.  Emits
`ESC[90+colorm`.

### `ANSI-BG-BRIGHT`

```forth
ANSI-BG-BRIGHT ( color -- )
```

Set background to a bright color.  Emits `ESC[100+colorm`.

```forth
ANSI-BLUE ANSI-BG-BRIGHT
ANSI-WHITE ANSI-FG
." bright blue background "
ANSI-RESET
```

### `ANSI-DEFAULT-FG`

```forth
ANSI-DEFAULT-FG ( -- )
```

Reset foreground to terminal default.  `ESC[39m`.

### `ANSI-DEFAULT-BG`

```forth
ANSI-DEFAULT-BG ( -- )
```

Reset background to terminal default.  `ESC[49m`.

---

## Colors — 256 Palette

### `ANSI-FG256`

```forth
ANSI-FG256 ( n -- )
```

Set foreground from the 256-color palette (0–255).  Emits
`ESC[38;5;nm`.

- 0–7: standard colors
- 8–15: bright colors
- 16–231: 6×6×6 color cube
- 232–255: grayscale ramp

```forth
208 ANSI-FG256  ." orange text "  ANSI-RESET
```

### `ANSI-BG256`

```forth
ANSI-BG256 ( n -- )
```

Set background from the 256-color palette.  Emits `ESC[48;5;nm`.

---

## Colors — True-Color RGB

### `ANSI-FG-RGB`

```forth
ANSI-FG-RGB ( r g b -- )
```

Set foreground to a 24-bit RGB color.  Each component 0–255.  Emits
`ESC[38;2;r;g;bm`.

```forth
255 128 0 ANSI-FG-RGB    \ orange foreground
```

### `ANSI-BG-RGB`

```forth
ANSI-BG-RGB ( r g b -- )
```

Set background to a 24-bit RGB color.  Emits `ESC[48;2;r;g;bm`.

```forth
0 0 64 ANSI-BG-RGB      \ dark blue background
```

---

## Terminal Modes

### `ANSI-ALT-ON`

```forth
ANSI-ALT-ON ( -- )
```

Enter the alternate screen buffer.  The current screen content is
preserved and restored when `ANSI-ALT-OFF` is called.  Emits
`ESC[?1049h`.

Full-screen TUI applications should enter the alternate screen on
startup and leave it on exit:

```forth
ANSI-ALT-ON ANSI-CLEAR ANSI-HOME
\ ... run application ...
ANSI-ALT-OFF
```

### `ANSI-ALT-OFF`

```forth
ANSI-ALT-OFF ( -- )
```

Leave the alternate screen buffer, restoring the previous content.
Emits `ESC[?1049l`.

### `ANSI-CURSOR-ON`

```forth
ANSI-CURSOR-ON ( -- )
```

Show the cursor.  Emits `ESC[?25h`.

### `ANSI-CURSOR-OFF`

```forth
ANSI-CURSOR-OFF ( -- )
```

Hide the cursor.  Emits `ESC[?25l`.  Useful during bulk screen updates
to prevent cursor flicker.

```forth
ANSI-CURSOR-OFF
\ ... redraw screen ...
ANSI-CURSOR-ON
```

### `ANSI-MOUSE-ON`

```forth
ANSI-MOUSE-ON ( -- )
```

Enable SGR extended mouse reporting.  Emits `ESC[?1000h` (button
events) followed by `ESC[?1006h` (SGR encoding, allowing coordinates
larger than 223).

Mouse events arrive as CSI sequences and are decoded by `keys.f`.

### `ANSI-MOUSE-OFF`

```forth
ANSI-MOUSE-OFF ( -- )
```

Disable mouse reporting.  Emits `ESC[?1006l` and `ESC[?1000l`.

### `ANSI-PASTE-ON`

```forth
ANSI-PASTE-ON ( -- )
```

Enable bracketed paste mode.  Pasted text is delimited by
`ESC[200~` ... `ESC[201~`, allowing the application to distinguish
typed input from pasted content.  Emits `ESC[?2004h`.

### `ANSI-PASTE-OFF`

```forth
ANSI-PASTE-OFF ( -- )
```

Disable bracketed paste mode.  Emits `ESC[?2004l`.

---

## Queries

### `ANSI-QUERY-SIZE`

```forth
ANSI-QUERY-SIZE ( -- )
```

Request terminal dimensions.  Emits `ESC[18t`.  The terminal responds
with `ESC[8;rows;colst`, which is parsed by `keys.f` and stored in
`KEY-RESIZE-W` / `KEY-RESIZE-H`.

```forth
ANSI-QUERY-SIZE
\ ... later, after KEY-READ returns a KEY-T-RESIZE event ...
KEY-RESIZE-W @  KEY-RESIZE-H @   \ ( cols rows )
```

### `ANSI-QUERY-CURSOR`

```forth
ANSI-QUERY-CURSOR ( -- )
```

Request current cursor position.  Emits `ESC[6n`.  The terminal
responds with `ESC[row;colR`.

---

## Title

### `ANSI-TITLE`

```forth
ANSI-TITLE ( addr len -- )
```

Set the terminal window title.  Emits `ESC]2;...ST` where ST is
`ESC \` (string terminator).

```forth
\ Set title (counted string on the stack)
: set-title  S" My Application" ANSI-TITLE ;
```

---

## Quick Reference

| Word | Signature | Escape Sequence |
|------|-----------|-----------------|
| `ANSI-AT` | `( row col -- )` | `ESC[row;colH` |
| `ANSI-UP` | `( n -- )` | `ESC[nA` |
| `ANSI-DOWN` | `( n -- )` | `ESC[nB` |
| `ANSI-RIGHT` | `( n -- )` | `ESC[nC` |
| `ANSI-LEFT` | `( n -- )` | `ESC[nD` |
| `ANSI-HOME` | `( -- )` | `ESC[H` |
| `ANSI-COL` | `( n -- )` | `ESC[nG` |
| `ANSI-SAVE` | `( -- )` | `ESC[s` |
| `ANSI-RESTORE` | `( -- )` | `ESC[u` |
| `ANSI-CLEAR` | `( -- )` | `ESC[2J` |
| `ANSI-CLEAR-EOL` | `( -- )` | `ESC[K` |
| `ANSI-CLEAR-BOL` | `( -- )` | `ESC[1K` |
| `ANSI-CLEAR-LINE` | `( -- )` | `ESC[2K` |
| `ANSI-CLEAR-EOS` | `( -- )` | `ESC[J` |
| `ANSI-CLEAR-BOS` | `( -- )` | `ESC[1J` |
| `ANSI-SCROLL-UP` | `( n -- )` | `ESC[nS` |
| `ANSI-SCROLL-DN` | `( n -- )` | `ESC[nT` |
| `ANSI-SCROLL-RGN` | `( top bot -- )` | `ESC[top;botr` |
| `ANSI-SCROLL-RESET` | `( -- )` | `ESC[r` |
| `ANSI-RESET` | `( -- )` | `ESC[0m` |
| `ANSI-BOLD` | `( -- )` | `ESC[1m` |
| `ANSI-DIM` | `( -- )` | `ESC[2m` |
| `ANSI-ITALIC` | `( -- )` | `ESC[3m` |
| `ANSI-UNDERLINE` | `( -- )` | `ESC[4m` |
| `ANSI-BLINK` | `( -- )` | `ESC[5m` |
| `ANSI-REVERSE` | `( -- )` | `ESC[7m` |
| `ANSI-HIDDEN` | `( -- )` | `ESC[8m` |
| `ANSI-STRIKE` | `( -- )` | `ESC[9m` |
| `ANSI-NORMAL` | `( -- )` | `ESC[22m` |
| `ANSI-NO-ITALIC` | `( -- )` | `ESC[23m` |
| `ANSI-NO-UNDERLINE` | `( -- )` | `ESC[24m` |
| `ANSI-NO-BLINK` | `( -- )` | `ESC[25m` |
| `ANSI-NO-REVERSE` | `( -- )` | `ESC[27m` |
| `ANSI-NO-HIDDEN` | `( -- )` | `ESC[28m` |
| `ANSI-NO-STRIKE` | `( -- )` | `ESC[29m` |
| `ANSI-FG` | `( color -- )` | `ESC[30+cm` |
| `ANSI-BG` | `( color -- )` | `ESC[40+cm` |
| `ANSI-FG-BRIGHT` | `( color -- )` | `ESC[90+cm` |
| `ANSI-BG-BRIGHT` | `( color -- )` | `ESC[100+cm` |
| `ANSI-FG256` | `( n -- )` | `ESC[38;5;nm` |
| `ANSI-BG256` | `( n -- )` | `ESC[48;5;nm` |
| `ANSI-FG-RGB` | `( r g b -- )` | `ESC[38;2;r;g;bm` |
| `ANSI-BG-RGB` | `( r g b -- )` | `ESC[48;2;r;g;bm` |
| `ANSI-DEFAULT-FG` | `( -- )` | `ESC[39m` |
| `ANSI-DEFAULT-BG` | `( -- )` | `ESC[49m` |
| `ANSI-ALT-ON` | `( -- )` | `ESC[?1049h` |
| `ANSI-ALT-OFF` | `( -- )` | `ESC[?1049l` |
| `ANSI-CURSOR-ON` | `( -- )` | `ESC[?25h` |
| `ANSI-CURSOR-OFF` | `( -- )` | `ESC[?25l` |
| `ANSI-MOUSE-ON` | `( -- )` | `ESC[?1000h` + `ESC[?1006h` |
| `ANSI-MOUSE-OFF` | `( -- )` | `ESC[?1006l` + `ESC[?1000l` |
| `ANSI-PASTE-ON` | `( -- )` | `ESC[?2004h` |
| `ANSI-PASTE-OFF` | `( -- )` | `ESC[?2004l` |
| `ANSI-QUERY-SIZE` | `( -- )` | `ESC[18t` |
| `ANSI-QUERY-CURSOR` | `( -- )` | `ESC[6n` |
| `ANSI-TITLE` | `( addr len -- )` | `ESC]2;...ST` |

### Internal Words

| Word | Signature | Behavior |
|------|-----------|----------|
| `_ANSI-CSI` | `( -- )` | Emit `ESC [` prefix |
| `_ANSI-SEP` | `( -- )` | Emit `;` separator |
| `_ANSI-NUM` | `( n -- )` | Emit unsigned decimal number |
| `_ANSI-SGR` | `( n -- )` | Emit `CSI n m` — single SGR parameter |
| `_ANSI-PRIV` | `( n suffix -- )` | Emit `ESC[?n{suffix}` — DEC private mode |

### Internal Variables

| Name | Purpose |
|------|---------|
| `_ANSI-NB` | Scratch pointer for decimal formatting |
| `_ANSI-NC` | Character count for decimal formatting |
| `_ANSI-NBUF` | 12-byte scratch buffer for decimal digits |
