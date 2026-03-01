# akashic-audio-midi — MIDI Byte Protocol for KDOS / Megapad-64

Pure data-format library for MIDI wire protocol messages.  Generates
and parses raw MIDI bytes.  Also provides MIDI note ↔ Hz conversion
using a precomputed 128-entry FP16 lookup table (A4 = 440 Hz).

```forth
REQUIRE audio/midi.f
```

`PROVIDED akashic-audio-midi`
Dependencies: `fp16-ext.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Message Types](#message-types)
- [Message Generation](#message-generation)
- [Message Parsing](#message-parsing)
- [Note ↔ Hz Conversion](#note--hz-conversion)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Pure protocol** | No device I/O, no MIDI file (.mid) reader, no instrument maps. |
| **Running status** | Parser supports running status (status byte reuse). |
| **Note-on vel=0** | Automatically reported as note-off (standard MIDI convention). |
| **FP16 Hz table** | 128-entry lookup table built at load time using successive multiplication by the semitone ratio $2^{1/12}$. |
| **Variable-based state** | Scratch via `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `MIDI-`.  Internal: `_MI-`. |

---

## Message Types

| Constant | Value | Meaning | Byte Count |
|---|---|---|---|
| `MIDI-MSG-NOTE-OFF` | 0 | Note off | 3 |
| `MIDI-MSG-NOTE-ON` | 1 | Note on | 3 |
| `MIDI-MSG-POLY-AT` | 2 | Poly aftertouch | 3 |
| `MIDI-MSG-CC` | 3 | Control change | 3 |
| `MIDI-MSG-PROG` | 4 | Program change | 2 |
| `MIDI-MSG-CHAN-AT` | 5 | Channel aftertouch | 2 |
| `MIDI-MSG-BEND` | 6 | Pitch bend | 3 |

---

## Message Generation

All generators return bytes on the stack (status byte deepest).

### MIDI-NOTE-ON

```forth
MIDI-NOTE-ON  ( chan note vel -- b1 b2 b3 )
```

Generate a note-on message.  Channel 0–15.

### MIDI-NOTE-OFF

```forth
MIDI-NOTE-OFF  ( chan note vel -- b1 b2 b3 )
```

### MIDI-CC

```forth
MIDI-CC  ( chan cc val -- b1 b2 b3 )
```

Generate a control change message.

### MIDI-PITCH-BEND

```forth
MIDI-PITCH-BEND  ( chan bend -- b1 b2 b3 )
```

Generate a pitch bend message.  `bend` is a signed 14-bit value
centered at 0 (no bend).  Encoded as `(bend + 8192)` split into
7-bit LSB and MSB.

### MIDI-PROG

```forth
MIDI-PROG  ( chan prog -- b1 b2 )
```

Generate a program change message (2 bytes only).

---

## Message Parsing

### MIDI-PARSE

```forth
MIDI-PARSE  ( byte state -- type chan d1 d2 flag state' )
```

Feed one byte at a time.  `state` is an opaque packed integer
(start with 0).  Returns:

