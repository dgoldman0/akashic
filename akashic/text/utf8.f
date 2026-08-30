\ utf8.f — UTF-8 codec for KDOS / Megapad-64
\
\ Decode and encode Unicode codepoints in the standard (addr len)
\ byte-buffer model used throughout Akashic.
\
\ Prefix: UTF8-   (public API)
\         _UTF8-  (internal helpers)
\
\ Load with:   REQUIRE utf8.f
\
\ === Public API ===
\   UTF8-DECODE   ( addr len -- cp addr' len' )
\   UTF8-DECODE-WITH ( addr len state -- cp addr' len' )
\   UTF8-ENCODE   ( cp buf -- buf' )
\   UTF8-LEN      ( addr len -- n )
\   UTF8-VALID?   ( addr len -- flag )
\   UTF8-NTH      ( addr len n -- cp )

PROVIDED akashic-utf8

0xFFFD CONSTANT UTF8-REPLACEMENT  \ U+FFFD REPLACEMENT CHARACTER

\ A terminal cell is a presentation boundary, not an arbitrary Unicode byte
\ channel.  This pure policy preserves ordinary text while making controls and
\ invisible direction overrides visibly inert.  Source buffers remain owned
\ and unchanged by callers.
: UTF8-DISPLAY-UNSAFE?  ( cp -- flag )
    DUP 0 32 WITHIN IF DROP -1 EXIT THEN       \ C0 controls
    DUP 127 160 WITHIN IF DROP -1 EXIT THEN    \ DEL and C1 controls
    DUP 0x061C = IF DROP -1 EXIT THEN          \ Arabic letter mark
    DUP 0x200B = IF DROP -1 EXIT THEN          \ zero-width space
    DUP 0x200E 0x2010 WITHIN IF DROP -1 EXIT THEN
    DUP 0x2028 0x202F WITHIN IF DROP -1 EXIT THEN
    DUP 0x2060 0x2070 WITHIN IF DROP -1 EXIT THEN
    DUP 0xFEFF = IF DROP -1 EXIT THEN
    DUP 0xFFF9 0xFFFC WITHIN IF DROP -1 EXIT THEN
    DUP 0xE0000 0xE0080 WITHIN IF DROP -1 EXIT THEN
    DROP 0 ;

: UTF8-DISPLAY-CP  ( cp -- safe-cp )
    DUP UTF8-DISPLAY-UNSAFE? IF DROP UTF8-REPLACEMENT THEN ;

\ =====================================================================
\  Internal: classify a leading byte
\ =====================================================================

\ _UTF8-SEQLEN ( byte -- n )
\   Sequence length from leading byte.  0 for invalid/continuation.
: _UTF8-SEQLEN  ( byte -- n )
    DUP 0x80 < IF DROP 1 EXIT THEN
    DUP 0xC0 < IF DROP 0 EXIT THEN
    DUP 0xE0 < IF DROP 2 EXIT THEN
    DUP 0xF0 < IF DROP 3 EXIT THEN
    DUP 0xF8 < IF DROP 4 EXIT THEN
    DROP 0 ;

\ _UTF8-CONT? ( byte -- flag )
\   True if byte is a continuation byte (10xxxxxx).
: _UTF8-CONT?  ( byte -- flag )
    0xC0 AND 0x80 = ;

\ =====================================================================
\  UTF8-DECODE — consume one UTF-8 character from front of buffer
\ =====================================================================
\  On invalid byte or truncated sequence: returns U+FFFD, advances 1.
\
\  UTF8-DECODE-WITH keeps every mutable decode temporary in four cells of
\  caller-owned state.  Distinct state makes the operation reentrant and
\  suitable for a bounded callback which may not acquire or wait on a guard.
\  The ordinary UTF8-DECODE API serializes one private state below.

 0 CONSTANT _UTF8-DS-A
 8 CONSTANT _UTF8-DS-L
16 CONSTANT _UTF8-DS-CP
24 CONSTANT _UTF8-DS-NEED
32 CONSTANT UTF8-DECODE-STATE-SIZE

: _UTF8-DECODE-WITH-FAIL  ( state -- cp addr' len' )
    DUP _UTF8-DS-A + @ 1+
    SWAP _UTF8-DS-L + @ 1-
    UTF8-REPLACEMENT -ROT ;

: _UTF8-DECODE-WITH-CONT  ( offset state -- flag )
    >R
    R@ _UTF8-DS-A + @ + C@ DUP _UTF8-CONT? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    0x3F AND
    R@ _UTF8-DS-CP + @ 6 LSHIFT OR
    R> _UTF8-DS-CP + !
    -1 ;

: _UTF8-DECODE-WITH-VALID?  ( cp need -- flag )
    OVER 0x10FFFF > IF 2DROP 0 EXIT THEN
    OVER 0xD800 >= 2 PICK 0xDFFF <= AND IF 2DROP 0 EXIT THEN
    DUP 1 = IF 2DROP -1 EXIT THEN
    DUP 2 = IF DROP 0x80 >= EXIT THEN
    DUP 3 = IF DROP 0x800 >= EXIT THEN
    DUP 4 = IF DROP 0x10000 >= EXIT THEN
    2DROP 0 ;

: UTF8-DECODE-WITH  ( addr len state -- cp addr' len' )
    >R
    DUP 0= IF UTF8-REPLACEMENT -ROT R> DROP EXIT THEN
    DUP  R@ _UTF8-DS-L + !
    OVER R@ _UTF8-DS-A + !
    2DROP
    R@ _UTF8-DS-A + @ C@               ( b0 )
    DUP _UTF8-SEQLEN                   ( b0 seqlen )
    DUP 0= IF                         \ bad leading byte → skip 1
        2DROP
        R> _UTF8-DECODE-WITH-FAIL EXIT
    THEN
    DUP R@ _UTF8-DS-NEED + !           ( b0 seqlen )
    \ Check buffer has enough bytes
    R@ _UTF8-DS-L + @ > IF             \ truncated → skip 1
        DROP
        R> _UTF8-DECODE-WITH-FAIL EXIT
    THEN
    \ Extract leading-byte payload
    R@ _UTF8-DS-NEED + @ CASE
        1 OF                   R@ _UTF8-DS-CP + ! ENDOF
        2 OF 0x1F AND          R@ _UTF8-DS-CP + ! ENDOF
        3 OF 0x0F AND          R@ _UTF8-DS-CP + ! ENDOF
        4 OF 0x07 AND          R@ _UTF8-DS-CP + ! ENDOF
    ENDCASE
    \ Read continuation bytes without using DO-loop return-stack state.
    R@ _UTF8-DS-NEED + @ 1 > IF
        1 R@ _UTF8-DECODE-WITH-CONT 0= IF
            R> _UTF8-DECODE-WITH-FAIL EXIT
        THEN
    THEN
    R@ _UTF8-DS-NEED + @ 2 > IF
        2 R@ _UTF8-DECODE-WITH-CONT 0= IF
            R> _UTF8-DECODE-WITH-FAIL EXIT
        THEN
    THEN
    R@ _UTF8-DS-NEED + @ 3 > IF
        3 R@ _UTF8-DECODE-WITH-CONT 0= IF
            R> _UTF8-DECODE-WITH-FAIL EXIT
        THEN
    THEN
    \ Validate: overlong, surrogate, out of range
    R@ _UTF8-DS-CP + @ R@ _UTF8-DS-NEED + @
    _UTF8-DECODE-WITH-VALID? 0= IF
        UTF8-REPLACEMENT R@ _UTF8-DS-CP + !
    THEN
    \ Return: cp addr' len'
    R@ _UTF8-DS-CP + @
    R@ _UTF8-DS-A + @ R@ _UTF8-DS-NEED + @ +
    R@ _UTF8-DS-L + @ R@ _UTF8-DS-NEED + @ -
    R> DROP ;

CREATE _UTF8-DECODE-STATE UTF8-DECODE-STATE-SIZE ALLOT

: UTF8-DECODE  ( addr len -- cp addr' len' )
    _UTF8-DECODE-STATE UTF8-DECODE-WITH ;

\ =====================================================================
\  UTF8-ENCODE — write one codepoint as UTF-8 into buffer
\ =====================================================================
\  buf must have at least 4 bytes available.
\  Returns address past the last byte written.

: UTF8-ENCODE  ( cp buf -- buf' )
    OVER 0x80 < IF                     \ 1-byte ASCII
        OVER OVER C!  1+  NIP EXIT
    THEN
    OVER 0x800 < IF                    \ 2-byte
        OVER 6 RSHIFT 0xC0 OR OVER C!  1+
        OVER 0x3F AND 0x80 OR OVER C!  1+
        NIP EXIT
    THEN
    OVER 0x10000 < IF                  \ 3-byte
        OVER 12 RSHIFT 0xE0 OR OVER C!  1+
        OVER 6 RSHIFT 0x3F AND 0x80 OR OVER C!  1+
        OVER 0x3F AND 0x80 OR OVER C!  1+
        NIP EXIT
    THEN
    \ 4-byte
    OVER 18 RSHIFT 0xF0 OR OVER C!  1+
    OVER 12 RSHIFT 0x3F AND 0x80 OR OVER C!  1+
    OVER 6 RSHIFT 0x3F AND 0x80 OR OVER C!  1+
    OVER 0x3F AND 0x80 OR OVER C!  1+
    NIP ;

\ =====================================================================
\  UTF8-LEN — count codepoints in a UTF-8 buffer
\ =====================================================================

: UTF8-LEN  ( addr len -- n )
    0 >R                               ( addr len  R: count )
    BEGIN DUP 0 > WHILE
        UTF8-DECODE                    ( cp addr' len' )
        ROT DROP                       ( addr' len' )
        R> 1+ >R
    REPEAT
    2DROP R> ;

\ =====================================================================
\  UTF8-VALID? — check if buffer is valid UTF-8
\ =====================================================================
\  Validation has a direct ASCII path instead of calling UTF8-DECODE for
\  every byte.  Multibyte lead constraints reject overlong encodings,
\  surrogate codepoints, and values beyond U+10FFFF.

VARIABLE _UV-A
VARIABLE _UV-U
VARIABLE _UV-B0
VARIABLE _UV-B1

: _UV-CONT?  ( offset -- flag )
    DUP _UV-U @ >= IF DROP 0 EXIT THEN
    _UV-A @ + C@ 0xC0 AND 0x80 = ;

: _UV-ADV  ( count -- )
    DUP _UV-A +! NEGATE _UV-U +! ;

: UTF8-VALID?  ( addr len -- flag )
    _UV-U ! _UV-A !
    BEGIN _UV-U @ 0> WHILE
        _UV-A @ C@ DUP _UV-B0 !
        0x80 < IF
            1 _UV-ADV
        ELSE
            _UV-B0 @ 0xC2 >= _UV-B0 @ 0xDF <= AND IF
                1 _UV-CONT? 0= IF 0 EXIT THEN
                2 _UV-ADV
            ELSE
                _UV-B0 @ 0xE0 >= _UV-B0 @ 0xEF <= AND IF
                    _UV-U @ 3 < IF 0 EXIT THEN
                    _UV-A @ 1+ C@ _UV-B1 !
                    _UV-B0 @ 0xE0 = IF
                        _UV-B1 @ 0xA0 >= _UV-B1 @ 0xBF <= AND
                    ELSE
                        _UV-B0 @ 0xED = IF
                            _UV-B1 @ 0x80 >= _UV-B1 @ 0x9F <= AND
                        ELSE
                            _UV-B1 @ 0xC0 AND 0x80 =
                        THEN
                    THEN
                    2 _UV-CONT? AND 0= IF 0 EXIT THEN
                    3 _UV-ADV
                ELSE
                    _UV-B0 @ 0xF0 >= _UV-B0 @ 0xF4 <= AND IF
                        _UV-U @ 4 < IF 0 EXIT THEN
                        _UV-A @ 1+ C@ _UV-B1 !
                        _UV-B0 @ 0xF0 = IF
                            _UV-B1 @ 0x90 >= _UV-B1 @ 0xBF <= AND
                        ELSE
                            _UV-B0 @ 0xF4 = IF
                                _UV-B1 @ 0x80 >= _UV-B1 @ 0x8F <= AND
                            ELSE
                                _UV-B1 @ 0xC0 AND 0x80 =
                            THEN
                        THEN
                        2 _UV-CONT? AND 3 _UV-CONT? AND
                        0= IF 0 EXIT THEN
                        4 _UV-ADV
                    ELSE
                        0 EXIT
                    THEN
                THEN
            THEN
        THEN
    REPEAT
    -1 ;

\ =====================================================================
\  UTF8-NTH — return the nth codepoint (0-based)
\ =====================================================================
\  Returns U+FFFD if n is past the end of the buffer.

VARIABLE _UN-IDX

: UTF8-NTH  ( addr len n -- cp )
    >R                                 ( addr len  R: target )
    0 _UN-IDX !
    BEGIN DUP 0 > WHILE
        UTF8-DECODE                    ( cp addr' len' )
        _UN-IDX @ R@ = IF             \ found it
            ROT NIP NIP                ( cp )
            R> DROP EXIT
        THEN
        ROT DROP                       ( addr' len' )
        _UN-IDX @ 1+ _UN-IDX !
    REPEAT
    2DROP R> DROP
    UTF8-REPLACEMENT ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _utf8-guard

' UTF8-DECODE     CONSTANT _utf8-decode-xt
' UTF8-ENCODE     CONSTANT _utf8-encode-xt
' UTF8-LEN        CONSTANT _utf8-len-xt
' UTF8-VALID?     CONSTANT _utf8-valid-q-xt
' UTF8-NTH        CONSTANT _utf8-nth-xt

: UTF8-DECODE     _utf8-decode-xt _utf8-guard WITH-GUARD ;
: UTF8-ENCODE     _utf8-encode-xt _utf8-guard WITH-GUARD ;
: UTF8-LEN        _utf8-len-xt _utf8-guard WITH-GUARD ;
: UTF8-VALID?     _utf8-valid-q-xt _utf8-guard WITH-GUARD ;
: UTF8-NTH        _utf8-nth-xt _utf8-guard WITH-GUARD ;
[THEN] [THEN]
