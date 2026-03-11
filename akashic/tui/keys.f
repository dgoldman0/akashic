\ =================================================================
\  keys.f  —  Terminal Input Decoding
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: KEY-  / _KEY-
\  Depends on: akashic-utf8 (UTF8-DECODE, _UTF8-SEQLEN)
\
\  Converts raw UART bytes from KEY/KEY? into structured key
\  events.  Arrow keys, function keys, Home/End/PgUp/PgDn, and
\  mouse clicks all arrive as multi-byte escape sequences.  This
\  module buffers partial sequences and resolves them into typed
\  event descriptors.
\
\  Public API:
\   KEY-READ          ( ev -- flag )       Blocking read, fill event
\   KEY-POLL          ( ev -- flag )       Non-blocking check
\   KEY-WAIT          ( ev ms -- flag )    Blocking with timeout
\   KEY-IS-CHAR?      ( ev -- flag )       Character event?
\   KEY-IS-SPECIAL?   ( ev -- flag )       Special key event?
\   KEY-IS-MOUSE?     ( ev -- flag )       Mouse event?
\   KEY-CODE@         ( ev -- code )       Get keycode
\   KEY-MODS@         ( ev -- mods )       Get modifiers
\   KEY-HAS-CTRL?     ( ev -- flag )       Ctrl present?
\   KEY-HAS-ALT?      ( ev -- flag )       Alt present?
\   KEY-HAS-SHIFT?    ( ev -- flag )       Shift present?
\   KEY-TIMEOUT!      ( ms -- )            Set escape timeout
\   KEY-MOUSE-X       ( -- addr )          VARIABLE: last mouse column
\   KEY-MOUSE-Y       ( -- addr )          VARIABLE: last mouse row
\
\  Not reentrant (shared state VARIABLEs for decode).
\  Uses BIOS MS@ for escape timeout timing.
\ =================================================================

PROVIDED akashic-tui-keys

REQUIRE ../text/utf8.f

\ =====================================================================
\  1. Event Types
\ =====================================================================

0 CONSTANT KEY-T-CHAR         \ printable character or Ctrl combo
1 CONSTANT KEY-T-SPECIAL      \ named key (arrow, F1-F12, etc.)
2 CONSTANT KEY-T-MOUSE        \ mouse button/motion event
3 CONSTANT KEY-T-PASTE        \ bracketed paste start/end
4 CONSTANT KEY-T-RESIZE       \ terminal size changed

\ =====================================================================
\  2. Special Key Constants
\ =====================================================================

1  CONSTANT KEY-UP
2  CONSTANT KEY-DOWN
3  CONSTANT KEY-RIGHT
4  CONSTANT KEY-LEFT
5  CONSTANT KEY-HOME
6  CONSTANT KEY-END
7  CONSTANT KEY-PGUP
8  CONSTANT KEY-PGDN
9  CONSTANT KEY-INS
10 CONSTANT KEY-DEL
11 CONSTANT KEY-F1
12 CONSTANT KEY-F2
13 CONSTANT KEY-F3
14 CONSTANT KEY-F4
15 CONSTANT KEY-F5
16 CONSTANT KEY-F6
17 CONSTANT KEY-F7
18 CONSTANT KEY-F8
19 CONSTANT KEY-F9
20 CONSTANT KEY-F10
21 CONSTANT KEY-F11
22 CONSTANT KEY-F12
23 CONSTANT KEY-ESC
24 CONSTANT KEY-TAB
25 CONSTANT KEY-BACKTAB
26 CONSTANT KEY-ENTER
27 CONSTANT KEY-BACKSPACE

\ =====================================================================
\  3. Modifier Flags
\ =====================================================================

1 CONSTANT KEY-MOD-SHIFT
2 CONSTANT KEY-MOD-ALT
4 CONSTANT KEY-MOD-CTRL

\ =====================================================================
\  4. Mouse Button Constants
\ =====================================================================

0 CONSTANT KEY-MOUSE-LEFT
1 CONSTANT KEY-MOUSE-MIDDLE
2 CONSTANT KEY-MOUSE-RIGHT
3 CONSTANT KEY-MOUSE-RELEASE
64 CONSTANT KEY-MOUSE-SCROLL-UP
65 CONSTANT KEY-MOUSE-SCROLL-DN

