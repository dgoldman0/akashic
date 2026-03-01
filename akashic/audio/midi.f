\ midi.f — MIDI byte protocol (parse and generate)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Pure data format library for MIDI wire protocol messages.
\ No device I/O, no MIDI file (.mid) reader, no instrument maps.
\ Generates and parses raw MIDI byte messages.
\
\ Also provides MIDI note ↔ Hz conversion using a precomputed
\ 128-entry FP16 lookup table (A4 = 440 Hz standard tuning).
\
\ Supports running status for parsing (status byte reuse).
\
\ Message types:
\   0 = note-off        (3 bytes: status note vel)
\   1 = note-on         (3 bytes: status note vel)
\   2 = poly aftertouch (3 bytes: status note pressure)
\   3 = control change  (3 bytes: status cc value)
\   4 = program change  (2 bytes: status program)
\   5 = chan aftertouch  (2 bytes: status pressure)
\   6 = pitch bend      (3 bytes: status lsb msb)
\
\ Prefix: MIDI-   (public API)
\         _MI-    (internals)
\
\ Load with:   REQUIRE audio/midi.f
\
\ === Public API ===
\   MIDI-NOTE-ON    ( chan note vel -- b1 b2 b3 )
\   MIDI-NOTE-OFF   ( chan note vel -- b1 b2 b3 )
\   MIDI-CC         ( chan cc val -- b1 b2 b3 )
\   MIDI-PITCH-BEND ( chan bend -- b1 b2 b3 )
\   MIDI-PROG       ( chan prog -- b1 b2 )
\   MIDI-PARSE      ( byte state -- state' type chan d1 d2 flag )
\   MIDI-NOTE>HZ    ( note -- hz )
\   MIDI-HZ>NOTE    ( hz -- note cents )

REQUIRE fp16-ext.f

PROVIDED akashic-audio-midi

\ =====================================================================
\  Message type constants
\ =====================================================================

0 CONSTANT MIDI-MSG-NOTE-OFF
1 CONSTANT MIDI-MSG-NOTE-ON
2 CONSTANT MIDI-MSG-POLY-AT
3 CONSTANT MIDI-MSG-CC
4 CONSTANT MIDI-MSG-PROG
5 CONSTANT MIDI-MSG-CHAN-AT
6 CONSTANT MIDI-MSG-PBEND

\ =====================================================================
\  Message generation — Note On
\ =====================================================================
\  ( chan note vel -- b1 b2 b3 )
\  chan: 0–15  note: 0–127  vel: 0–127 (vel 0 = note-off equivalent)

: MIDI-NOTE-ON  ( chan note vel -- b1 b2 b3 )
    >R >R                          \ R: vel note
    0x90 OR                        \ status byte = 0x90 | channel
    R> R> ;                        \ ( status note vel )

\ =====================================================================
\  Message generation — Note Off
\ =====================================================================

: MIDI-NOTE-OFF  ( chan note vel -- b1 b2 b3 )
    >R >R
    0x80 OR
    R> R> ;

\ =====================================================================
\  Message generation — Control Change
\ =====================================================================

: MIDI-CC  ( chan cc val -- b1 b2 b3 )
    >R >R
    0xB0 OR
    R> R> ;

\ =====================================================================
\  Message generation — Pitch Bend
\ =====================================================================
\  bend: −8192 to +8191 (integer)
\  Encoded as 14-bit value: raw = bend + 8192 (0–16383)
\  LSB = raw AND 0x7F, MSB = (raw >> 7) AND 0x7F

: MIDI-PITCH-BEND  ( chan bend -- b1 b2 b3 )
    8192 +                         \ raw 14-bit (0–16383)
    >R
    0xE0 OR                        \ status byte
    R@      127 AND                \ LSB (bits 0–6)
    R> 7 RSHIFT 127 AND ;         \ MSB (bits 7–13)

\ =====================================================================
\  Message generation — Program Change
\ =====================================================================
\  ( chan prog -- b1 b2 )

: MIDI-PROG  ( chan prog -- b1 b2 )
    >R
    0xC0 OR
    R> ;

\ =====================================================================
\  Parser state machine
\ =====================================================================
\
\  State is a single cell encoding:
\     bits 63–16:  unused
\     bits 15–8:   running status byte (0 = none)
\     bits 7–4:    parser phase (0=idle, 1=need-d1, 2=need-d2)
\     bits 3–0:    data1 byte (only valid in phase 2)
\
\  Actually, let's use a simpler approach: state is packed as:
\     (status << 16) | (phase << 8) | data1
\
\  MIDI-PARSE  ( byte state -- type chan d1 d2 flag state' )
\    byte:  next MIDI byte to process
\    state: parser state (0 = initial)
\    Returns:
\      type:   message type (0–6) or -1 if no message yet
\      chan:   channel (0–15) or 0
\      d1:    data byte 1 or 0
\      d2:    data byte 2 or 0
\      flag:  -1 if a complete message was parsed, 0 otherwise
\      state': updated state for next call  (on top for easy _st !)

VARIABLE _MI-BYTE
VARIABLE _MI-STATE
VARIABLE _MI-STATUS
VARIABLE _MI-PHASE
VARIABLE _MI-D1
VARIABLE _MI-D2
VARIABLE _MI-TYPE
VARIABLE _MI-CHAN

\ Internal: extract fields from packed state
: _MI-UNPACK  ( state -- )
    DUP 16 RSHIFT 255 AND _MI-STATUS !
    DUP  8 RSHIFT 255 AND _MI-PHASE !
        255 AND _MI-D1 ! ;

\ Internal: pack fields into state
: _MI-PACK  ( -- state )
    _MI-STATUS @ 255 AND 16 LSHIFT
    _MI-PHASE @  255 AND  8 LSHIFT OR
    _MI-D1 @    255 AND        OR ;

\ Internal: how many data bytes does this status need?
\ Note-off, note-on, poly AT, CC, pitch bend → 2
\ Program change, channel AT → 1
: _MI-DATA-COUNT  ( status -- n )
    0xF0 AND
    DUP 0xC0 = IF DROP 1 EXIT THEN    \ program change
    DUP 0xD0 = IF DROP 1 EXIT THEN    \ channel aftertouch
    DROP 2 ;

\ Internal: classify status byte → message type
: _MI-STATUS>TYPE  ( status -- type )
    0xF0 AND
    DUP 0x80 = IF DROP MIDI-MSG-NOTE-OFF EXIT THEN
    DUP 0x90 = IF DROP MIDI-MSG-NOTE-ON  EXIT THEN
    DUP 0xA0 = IF DROP MIDI-MSG-POLY-AT  EXIT THEN
    DUP 0xB0 = IF DROP MIDI-MSG-CC       EXIT THEN
    DUP 0xC0 = IF DROP MIDI-MSG-PROG     EXIT THEN
    DUP 0xD0 = IF DROP MIDI-MSG-CHAN-AT  EXIT THEN
    DUP 0xE0 = IF DROP MIDI-MSG-PBEND    EXIT THEN
    DROP -1 ;

: MIDI-PARSE  ( byte state -- type chan d1 d2 flag state' )
    _MI-UNPACK
    _MI-BYTE !

    _MI-BYTE @ 128 >= IF
        \ Status byte — update running status
        _MI-BYTE @ 0xF0 >= IF
            \ System message — ignore for now, don't change status
            -1 0 0 0 0 0 EXIT
        THEN
        _MI-BYTE @ _MI-STATUS !
        0 _MI-D1 !
        \ Do we need data?
        _MI-STATUS @ _MI-DATA-COUNT
        DUP 0> IF
            1 _MI-PHASE !         \ need data1
            DROP
            -1 0 0 0 0 _MI-PACK   \ no message yet; state on top
            EXIT
        THEN
        \ 0 data bytes (shouldn't happen for channel msgs)
        DROP 0 _MI-PHASE !
        -1 0 0 0 0 _MI-PACK
        EXIT
    THEN

    \ Data byte
    _MI-STATUS @ 0= IF
        \ No running status — discard
        -1 0 0 0 0 0 EXIT
    THEN

    _MI-PHASE @ 1 = IF
        \ First data byte
        _MI-BYTE @ _MI-D1 !
        _MI-STATUS @ _MI-DATA-COUNT 2 = IF
            \ Need second data byte
            2 _MI-PHASE !
            -1 0 0 0 0 _MI-PACK
            EXIT
        THEN
        \ Only 1 data byte needed — message complete
        _MI-STATUS @ _MI-STATUS>TYPE _MI-TYPE !
        _MI-STATUS @ 0x0F AND _MI-CHAN !
        1 _MI-PHASE !             \ ready for next (running status)
        _MI-TYPE @
        _MI-CHAN @
        _MI-D1 @
        0                         \ d2 = 0 for 1-byte messages
        -1                        \ flag = message complete
        _MI-PACK                  \ state' on top
        EXIT
    THEN

    _MI-PHASE @ 2 = IF
        \ Second data byte — message complete
        _MI-BYTE @ _MI-D2 !
        _MI-STATUS @ _MI-STATUS>TYPE _MI-TYPE !
        _MI-STATUS @ 0x0F AND _MI-CHAN !
        1 _MI-PHASE !             \ ready for next (running status)

        \ Special: note-on with vel=0 → note-off
        _MI-TYPE @ MIDI-MSG-NOTE-ON = _MI-D2 @ 0= AND IF
            MIDI-MSG-NOTE-OFF _MI-TYPE !
        THEN

        _MI-TYPE @
        _MI-CHAN @
        _MI-D1 @
        _MI-D2 @
        -1                        \ flag = message complete
        _MI-PACK                  \ state' on top
        EXIT
    THEN

    \ Unexpected phase — treat as running status data1
    _MI-BYTE @ _MI-D1 !
    1 _MI-PHASE !
    -1 0 0 0 0 _MI-PACK ;

\ =====================================================================
\  MIDI note → Hz conversion
\ =====================================================================
\  f = 440 × 2^((note − 69) / 12)
\
\  Precomputed table of 128 FP16 values.  Built at load time
\  using FP16 arithmetic for reasonable accuracy.
\
\  Strategy: compute from A4 (note 69 = 440 Hz) using repeated
\  multiplication by the 12th root of 2 ≈ 1.05946.
\  FP16 for 1.05946 ≈ 0x3CCF.
\
\  We build the table by:
\   1. Set note 69 = 440 Hz
\   2. For notes 70–127: multiply by semitone ratio
\   3. For notes 68–0: divide by semitone ratio

VARIABLE _MI-TADDR    \ table base address
VARIABLE _MI-TVAL     \ current frequency value

\ Semitone ratio ≈ 1.05946
\ FP16: 1.05946 ≈ 0x3CCE  (exact: 2^(1/12))
\ More precisely: we'll compute it as 1059 / 1000 in FP16
\ or just use the pre-known bit pattern.

0x3C3D CONSTANT _MI-SEMITONE

: _MI-BUILD-TABLE  ( -- )
    \ Allocate 128 cells for the table
    128 CELLS ALLOCATE
    0<> ABORT" MIDI: note table alloc failed"
    _MI-TADDR !

    \ Set A4 = 440 Hz
    440 INT>FP16 _MI-TVAL !
    _MI-TVAL @  _MI-TADDR @  69 CELLS +  !

    \ Build upward: notes 70–127
    _MI-TVAL @
    128 70 DO
        _MI-SEMITONE FP16-MUL
        DUP _MI-TADDR @ I CELLS + !
    LOOP
    DROP

    \ Build downward: notes 68–0
    _MI-TVAL @                     \ start from 440 again
    69 0 DO
        _MI-SEMITONE FP16-DIV
        DUP _MI-TADDR @ 68 I - CELLS + !
    LOOP
    DROP ;

\ Build the table now (at load time)
_MI-BUILD-TABLE

\ =====================================================================
\  MIDI-NOTE>HZ — Look up frequency for MIDI note
\ =====================================================================
\  ( note -- hz )
\  note: 0–127.  Returns FP16 Hz value.

: MIDI-NOTE>HZ  ( note -- hz )
    0 MAX 127 MIN
    CELLS _MI-TADDR @ + @ ;

\ =====================================================================
\  MIDI-HZ>NOTE — Convert frequency to nearest MIDI note + cents
\ =====================================================================
\  ( hz -- note cents )
\  hz: FP16 frequency.  Finds nearest note by linear scan of table.
\  cents: signed deviation (-50 to +50 range, as integer).
\
\  Simple approach: scan the table, find the two adjacent entries
\  that bracket the target frequency, pick the closer one.

VARIABLE _MI-HZ
VARIABLE _MI-BEST
VARIABLE _MI-BDIST
VARIABLE _MI-CDIST
VARIABLE _MI-LO
VARIABLE _MI-HI

: MIDI-HZ>NOTE  ( hz -- note cents )
    _MI-HZ !
    0 _MI-BEST !
    0x7BFF _MI-BDIST !        \ FP16 max positive

    128 0 DO
        I CELLS _MI-TADDR @ + @   \ table entry
        _MI-HZ @ FP16-SUB FP16-ABS
        DUP _MI-BDIST @ FP16-LT IF
            _MI-BDIST !
            I _MI-BEST !
        ELSE
            DROP
        THEN
    LOOP

    \ Compute cents deviation
    \ cents = 1200 × log2(hz / table[note])
    \ Approximation: linear interpolation between adjacent semitones.
    \ cents ≈ (hz − table[note]) / (table[note+1] − table[note]) × 100
    _MI-BEST @                     \ note
    DUP 127 >= IF
        0                          \ no upper neighbor — 0 cents
    ELSE
        DUP CELLS _MI-TADDR @ + @      \ table[note]
        _MI-LO !
        DUP 1+ CELLS _MI-TADDR @ + @   \ table[note+1]
        _MI-HI !
        \ width = table[note+1] - table[note]
        _MI-HI @ _MI-LO @ FP16-SUB
        \ offset = hz - table[note]
        _MI-HZ @ _MI-LO @ FP16-SUB
        SWAP FP16-DIV                  \ offset / width = fraction
        100 INT>FP16 FP16-MUL         \ × 100
        FP16>INT                       \ integer cents
    THEN ;