| Return | Meaning |
|---|---|
| `type` | Message type (0–6) or -1 if incomplete |
| `chan` | Channel (0–15) or 0 if incomplete |
| `d1` | Data byte 1 (note, CC#, etc.) or 0 |
| `d2` | Data byte 2 (vel, value, etc.) or 0 |
| `flag` | -1 = complete message, 0 = need more bytes |
| `state'` | Updated state — feed back on next call |

**Return order:** `state'` is on **top of stack** for easy `_st !` usage.

### Running Status

After a complete message, subsequent data bytes (< 0x80) reuse the
last status byte.  The parser handles this automatically.

### Note-on with vel=0

When the parser sees a note-on with velocity 0, it reports it as
`MIDI-MSG-NOTE-OFF` (type 0) with d2=0.

### State packing

```
state = (status << 16) | (phase << 8) | data1
```

- `status`: last status byte (0x80–0xEF)
- `phase`: 0 = waiting for status, 1 = got status/data1, 2 = got data1
- `data1`: first data byte (stored during multi-byte messages)

---

## Note ↔ Hz Conversion

### MIDI-NOTE>HZ

```forth
MIDI-NOTE>HZ  ( note -- hz )
```

O(1) table lookup.  Returns FP16 Hz value.  Clamped to 0–127.

Reference values:

| Note | Name | Hz (approx) | FP16 |
|---|---|---|---|
| 69 | A4 | 440 | 0x5EE0 |
| 60 | C4 | 261.6 | ~0x5C14 |
| 81 | A5 | 880 | ~0x62E0 |

### MIDI-HZ>NOTE

```forth
MIDI-HZ>NOTE  ( hz -- note cents )
```

Linear scan of the table to find the closest note, then linear
interpolation to compute cents offset (0–99).

---

## Internals

### Note Table

A 128-entry table built at load time.  Starting from A4 = 440 Hz
(0x5EE0), each semitone is computed by multiplying/dividing by
the FP16 constant `_MI-SEMITONE` = 0x3C3D ≈ $2^{1/12}$ ≈ 1.0595.

- Notes 70–127: multiply upward from A4
- Notes 0–68: divide downward from A4

### Hz→Note Search

`MIDI-HZ>NOTE` uses a linear scan finding the note whose table entry
is closest to the input Hz.  Then computes:

$$\text{cents} = \frac{hz - \text{table}[\text{note}]}{\text{table}[\text{note}+1] - \text{table}[\text{note}]} \times 100$$

### Scratch Variables

`_MI-HZ`, `_MI-BEST`, `_MI-BDIST`, `_MI-LO`, `_MI-HI`, `_MI-TADDR`.

---

## Quick Reference

```
MIDI-MSG-NOTE-OFF  ( -- 0 )
MIDI-MSG-NOTE-ON   ( -- 1 )
MIDI-MSG-POLY-AT   ( -- 2 )
MIDI-MSG-CC        ( -- 3 )
MIDI-MSG-PROG      ( -- 4 )
MIDI-MSG-CHAN-AT    ( -- 5 )
MIDI-MSG-BEND      ( -- 6 )

MIDI-NOTE-ON       ( chan note vel -- b1 b2 b3 )
MIDI-NOTE-OFF      ( chan note vel -- b1 b2 b3 )
MIDI-CC            ( chan cc val -- b1 b2 b3 )
MIDI-PITCH-BEND    ( chan bend -- b1 b2 b3 )
MIDI-PROG          ( chan prog -- b1 b2 )

MIDI-PARSE         ( byte state -- type chan d1 d2 flag state' )

MIDI-NOTE>HZ       ( note -- hz )
MIDI-HZ>NOTE       ( hz -- note cents )
```

---

## Cookbook

### Send a note-on to UART

```forth
: MIDI-TX  ( byte -- )  \ your UART write word
    UART-TX! ;

: PLAY-NOTE  ( chan note vel -- )
    MIDI-NOTE-ON
    MIDI-TX MIDI-TX MIDI-TX ;

0 60 100 PLAY-NOTE   \ C4 on channel 0
```

### Parse incoming MIDI stream

```forth
VARIABLE midi-state  0 midi-state !

: ON-MIDI-BYTE  ( byte -- )
    midi-state @ MIDI-PARSE
    midi-state !              \ save state' (TOS)
    IF                        \ flag = -1 means complete
        \ stack: type chan d1 d2
        ." type=" SWAP . ." chan=" SWAP . ." d1=" SWAP . ." d2=" . CR
    ELSE
        DROP DROP DROP DROP   \ incomplete — discard
    THEN ;
```

### Convert note to frequency

```forth
: NOTE-FREQ  ( note -- )
    DUP MIDI-NOTE>HZ
    ." note " SWAP . ." = " FP16. ." Hz" CR ;

69 NOTE-FREQ   \ → note 69 = 440.0 Hz
```