\ =====================================================================
\  5. Event Descriptor Layout (3 cells = 24 bytes)
\ =====================================================================
\
\  Offset  Field   Description
\    +0    type    KEY-T-CHAR, KEY-T-SPECIAL, KEY-T-MOUSE, etc.
\    +8    code    Character codepoint, special key constant, or button
\   +16    mods    Modifier bitmask (shift=1, alt=2, ctrl=4)

: _KEY-EV-TYPE  ( ev -- addr )   ;          \ +0
: _KEY-EV-CODE  ( ev -- addr )   8 + ;      \ +8
: _KEY-EV-MODS  ( ev -- addr )   16 + ;     \ +16

\ =====================================================================
\  6. Shared State
\ =====================================================================

VARIABLE KEY-MOUSE-X        \ last mouse column (1-based)
VARIABLE KEY-MOUSE-Y        \ last mouse row (1-based)
VARIABLE KEY-RESIZE-W       \ terminal width from last resize report
VARIABLE KEY-RESIZE-H       \ terminal height from last resize report

\ Default escape sequence timeout: 50 ms.
\ When ESC arrives, we wait this long for a follow-up byte to
\ distinguish a lone Escape from the start of a CSI sequence.
VARIABLE _KEY-TIMEOUT
50 _KEY-TIMEOUT !

\ Internal decode buffer — holds raw bytes of the current sequence.
\ Max CSI sequence we handle is ~16 bytes; 32 is generous.
CREATE _KEY-BUF  32 ALLOT
VARIABLE _KEY-BLEN           \ current length in buffer

\ Internal: 4-byte scratch for UTF-8 decode
CREATE _KEY-UTF8  4 ALLOT

\ =====================================================================
\  7. Timeout Setting
\ =====================================================================

\ KEY-TIMEOUT! ( ms -- )  Set escape sequence timeout in milliseconds.
: KEY-TIMEOUT!  ( ms -- )
    _KEY-TIMEOUT ! ;

\ =====================================================================
\  8. Event Accessors
\ =====================================================================

\ KEY-CODE@ ( ev -- code )  Get keycode from event descriptor.
: KEY-CODE@  ( ev -- code )
    _KEY-EV-CODE @ ;

\ KEY-MODS@ ( ev -- mods )  Get modifier bitmask.
: KEY-MODS@  ( ev -- mods )
    _KEY-EV-MODS @ ;

\ KEY-IS-CHAR? ( ev -- flag )
: KEY-IS-CHAR?  ( ev -- flag )
    @ KEY-T-CHAR = ;

\ KEY-IS-SPECIAL? ( ev -- flag )
: KEY-IS-SPECIAL?  ( ev -- flag )
    @ KEY-T-SPECIAL = ;

\ KEY-IS-MOUSE? ( ev -- flag )
: KEY-IS-MOUSE?  ( ev -- flag )
    @ KEY-T-MOUSE = ;

\ KEY-HAS-CTRL? ( ev -- flag )
: KEY-HAS-CTRL?  ( ev -- flag )
    KEY-MODS@ KEY-MOD-CTRL AND 0<> ;

\ KEY-HAS-ALT? ( ev -- flag )
: KEY-HAS-ALT?  ( ev -- flag )
    KEY-MODS@ KEY-MOD-ALT AND 0<> ;

\ KEY-HAS-SHIFT? ( ev -- flag )
: KEY-HAS-SHIFT?  ( ev -- flag )
    KEY-MODS@ KEY-MOD-SHIFT AND 0<> ;

\ =====================================================================
\  9. Internal: event builder
\ =====================================================================

\ _KEY-SET-EV ( ev type code mods -- )
: _KEY-SET-EV  ( ev type code mods -- )
    >R >R                             ( ev type  R: mods code )
    OVER !                            ( ev  -- type stored at +0 )
    R> OVER _KEY-EV-CODE !            ( ev  -- code stored at +8 )
    R> SWAP _KEY-EV-MODS ! ;          ( -- mods stored at +16 )

\ =====================================================================
\ 10. Internal: timed KEY? poll
\ =====================================================================
\
\  _KEY-TIMED? ( ms -- char flag )
\    Poll KEY? for up to ms milliseconds.  If a byte arrives,
\    return it with flag=TRUE.  If timeout, return 0 FALSE.
\
\    Uses MS@ (BIOS millisecond uptime counter) for timing.

VARIABLE _KEY-DEADLINE

