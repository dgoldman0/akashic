# akashic-tui-keys — Terminal Input Decoding

Converts raw UART bytes from `KEY` / `KEY?` into structured key
events.  Arrow keys, function keys, Home/End/PgUp/PgDn, mouse clicks,
and bracketed paste markers all arrive as multi-byte escape sequences.
This module buffers partial sequences and resolves them into typed
event descriptors.

```forth
REQUIRE tui/keys.f
```

`PROVIDED akashic-tui-keys` — safe to include multiple times.

Depends on: `akashic-utf8` (for multi-byte character decoding).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Event Descriptor Layout](#event-descriptor-layout)
- [Event Types](#event-types)
- [Special Key Constants](#special-key-constants)
- [Modifier Flags](#modifier-flags)
- [Mouse Button Constants](#mouse-button-constants)
- [Reading Events](#reading-events)
- [Event Accessors](#event-accessors)
- [Modifier Queries](#modifier-queries)
- [Mouse & Resize State](#mouse--resize-state)
- [Configuration](#configuration)
- [Decode Algorithm](#decode-algorithm)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Event-oriented** | Raw bytes are decoded into structured 3-cell event descriptors. |
| **Blocking & non-blocking** | `KEY-READ` blocks; `KEY-POLL` returns immediately; `KEY-WAIT` has a timeout. |
| **Escape disambiguation** | Configurable timeout (default 50 ms) distinguishes standalone ESC from CSI/SS3 sequence starts. |
| **Full VT100 coverage** | Arrows, F1–F12, Home/End, PgUp/PgDn, Ins/Del, Shift-Tab, SGR mouse, terminal size reports. |
| **UTF-8 aware** | Multi-byte characters are decoded via `akashic-utf8` and returned as `KEY-T-CHAR` events with the Unicode codepoint. |
| **Microsecond timing** | Uses KDOS `TIMER@` for precise escape sequence timeouts. |
| **Prefix convention** | Public: `KEY-`. Internal: `_KEY-`. |
| **Not reentrant** | Shared `VARIABLE`s for decode state; call from one task only. |

---

## Event Descriptor Layout

An event descriptor occupies **3 cells = 24 bytes**:

```
Offset  Size   Field    Description
──────  ─────  ──────   ──────────────────────────────────────
  +0      8    type     KEY-T-CHAR, KEY-T-SPECIAL, KEY-T-MOUSE, etc.
  +8      8    code     Character codepoint, special key constant, or button
 +16      8    mods     Modifier bitmask (shift=1, alt=2, ctrl=4)
```

Allocate event storage with `CREATE`:

```forth
CREATE my-event  24 ALLOT
my-event KEY-READ DROP
my-event KEY-CODE@ .    \ print the keycode
```

---

## Event Types

| Constant | Value | Meaning |
|----------|-------|---------|
| `KEY-T-CHAR` | 0 | Printable character or Ctrl+letter combination |
| `KEY-T-SPECIAL` | 1 | Named key (arrow, function key, etc.) |
| `KEY-T-MOUSE` | 2 | Mouse button/motion event |
| `KEY-T-PASTE` | 3 | Bracketed paste start or end |
| `KEY-T-RESIZE` | 4 | Terminal size changed |

---

## Special Key Constants

Used as the `code` field when `type` = `KEY-T-SPECIAL`.

| Constant | Value | Key |
|----------|-------|-----|
| `KEY-UP` | 1 | Up arrow |
| `KEY-DOWN` | 2 | Down arrow |
| `KEY-RIGHT` | 3 | Right arrow |
| `KEY-LEFT` | 4 | Left arrow |
| `KEY-HOME` | 5 | Home |
| `KEY-END` | 6 | End |
| `KEY-PGUP` | 7 | Page Up |
| `KEY-PGDN` | 8 | Page Down |
| `KEY-INS` | 9 | Insert |
| `KEY-DEL` | 10 | Delete |
| `KEY-F1` | 11 | F1 |
| `KEY-F2` | 12 | F2 |
| `KEY-F3` | 13 | F3 |
| `KEY-F4` | 14 | F4 |
| `KEY-F5` | 15 | F5 |
| `KEY-F6` | 16 | F6 |
| `KEY-F7` | 17 | F7 |
| `KEY-F8` | 18 | F8 |
| `KEY-F9` | 19 | F9 |
| `KEY-F10` | 20 | F10 |
| `KEY-F11` | 21 | F11 |
| `KEY-F12` | 22 | F12 |
| `KEY-ESC` | 23 | Escape (standalone) |
| `KEY-TAB` | 24 | Tab |
| `KEY-BACKTAB` | 25 | Shift-Tab |
| `KEY-ENTER` | 26 | Enter (CR, LF, or CR+LF) |
| `KEY-BACKSPACE` | 27 | Backspace (DEL 127 or BS 8) |

---

## Modifier Flags

Stored in the `mods` field.  Combine with `AND` to test.

| Constant | Value | Modifier |
|----------|-------|----------|
| `KEY-MOD-SHIFT` | 1 | Shift |
| `KEY-MOD-ALT` | 2 | Alt (Meta / Option) |
| `KEY-MOD-CTRL` | 4 | Ctrl |

Modifiers are extracted from CSI sequence parameters where the terminal
encodes them as `1 + bitmask` in the second numeric parameter.

---

## Mouse Button Constants

Used as the `code` field when `type` = `KEY-T-MOUSE`.

| Constant | Value | Button |
|----------|-------|--------|
| `KEY-MOUSE-LEFT` | 0 | Left button press |
| `KEY-MOUSE-MIDDLE` | 1 | Middle button press |
| `KEY-MOUSE-RIGHT` | 2 | Right button press |
| `KEY-MOUSE-RELEASE` | 3 | Button release |
| `KEY-MOUSE-SCROLL-UP` | 64 | Scroll wheel up |
| `KEY-MOUSE-SCROLL-DN` | 65 | Scroll wheel down |

Mouse coordinates are stored separately in `KEY-MOUSE-X` and
`KEY-MOUSE-Y` (see below).

---

## Reading Events

### `KEY-READ`

```forth
KEY-READ ( ev -- flag )
```

Blocking read.  Waits until a complete key event is decoded, fills
the event descriptor at `ev`, and returns TRUE (-1).

```forth
CREATE ev 24 ALLOT
ev KEY-READ DROP
ev KEY-IS-CHAR? IF
    ev KEY-CODE@ EMIT
THEN
```

### `KEY-POLL`

```forth
KEY-POLL ( ev -- flag )
```

Non-blocking poll.  If input bytes are available, decodes one event
and returns TRUE.  If no input is pending, returns FALSE (0) without
blocking.

```forth
ev KEY-POLL IF
    \ handle event
THEN
```

### `KEY-WAIT`

```forth
KEY-WAIT ( ev ms -- flag )
```

Blocking read with timeout.  Waits up to `ms` milliseconds.  Returns
TRUE if an event was received, FALSE if the timeout expired.  If
`ms` = 0, behaves like `KEY-READ` (waits forever).

```forth
ev 1000 KEY-WAIT IF
    \ got input within 1 second
ELSE
    \ timeout — no input
THEN
```

---

## Event Accessors

### `KEY-CODE@`

```forth
KEY-CODE@ ( ev -- code )
```

Read the `code` field from an event descriptor.  For `KEY-T-CHAR`
events, this is the Unicode codepoint.  For `KEY-T-SPECIAL`, one of
the `KEY-UP` ... `KEY-BACKSPACE` constants.  For `KEY-T-MOUSE`, the
button constant.

### `KEY-MODS@`

```forth
KEY-MODS@ ( ev -- mods )
```

Read the modifier bitmask.  Returns a combination of `KEY-MOD-SHIFT`,
`KEY-MOD-ALT`, `KEY-MOD-CTRL` (ORed together).

---

## Modifier Queries

### `KEY-HAS-CTRL?`

```forth
KEY-HAS-CTRL? ( ev -- flag )
```

TRUE if Ctrl was held.

### `KEY-HAS-ALT?`

```forth
KEY-HAS-ALT? ( ev -- flag )
```

TRUE if Alt was held.

### `KEY-HAS-SHIFT?`

```forth
KEY-HAS-SHIFT? ( ev -- flag )
```

TRUE if Shift was held.

---

## Type Queries

### `KEY-IS-CHAR?`

```forth
KEY-IS-CHAR? ( ev -- flag )
```

TRUE if the event is a printable character or Ctrl+letter.

### `KEY-IS-SPECIAL?`

```forth
KEY-IS-SPECIAL? ( ev -- flag )
```

TRUE if the event is a named special key (arrow, function key, etc.).

### `KEY-IS-MOUSE?`

```forth
KEY-IS-MOUSE? ( ev -- flag )
```

TRUE if the event is a mouse event.

```forth
ev KEY-READ DROP
ev KEY-IS-MOUSE? IF
    KEY-MOUSE-X @  KEY-MOUSE-Y @
    ." Click at " . ." , " . CR
THEN
```

---

## Mouse & Resize State

### `KEY-MOUSE-X`

```forth
KEY-MOUSE-X ( -- addr )
```

`VARIABLE` holding the column (1-based) of the last mouse event.
Updated automatically when a `KEY-T-MOUSE` event is decoded.

### `KEY-MOUSE-Y`

```forth
KEY-MOUSE-Y ( -- addr )
```

`VARIABLE` holding the row (1-based) of the last mouse event.

### `KEY-RESIZE-W`

```forth
KEY-RESIZE-W ( -- addr )
```

`VARIABLE` holding the terminal width (columns) from the last
`KEY-T-RESIZE` event.  Populated when the response to
`ANSI-QUERY-SIZE` is decoded.

### `KEY-RESIZE-H`

```forth
KEY-RESIZE-H ( -- addr )
```

`VARIABLE` holding the terminal height (rows) from the last
`KEY-T-RESIZE` event.

```forth
ANSI-QUERY-SIZE
\ ... process events until KEY-T-RESIZE arrives ...
KEY-RESIZE-W @  KEY-RESIZE-H @
." Terminal: " . ." cols × " . ." rows" CR
```

---

## Configuration

### `KEY-TIMEOUT!`

```forth
KEY-TIMEOUT! ( ms -- )
```

Set the escape sequence disambiguation timeout in milliseconds.

When an ESC byte (27) arrives, the decoder waits up to this many
milliseconds for a follow-up byte.  If one arrives, it is part of a
CSI or SS3 sequence.  If the timeout expires, the ESC is interpreted
as a standalone Escape keypress.

Default: **50 ms**.  Lower values make ESC more responsive but risk
misinterpreting slow-arriving sequences.  Higher values are more
reliable over high-latency serial links.

```forth
100 KEY-TIMEOUT!    \ 100 ms — conservative for slow links
20  KEY-TIMEOUT!    \ 20 ms  — snappy for local terminal
```

---

## Decode Algorithm

The core decoder (`_KEY-READ-RAW`) examines the first byte and
dispatches:

1. **ESC (27)** — Wait up to timeout for next byte:
   - `[` → CSI sequence: read bytes until a final character (64–126)
     arrives, then parse via `_KEY-DECODE-CSI`.
   - `O` → SS3 sequence: read one more byte, parse via
     `_KEY-DECODE-SS3`.
   - Other → Alt+character (modifier = `KEY-MOD-ALT`).
   - Timeout → standalone `KEY-ESC` event.

2. **Tab (9)** → `KEY-T-SPECIAL KEY-TAB`.

3. **CR (13)** → `KEY-T-SPECIAL KEY-ENTER`.  Consumes optional LF
   after CR (handles CR+LF line endings).

4. **LF (10)** → `KEY-T-SPECIAL KEY-ENTER`.

5. **DEL (127) or BS (8)** → `KEY-T-SPECIAL KEY-BACKSPACE`.

6. **Ctrl+letter (1–26, excluding Tab/LF/CR)** → `KEY-T-CHAR` with
   code = `96 + byte` (i.e., the lowercase letter) and modifier
   `KEY-MOD-CTRL`.

7. **High bit set (≥ 0x80)** → UTF-8 multi-byte character.  Determines
   sequence length from the leading byte, reads continuation bytes,
   decodes via `UTF8-DECODE`, returns as `KEY-T-CHAR`.  Invalid
   sequences produce the replacement character U+FFFD.

8. **Anything else** → `KEY-T-CHAR` with the raw byte as codepoint.

### CSI Parsing

`_KEY-DECODE-CSI` examines the final character of the buffered
sequence:

| Final | Decoded As |
|-------|-----------|
| `A` `B` `C` `D` | Arrows (up/down/right/left) |
| `H` `F` | Home / End |
| `~` | Tilde sequence — param selects key (2=Ins, 3=Del, 5/6=PgUp/PgDn, 15–24=F5–F12) |
| `M` | SGR mouse press (if preceded by `<`) or legacy X10 mouse |
| `m` | SGR mouse release |
| `Z` | Shift-Tab |
| `t` | Terminal size response (param 8 → rows;cols) |

The second numeric CSI parameter encodes modifiers as `1 + bitmask`.

### SS3 Parsing

`_KEY-DECODE-SS3` maps the single final byte:

| Byte | Key |
|------|-----|
| `P` `Q` `R` `S` | F1–F4 |
| `H` `F` | Home / End |
| `A` `B` `C` `D` | Arrow keys (some terminals) |

---

## Quick Reference

| Word | Signature | Behavior |
|------|-----------|----------|
| `KEY-READ` | `( ev -- flag )` | Blocking read; always TRUE |
| `KEY-POLL` | `( ev -- flag )` | Non-blocking; TRUE if event filled |
| `KEY-WAIT` | `( ev ms -- flag )` | Timeout read; TRUE if event, FALSE if expired |
| `KEY-IS-CHAR?` | `( ev -- flag )` | Character event? |
| `KEY-IS-SPECIAL?` | `( ev -- flag )` | Special key event? |
| `KEY-IS-MOUSE?` | `( ev -- flag )` | Mouse event? |
| `KEY-CODE@` | `( ev -- code )` | Get keycode / codepoint |
| `KEY-MODS@` | `( ev -- mods )` | Get modifier bitmask |
| `KEY-HAS-CTRL?` | `( ev -- flag )` | Ctrl held? |
| `KEY-HAS-ALT?` | `( ev -- flag )` | Alt held? |
| `KEY-HAS-SHIFT?` | `( ev -- flag )` | Shift held? |
| `KEY-TIMEOUT!` | `( ms -- )` | Set ESC disambiguation timeout |
| `KEY-MOUSE-X` | `( -- addr )` | Last mouse column |
| `KEY-MOUSE-Y` | `( -- addr )` | Last mouse row |
| `KEY-RESIZE-W` | `( -- addr )` | Terminal width from last resize |
| `KEY-RESIZE-H` | `( -- addr )` | Terminal height from last resize |

### Internal Words

| Word | Signature | Behavior |
|------|-----------|----------|
| `_KEY-EV-TYPE` | `( ev -- addr )` | Address of type field (+0) |
| `_KEY-EV-CODE` | `( ev -- addr )` | Address of code field (+8) |
| `_KEY-EV-MODS` | `( ev -- addr )` | Address of mods field (+16) |
| `_KEY-SET-EV` | `( ev type code mods -- )` | Fill an event descriptor |
| `_KEY-TIMED?` | `( ms -- char flag )` | Poll KEY? with microsecond timeout |
| `_KEY-BUF-RESET` | `( -- )` | Clear decode buffer |
| `_KEY-BUF-ADD` | `( c -- )` | Append byte to decode buffer |
| `_KEY-BUF-C@` | `( i -- c )` | Read byte i from decode buffer |
| `_KEY-PARSE-NUM` | `( -- n )` | Parse decimal number from buffer |
| `_KEY-SKIP-SEP` | `( -- )` | Skip `;` separator in buffer |
| `_KEY-DECODE-MODS` | `( param -- mods )` | Convert CSI modifier param to bitmask |
| `_KEY-CSI-PARSE-PARAMS` | `( -- )` | Parse CSI numeric parameters |
| `_KEY-DECODE-CSI` | `( ev -- )` | Decode CSI sequence into event |
| `_KEY-DECODE-SS3` | `( ev -- )` | Decode SS3 sequence into event |
| `_KEY-READ-RAW` | `( ev -- flag )` | Core decode: read and classify one input |

### Internal Variables

| Name | Purpose |
|------|---------|
| `_KEY-TIMEOUT` | Escape timeout in milliseconds (default 50) |
| `_KEY-BUF` | 32-byte raw sequence decode buffer |
| `_KEY-BLEN` | Current byte count in decode buffer |
| `_KEY-UTF8` | 4-byte scratch for UTF-8 decode |
| `_KEY-B0` | First raw byte of current input |
| `_KEY-PIDX` | Parse index into decode buffer |
| `_KEY-CSI-P1` | First CSI numeric parameter |
| `_KEY-CSI-P2` | Second CSI numeric parameter |
| `_KEY-CSI-FINAL` | CSI final (terminator) byte |
| `_KEY-DEADLINE` | Absolute deadline for `_KEY-TIMED?` |

### Constants

| Name | Value | Meaning |
|------|-------|---------|
| `KEY-T-CHAR` | 0 | Character event type |
| `KEY-T-SPECIAL` | 1 | Special key event type |
| `KEY-T-MOUSE` | 2 | Mouse event type |
| `KEY-T-PASTE` | 3 | Paste bracket event type |
| `KEY-T-RESIZE` | 4 | Resize event type |
| `KEY-MOD-SHIFT` | 1 | Shift modifier flag |
| `KEY-MOD-ALT` | 2 | Alt modifier flag |
| `KEY-MOD-CTRL` | 4 | Ctrl modifier flag |
