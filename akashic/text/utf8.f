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
\   UTF8-ENCODE   ( cp buf -- buf' )
\   UTF8-LEN      ( addr len -- n )
\   UTF8-VALID?   ( addr len -- flag )
\   UTF8-NTH      ( addr len n -- cp )

PROVIDED akashic-utf8

0xFFFD CONSTANT UTF8-REPLACEMENT  \ U+FFFD REPLACEMENT CHARACTER

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

VARIABLE _UD-CP                        \ accumulating codepoint
VARIABLE _UD-NEED                      \ expected sequence length
VARIABLE _UD-A                         \ buffer start
VARIABLE _UD-L                         \ buffer length

: UTF8-DECODE  ( addr len -- cp addr' len' )
    DUP 0= IF UTF8-REPLACEMENT -ROT EXIT THEN
    2DUP _UD-L ! _UD-A !              ( addr len )
    DROP                               ( )
    _UD-A @ C@                         ( b0 )
    DUP _UTF8-SEQLEN                   ( b0 seqlen )
    DUP 0= IF                         \ bad leading byte → skip 1
        2DROP
        UTF8-REPLACEMENT
        _UD-A @ 1+  _UD-L @ 1-
        EXIT
    THEN
    _UD-NEED !                         ( b0 )
    \ Check buffer has enough bytes
    _UD-L @ _UD-NEED @ < IF           \ truncated → skip 1
        DROP
        UTF8-REPLACEMENT
        _UD-A @ 1+  _UD-L @ 1-
        EXIT
    THEN
    \ Extract leading-byte payload
    _UD-NEED @ CASE
        1 OF                   _UD-CP ! ENDOF
        2 OF 0x1F AND          _UD-CP ! ENDOF
        3 OF 0x0F AND          _UD-CP ! ENDOF
        4 OF 0x07 AND          _UD-CP ! ENDOF
    ENDCASE
    \ Read continuation bytes
    _UD-NEED @ 1 > IF
        _UD-NEED @ 1 DO
            _UD-A @ I + C@            ( cont )
            DUP _UTF8-CONT? 0= IF     \ bad continuation → skip 1
                DROP
                UTF8-REPLACEMENT
                _UD-A @ 1+  _UD-L @ 1-
                UNLOOP EXIT
            THEN
            0x3F AND
            _UD-CP @ 6 LSHIFT OR _UD-CP !
        LOOP
    THEN
    \ Validate: overlong, surrogate, out of range
    _UD-CP @
    DUP 0x10FFFF > IF
        DROP UTF8-REPLACEMENT _UD-CP !
    ELSE
        DUP 0xD800 >= OVER 0xDFFF <= AND IF
            DROP UTF8-REPLACEMENT _UD-CP !
        ELSE
            _UD-NEED @ CASE
                2 OF DUP 0x80   < IF DROP UTF8-REPLACEMENT _UD-CP ! THEN ENDOF
                3 OF DUP 0x800  < IF DROP UTF8-REPLACEMENT _UD-CP ! THEN ENDOF
                4 OF DUP 0x10000 < IF DROP UTF8-REPLACEMENT _UD-CP ! THEN ENDOF
            ENDCASE
            DROP
        THEN
    THEN
    \ Return: cp addr' len'
    _UD-CP @
    _UD-A @ _UD-NEED @ +
    _UD-L @ _UD-NEED @ -
;

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
\  Returns -1 for valid, 0 if any replacement chars were emitted.

: UTF8-VALID?  ( addr len -- flag )
    BEGIN DUP 0 > WHILE
        UTF8-DECODE                    ( cp addr' len' )
        ROT UTF8-REPLACEMENT = IF
            2DROP 0 EXIT
        THEN
    REPEAT
    2DROP -1 ;

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