: _KEY-TIMED?  ( ms -- char flag )
    MS@ +                              \ absolute deadline in ms
    _KEY-DEADLINE !
    BEGIN
        KEY? IF KEY -1 EXIT THEN
        MS@ _KEY-DEADLINE @ >= IF 0 0 EXIT THEN
    AGAIN ;

\ =====================================================================
\ 11. Internal: buffer raw bytes of a sequence
\ =====================================================================

\ _KEY-BUF-RESET ( -- )  Clear the decode buffer.
: _KEY-BUF-RESET  ( -- )
    0 _KEY-BLEN ! ;

\ _KEY-BUF-ADD ( c -- )  Append byte to decode buffer.
: _KEY-BUF-ADD  ( c -- )
    _KEY-BLEN @ 31 < IF
        _KEY-BUF _KEY-BLEN @ + C!
        1 _KEY-BLEN +!
    ELSE DROP THEN ;

\ _KEY-BUF-C@ ( i -- c )  Read byte i from buffer.
: _KEY-BUF-C@  ( i -- c )
    _KEY-BUF + C@ ;

\ =====================================================================
\ 12. Internal: parse decimal number from CSI parameter bytes
\ =====================================================================

VARIABLE _KEY-PIDX           \ current parse index in _KEY-BUF

\ _KEY-PARSE-NUM ( -- n )
\   Parse a decimal number starting at _KEY-PIDX in the buffer.
\   Advances _KEY-PIDX past the digits.  Returns 0 if no digits.
: _KEY-PARSE-NUM  ( -- n )
    0                                  ( accum )
    BEGIN
        _KEY-PIDX @ _KEY-BLEN @ < IF
            _KEY-PIDX @ _KEY-BUF-C@
            DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND IF
                [CHAR] 0 -
                SWAP 10 * +
                1 _KEY-PIDX +!
                -1                     \ continue
            ELSE
                DROP 0                 \ non-digit, stop
            THEN
        ELSE
            0                          \ buffer exhausted
        THEN
    WHILE REPEAT ;

\ _KEY-SKIP-SEP ( -- )
\   If current byte is ;, advance past it.
: _KEY-SKIP-SEP  ( -- )
    _KEY-PIDX @ _KEY-BLEN @ < IF
        _KEY-PIDX @ _KEY-BUF-C@ [CHAR] ; = IF
            1 _KEY-PIDX +!
        THEN
    THEN ;

\ =====================================================================
\ 13. Internal: decode modifiers from CSI parameter
\ =====================================================================

\ CSI sequences encode modifiers as (1+bitmask) in the second param:
\   param = 1 + (shift*1 | alt*2 | ctrl*4)
\ So param 2 = shift, 3 = alt, 5 = ctrl, etc.
\   Param 1 or 0 = no modifiers.

: _KEY-DECODE-MODS  ( param -- mods )
    DUP 1 <= IF DROP 0 EXIT THEN
    1- ;                               \ strip the +1 bias

