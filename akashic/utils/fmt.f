\ =================================================================
\  fmt.f  —  Formatting Utilities
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: FMT-  / _FMT-
\  No dependencies (pure KDOS).
\
\  Hex printing and formatting primitives used across the Akashic
\  library.  Provides a canonical set of words so individual modules
\  do not need to define their own private nibble/hex routines.
\
\  Public API:
\   FMT-NIB>C        ( n -- c )            nibble (0-15) to hex char
\   FMT-.NIB         ( n -- )              emit one hex nibble
\   FMT-.BYTE        ( b -- )              emit one byte as 2 hex chars
\   FMT-.HEX         ( addr n -- )         emit n bytes as lowercase hex
\   FMT->HEX         ( src n dst -- n*2 )  write n bytes as hex string
\   FMT-U.H          ( u -- )              emit cell as 16 hex chars
\   FMT-U.H4         ( u -- )              emit cell as 8 hex chars (low 32 bits)
\   FMT-.HEXDUMP     ( addr n -- )         16-byte/line hex dump + ASCII
\
\  Not reentrant (scratch VARIABLEs).
\ =================================================================

REQUIRE fmt.f
PROVIDED akashic-fmt

\ =====================================================================
\  1. Hex lookup table — "0123456789abcdef"
\ =====================================================================

CREATE _FMT-HEX
  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
  56 C, 57 C, 97 C, 98 C, 99 C, 100 C, 101 C, 102 C,

\ =====================================================================
\  2. Core primitives
\ =====================================================================

\ FMT-NIB>C ( n -- c )  Convert nibble 0..15 to ASCII hex char.
: FMT-NIB>C  ( n -- c )
    0x0F AND _FMT-HEX + C@ ;

\ FMT-.NIB ( n -- )  Emit one hex nibble.
: FMT-.NIB  ( n -- )
    FMT-NIB>C EMIT ;

\ FMT-.BYTE ( b -- )  Emit one byte as two lowercase hex chars.
: FMT-.BYTE  ( b -- )
    DUP 4 RSHIFT FMT-.NIB
    0x0F AND FMT-.NIB ;

\ =====================================================================
\  3. Multi-byte hex display
\ =====================================================================

\ FMT-.HEX ( addr n -- )  Emit n bytes starting at addr as hex.
: FMT-.HEX  ( addr n -- )
    0 ?DO
        DUP I + C@ FMT-.BYTE
    LOOP
    DROP ;

\ =====================================================================
\  4. Hex string builder (write to buffer, no EMIT)
\ =====================================================================

VARIABLE _FMT-DST

\ FMT->HEX ( src n dst -- n*2 )  Write n bytes from src as hex to dst.
\   Returns the number of chars written (always n*2).
: FMT->HEX  ( src n dst -- n*2 )
    _FMT-DST !
    DUP 2* >R                     \ save result
    0 ?DO
        DUP I + C@
        DUP 4 RSHIFT FMT-NIB>C
        _FMT-DST @ C!  1 _FMT-DST +!
        0x0F AND FMT-NIB>C
        _FMT-DST @ C!  1 _FMT-DST +!
    LOOP
    DROP R> ;

\ =====================================================================
\  5. Cell-as-hex display
\ =====================================================================

\ FMT-U.H ( u -- )  Emit a full 64-bit cell as 16 lowercase hex chars
\   (big-endian byte order, most-significant byte first).
: FMT-U.H  ( u -- )
    8 0 DO
        DUP 56 I 8 * - RSHIFT 0xFF AND FMT-.BYTE
    LOOP
    DROP ;

\ FMT-U.H4 ( u -- )  Emit low 32 bits as 8 lowercase hex chars.
: FMT-U.H4  ( u -- )
    4 0 DO
        DUP 24 I 8 * - RSHIFT 0xFF AND FMT-.BYTE
    LOOP
    DROP ;

\ =====================================================================
\  6. HEXDUMP — 16 bytes per line with ASCII sidebar
\ =====================================================================
\
\  Example output:
\    00000000  48 65 6c 6c 6f 20 57 6f  72 6c 64 00 .. .. .. ..  |Hello World.....|
\

VARIABLE _FMT-HD-BASE
VARIABLE _FMT-HD-LEN
VARIABLE _FMT-HD-OFF    \ current line offset
VARIABLE _FMT-HD-COL    \ column within line

: _FMT-HD-ASCII  ( addr n -- )
    ." |"
    0 ?DO
        DUP I + C@
        DUP 0x20 < OVER 0x7E > OR IF DROP 46 THEN EMIT
    LOOP
    DROP ." |" ;

: FMT-.HEXDUMP  ( addr n -- )
    _FMT-HD-LEN !  _FMT-HD-BASE !
    0 _FMT-HD-OFF !
    BEGIN _FMT-HD-OFF @ _FMT-HD-LEN @ < WHILE
        \ Line offset
        _FMT-HD-OFF @ FMT-U.H4  ."   "
        \ Hex bytes (up to 16)
        0 _FMT-HD-COL !
        BEGIN _FMT-HD-COL @ 16 < WHILE
            _FMT-HD-OFF @ _FMT-HD-COL @ + _FMT-HD-LEN @ < IF
                _FMT-HD-BASE @ _FMT-HD-OFF @ + _FMT-HD-COL @ + C@
                FMT-.BYTE
            ELSE
                ." .."
            THEN
            _FMT-HD-COL @ 7 = IF ."  " ELSE ." " THEN
            1 _FMT-HD-COL +!
        REPEAT
        ."  "
        \ ASCII sidebar
        _FMT-HD-BASE @ _FMT-HD-OFF @ +
        _FMT-HD-LEN @ _FMT-HD-OFF @ - 16 MIN
        _FMT-HD-ASCII
        CR
        16 _FMT-HD-OFF +!
    REPEAT ;

\ =====================================================================
\  Done.
\ =====================================================================