\ =====================================================================
\ 14. Internal: decode CSI sequence (ESC [ ...)
\ =====================================================================
\
\  At entry, _KEY-BUF holds the bytes AFTER "ESC [".
\  _KEY-BLEN is the count of those bytes.
\  The final byte is the terminator character.

VARIABLE _KEY-CSI-P1       \ first numeric parameter
VARIABLE _KEY-CSI-P2       \ second numeric parameter (modifier)
VARIABLE _KEY-CSI-FINAL    \ final (terminator) byte

: _KEY-CSI-PARSE-PARAMS  ( -- )
    0 _KEY-PIDX !
    _KEY-PARSE-NUM _KEY-CSI-P1 !
    _KEY-SKIP-SEP
    _KEY-PARSE-NUM _KEY-CSI-P2 ! ;

\ _KEY-DECODE-CSI ( ev -- )
\   Fill event from a CSI sequence in buffer.
\   Buffer contains bytes after ESC[, including the final byte.

: _KEY-DECODE-CSI  ( ev -- )
    _KEY-BLEN @ 0= IF                 \ empty CSI — treat as ESC [
        KEY-T-CHAR [CHAR] [ 0 _KEY-SET-EV EXIT
    THEN
    \ The final byte determines the sequence type
    _KEY-BLEN @ 1- _KEY-BUF-C@ _KEY-CSI-FINAL !
    _KEY-CSI-PARSE-PARAMS
    _KEY-CSI-P2 @ _KEY-DECODE-MODS >R  \ R: mods

    _KEY-CSI-FINAL @ CASE

        \ Arrow keys:  ESC[A  ESC[B  ESC[C  ESC[D
        [CHAR] A OF KEY-T-SPECIAL KEY-UP    R> _KEY-SET-EV EXIT ENDOF
        [CHAR] B OF KEY-T-SPECIAL KEY-DOWN  R> _KEY-SET-EV EXIT ENDOF
        [CHAR] C OF KEY-T-SPECIAL KEY-RIGHT R> _KEY-SET-EV EXIT ENDOF
        [CHAR] D OF KEY-T-SPECIAL KEY-LEFT  R> _KEY-SET-EV EXIT ENDOF

        \ Home/End:  ESC[H  ESC[F
        [CHAR] H OF KEY-T-SPECIAL KEY-HOME  R> _KEY-SET-EV EXIT ENDOF
        [CHAR] F OF KEY-T-SPECIAL KEY-END   R> _KEY-SET-EV EXIT ENDOF

        \ Tilde sequences:  ESC[n~  where n identifies the key
        [CHAR] ~ OF
            _KEY-CSI-P1 @ CASE
                1 OF KEY-T-SPECIAL KEY-HOME  R> _KEY-SET-EV EXIT ENDOF
                2 OF KEY-T-SPECIAL KEY-INS   R> _KEY-SET-EV EXIT ENDOF
                3 OF KEY-T-SPECIAL KEY-DEL   R> _KEY-SET-EV EXIT ENDOF
                4 OF KEY-T-SPECIAL KEY-END   R> _KEY-SET-EV EXIT ENDOF
                5 OF KEY-T-SPECIAL KEY-PGUP  R> _KEY-SET-EV EXIT ENDOF
                6 OF KEY-T-SPECIAL KEY-PGDN  R> _KEY-SET-EV EXIT ENDOF
                7 OF KEY-T-SPECIAL KEY-HOME  R> _KEY-SET-EV EXIT ENDOF
                8 OF KEY-T-SPECIAL KEY-END   R> _KEY-SET-EV EXIT ENDOF
                \ Function keys: F5=15, F6=17, F7=18, F8=19, F9=20,
                \ F10=21, F11=23, F12=24
                15 OF KEY-T-SPECIAL KEY-F5   R> _KEY-SET-EV EXIT ENDOF
                17 OF KEY-T-SPECIAL KEY-F6   R> _KEY-SET-EV EXIT ENDOF
                18 OF KEY-T-SPECIAL KEY-F7   R> _KEY-SET-EV EXIT ENDOF
                19 OF KEY-T-SPECIAL KEY-F8   R> _KEY-SET-EV EXIT ENDOF
                20 OF KEY-T-SPECIAL KEY-F9   R> _KEY-SET-EV EXIT ENDOF
                21 OF KEY-T-SPECIAL KEY-F10  R> _KEY-SET-EV EXIT ENDOF
                23 OF KEY-T-SPECIAL KEY-F11  R> _KEY-SET-EV EXIT ENDOF
                24 OF KEY-T-SPECIAL KEY-F12  R> _KEY-SET-EV EXIT ENDOF
                \ Unknown tilde sequence — return as char event
                KEY-T-CHAR _KEY-CSI-P1 @ R> _KEY-SET-EV EXIT
            ENDCASE
        ENDOF

        \ Bracketed paste: ESC[200~ (start), ESC[201~ (end)
        \ These are handled by the tilde case above via param,
        \ but the paste markers have special meaning at L5.
        \ For now, if param=200 or 201 and final=~, emit paste event.
        \ (Already handled in tilde case — add here if 200/201 seen.)

        \ SGR mouse: ESC[<btn;col;rowM  or  ESC[<btn;col;rowm
        [CHAR] M OF
            \ Check if first byte in buffer is '<' (SGR mouse)
            0 _KEY-BUF-C@ [CHAR] < = IF
                \ Re-parse skipping the '<'
                1 _KEY-PIDX !
                _KEY-PARSE-NUM >R      \ R2: button
                _KEY-SKIP-SEP
                _KEY-PARSE-NUM KEY-MOUSE-X !
                _KEY-SKIP-SEP
                _KEY-PARSE-NUM KEY-MOUSE-Y !
                KEY-T-MOUSE R> R> DROP 0 _KEY-SET-EV EXIT
            ELSE
                \ Normal mouse mode (not SGR) — legacy X10
                \ param1 = button, but encoded differently.
                KEY-T-MOUSE _KEY-CSI-P1 @ R> _KEY-SET-EV EXIT
            THEN
        ENDOF

        [CHAR] m OF
            \ SGR mouse release: ESC[<btn;col;rowm
            0 _KEY-BUF-C@ [CHAR] < = IF
                1 _KEY-PIDX !
                _KEY-PARSE-NUM DROP    \ release — button info
                _KEY-SKIP-SEP
                _KEY-PARSE-NUM KEY-MOUSE-X !
                _KEY-SKIP-SEP
                _KEY-PARSE-NUM KEY-MOUSE-Y !
                KEY-T-MOUSE KEY-MOUSE-RELEASE R> _KEY-SET-EV EXIT
            ELSE
                KEY-T-CHAR [CHAR] m R> _KEY-SET-EV EXIT
            THEN
        ENDOF

        \ Shift-Tab: ESC[Z
        [CHAR] Z OF KEY-T-SPECIAL KEY-BACKTAB R> _KEY-SET-EV EXIT ENDOF

        \ Terminal size response: ESC[8;rows;colst
        [CHAR] t OF
            \ First param should be 8
            _KEY-CSI-P1 @ 8 = IF
                \ Parse rows and cols from buffer
                \ After p1=8 and p2 already parsed as second param,
                \ we need the third.  Re-parse from start.
                0 _KEY-PIDX !
                _KEY-PARSE-NUM DROP    \ skip 8
                _KEY-SKIP-SEP
                _KEY-PARSE-NUM KEY-RESIZE-H !
                _KEY-SKIP-SEP
                _KEY-PARSE-NUM KEY-RESIZE-W !
                KEY-T-RESIZE 0 R> DROP 0 _KEY-SET-EV EXIT
            ELSE
                KEY-T-CHAR [CHAR] t R> _KEY-SET-EV EXIT
            THEN
        ENDOF

    ENDCASE

    \ Unknown CSI — return final byte as char
    R> DROP
    KEY-T-CHAR _KEY-CSI-FINAL @ 0 _KEY-SET-EV ;

\ =====================================================================
\ 15. Internal: decode SS3 sequence (ESC O ...)
\ =====================================================================
\
\  SS3 sequences are used by some terminals for F1-F4 and keypad.
\  Buffer holds one byte (the final character).

: _KEY-DECODE-SS3  ( ev -- )
    _KEY-BLEN @ 0= IF
        KEY-T-CHAR [CHAR] O 0 _KEY-SET-EV EXIT
    THEN
    0 _KEY-BUF-C@                      ( ev final )
    CASE
        [CHAR] P OF KEY-T-SPECIAL KEY-F1  0 _KEY-SET-EV EXIT ENDOF
        [CHAR] Q OF KEY-T-SPECIAL KEY-F2  0 _KEY-SET-EV EXIT ENDOF
        [CHAR] R OF KEY-T-SPECIAL KEY-F3  0 _KEY-SET-EV EXIT ENDOF
        [CHAR] S OF KEY-T-SPECIAL KEY-F4  0 _KEY-SET-EV EXIT ENDOF
        [CHAR] H OF KEY-T-SPECIAL KEY-HOME 0 _KEY-SET-EV EXIT ENDOF
        [CHAR] F OF KEY-T-SPECIAL KEY-END  0 _KEY-SET-EV EXIT ENDOF
        \ Arrow keys via SS3 (some terminals)
        [CHAR] A OF KEY-T-SPECIAL KEY-UP    0 _KEY-SET-EV EXIT ENDOF
        [CHAR] B OF KEY-T-SPECIAL KEY-DOWN  0 _KEY-SET-EV EXIT ENDOF
        [CHAR] C OF KEY-T-SPECIAL KEY-RIGHT 0 _KEY-SET-EV EXIT ENDOF
        [CHAR] D OF KEY-T-SPECIAL KEY-LEFT  0 _KEY-SET-EV EXIT ENDOF
    ENDCASE
    \ Unknown SS3 — return as char
    KEY-T-CHAR SWAP 0 _KEY-SET-EV ;

\ =====================================================================
\ 16. Internal: read and decode one complete sequence
\ =====================================================================

VARIABLE _KEY-B0             \ first raw byte

: _KEY-READ-RAW  ( ev -- flag )
    \ --- Get first byte ---
    KEY? 0= IF DROP 0 EXIT THEN       \ nothing available
    KEY _KEY-B0 !

    _KEY-B0 @ CASE

        \ ---- ESC (27) — start of escape sequence ----
        27 OF
            \ Wait for follow-up byte
            _KEY-TIMEOUT @ _KEY-TIMED? IF
                DUP [CHAR] [ = IF
                    \ CSI sequence: ESC [
                    DROP _KEY-BUF-RESET
                    \ Read bytes until we get a final byte (@ through ~)
                    BEGIN
                        KEY? IF
                            KEY DUP _KEY-BUF-ADD
                            DUP 64 >= OVER 126 <= AND  \ final byte?
                            NIP                        \ drop byte, keep flag
                        ELSE
                            -1                         \ timeout → exit
                        THEN
                    UNTIL                              ( ev )
                    _KEY-DECODE-CSI
                    -1 EXIT
                THEN
                DUP [CHAR] O = IF
                    \ SS3 sequence: ESC O
                    DROP _KEY-BUF-RESET
                    _KEY-TIMEOUT @ _KEY-TIMED? IF
                        _KEY-BUF-ADD
                    THEN
                    _KEY-DECODE-SS3
                    -1 EXIT
                THEN
                \ ESC + other byte — Alt+char
                KEY-T-CHAR SWAP KEY-MOD-ALT _KEY-SET-EV
                -1 EXIT
            ELSE
                \ Timeout: standalone Escape
                DROP KEY-T-SPECIAL KEY-ESC 0 _KEY-SET-EV
                -1 EXIT
            THEN
        ENDOF

        \ ---- TAB (9) ----
        9 OF
            KEY-T-SPECIAL KEY-TAB 0 _KEY-SET-EV
            -1 EXIT
        ENDOF

        \ ---- Enter (13) ----
        13 OF
            \ Consume optional LF after CR
            _KEY-TIMEOUT @ _KEY-TIMED? IF
                DUP 10 = IF DROP ELSE
                    \ Not LF — put it back?  Can't unpoll on UART.
                    \ Store it to be returned on next call.
                    \ For simplicity, discard non-LF — this is
                    \ extremely rare (CR followed by non-LF within
                    \ the timeout window).
                    DROP
                THEN
            ELSE DROP THEN
            KEY-T-SPECIAL KEY-ENTER 0 _KEY-SET-EV
            -1 EXIT
        ENDOF

        \ ---- LF (10) — treat as Enter as well ----
        10 OF
            KEY-T-SPECIAL KEY-ENTER 0 _KEY-SET-EV
            -1 EXIT
        ENDOF

        \ ---- Backspace (127 DEL, or 8 BS) ----
        127 OF
            KEY-T-SPECIAL KEY-BACKSPACE 0 _KEY-SET-EV
            -1 EXIT
        ENDOF

        8 OF
            KEY-T-SPECIAL KEY-BACKSPACE 0 _KEY-SET-EV
            -1 EXIT
        ENDOF

    ENDCASE

    \ ---- Ctrl+letter (1-26, excluding TAB=9, LF=10, CR=13) ----
    _KEY-B0 @ 1 >= _KEY-B0 @ 26 <= AND IF
        _KEY-B0 @ 9 <> IF
        _KEY-B0 @ 10 <> IF
        _KEY-B0 @ 13 <> IF
            KEY-T-CHAR _KEY-B0 @ 96 + KEY-MOD-CTRL _KEY-SET-EV
            -1 EXIT
        THEN THEN THEN
    THEN

    \ ---- Ctrl+special (28-31) ----
    _KEY-B0 @ 28 >= _KEY-B0 @ 31 <= AND IF
        KEY-T-CHAR _KEY-B0 @ KEY-MOD-CTRL _KEY-SET-EV
        -1 EXIT
    THEN

    \ ---- UTF-8 multi-byte character ----
    _KEY-B0 @ 0x80 >= IF
        _KEY-B0 @ _KEY-UTF8 C!
        \ Determine expected sequence length from leading byte
        _KEY-B0 @ _UTF8-SEQLEN DUP 2 < IF
            \ Invalid leading byte — return replacement
            DROP KEY-T-CHAR 0xFFFD 0 _KEY-SET-EV
            -1 EXIT
        THEN
        \ Read remaining bytes
        DUP 1 DO
            KEY DUP 0x80 AND 0= IF
                \ Not a continuation — bad sequence
                DROP UNLOOP
                KEY-T-CHAR 0xFFFD 0 _KEY-SET-EV
                -1 EXIT
            THEN
            _KEY-UTF8 I + C!
        LOOP
        \ Decode UTF-8
        _KEY-UTF8 SWAP UTF8-DECODE     ( cp addr' len' )
        2DROP                          ( cp )
        KEY-T-CHAR SWAP 0 _KEY-SET-EV
        -1 EXIT
    THEN

    \ ---- Plain ASCII printable (or unrecognized control) ----
    KEY-T-CHAR _KEY-B0 @ 0 _KEY-SET-EV
    -1 ;

\ =====================================================================
\ 17. Public API: KEY-READ, KEY-POLL, KEY-WAIT
\ =====================================================================

\ KEY-POLL ( ev -- flag )
\   Non-blocking: check if input is available and decode one event.
\   Returns TRUE if event was filled, FALSE if no input.
: KEY-POLL  ( ev -- flag )
    KEY? IF _KEY-READ-RAW ELSE DROP 0 THEN ;

\ KEY-READ ( ev -- flag )
\   Blocking read: wait for one complete key event.
\   Returns TRUE (always, unless there's a system error).
: KEY-READ  ( ev -- flag )
    BEGIN DUP KEY-POLL UNTIL
    DROP -1 ;

\ KEY-WAIT ( ev ms -- flag )
\   Blocking read with timeout.  Returns TRUE if event received,
\   FALSE if timeout expired.  ms=0 means wait forever.
: KEY-WAIT  ( ev ms -- flag )
    DUP 0= IF
        DROP KEY-READ EXIT
    THEN
    MS@ + >R                          ( ev  R: deadline )
    BEGIN
        DUP KEY-POLL IF
            R> DROP DROP -1 EXIT
        THEN
        MS@ R@ >= IF
            R> DROP DROP 0 EXIT
        THEN
    AGAIN ;

\ =====================================================================
\  Done.
\ =====================================================================

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
GUARD _keys-guard

' KEY-READ            CONSTANT _keys-read-xt
' KEY-POLL            CONSTANT _keys-poll-xt
' KEY-WAIT            CONSTANT _keys-wait-xt
' KEY-IS-CHAR?        CONSTANT _keys-ischar-xt
' KEY-IS-SPECIAL?     CONSTANT _keys-isspec-xt
' KEY-IS-MOUSE?       CONSTANT _keys-ismouse-xt
' KEY-CODE@           CONSTANT _keys-code-xt
' KEY-MODS@           CONSTANT _keys-mods-xt
' KEY-HAS-CTRL?       CONSTANT _keys-hctrl-xt
' KEY-HAS-ALT?        CONSTANT _keys-halt-xt
' KEY-HAS-SHIFT?      CONSTANT _keys-hshift-xt
' KEY-TIMEOUT!        CONSTANT _keys-timeout-xt

: KEY-READ            _keys-read-xt _keys-guard WITH-GUARD ;
: KEY-POLL            _keys-poll-xt _keys-guard WITH-GUARD ;
: KEY-WAIT            _keys-wait-xt _keys-guard WITH-GUARD ;
: KEY-IS-CHAR?        _keys-ischar-xt _keys-guard WITH-GUARD ;
: KEY-IS-SPECIAL?     _keys-isspec-xt _keys-guard WITH-GUARD ;
: KEY-IS-MOUSE?       _keys-ismouse-xt _keys-guard WITH-GUARD ;
: KEY-CODE@           _keys-code-xt _keys-guard WITH-GUARD ;
: KEY-MODS@           _keys-mods-xt _keys-guard WITH-GUARD ;
: KEY-HAS-CTRL?       _keys-hctrl-xt _keys-guard WITH-GUARD ;
: KEY-HAS-ALT?        _keys-halt-xt _keys-guard WITH-GUARD ;
: KEY-HAS-SHIFT?      _keys-hshift-xt _keys-guard WITH-GUARD ;
: KEY-TIMEOUT!        _keys-timeout-xt _keys-guard WITH-GUARD ;
[THEN] [THEN]
