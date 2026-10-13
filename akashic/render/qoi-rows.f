\ qoi-rows.f — QOI pictures encoded a row at a time
\
\ Encodes pixels as a QOI file ("Quite OK Image") as a caller makes them,
\ a row or any run of pixels at a time, so a decoder of another format can
\ write QOI as it goes without holding the picture: the header, then
\ QOI-ENC-START, QOI-ENC-PIXELS for each row and QOI-ENC-END.  Pixels are
\ 32 bits each with red in the high byte and alpha in the low, as a
\ surface holds them.  QOI-ENC-PIXELS writes at most QOI-ENC-ROOM bytes
\ for N pixels, since a run may wait for the next call, and QOI-ENC-END at
\ most nine.  The caller owns the encoder's record, QOI-ENC-SIZE bytes,
\ cell-aligned, so pictures may take turns; one call runs at a time.
\
\ The format's constants and the decoder are qoi.f; encoding a whole
\ surface is qoi-encode.f.  Neither this module nor the decoder loads the
\ surface renderer.
\
\ Load with:   REQUIRE qoi-rows.f
\
\ Public API:
\   QOI-ENC-SIZE   ( -- bytes )                  An encoder's record
\   QOI-ENC-HEADER ( w h channels dst -- dst' )  A file's 14-byte header
\   QOI-ENC-START  ( enc -- )                    A new picture's state
\   QOI-ENC-PIXELS ( src n dst enc -- dst' )     N more pixels
\   QOI-ENC-ROOM   ( n -- bytes )                The most N pixels take
\   QOI-ENC-END    ( dst enc -- dst' )           The last run and end marker
\ =====================================================================

REQUIRE qoi.f

PROVIDED akashic-qoi-rows

\ =====================================================================
\  Encoder variables
\ =====================================================================

VARIABLE _QOI-BUF
VARIABLE _QOI-POS
VARIABLE _QOI-RUN
VARIABLE _QOI-PREV       \ previous pixel as packed 32-bit RGBA
VARIABLE _QOI-CUR        \ current pixel as packed 32-bit RGBA
VARIABLE _QOI-SRC        \ source pointer into surface buffer

\ An encoder's record: the previous pixel, the run, and the index of 64
\ cells, each a packed RGBA value.  A call works on its record's index
\ and keeps the previous pixel and run in the variables above meanwhile.
: _QOI-E.PREV  ( e -- a )       ;
: _QOI-E.RUN   ( e -- a )   8 + ;
: _QOI-E.TAB   ( e -- a )  16 + ;
16 512 + CONSTANT QOI-ENC-SIZE
VARIABLE _QOI-TAB        \ the index of the record being encoded


\ Channel scratch
VARIABLE _QOI-PR
VARIABLE _QOI-PG
VARIABLE _QOI-PB
VARIABLE _QOI-PA
VARIABLE _QOI-CR
VARIABLE _QOI-CG
VARIABLE _QOI-CB
VARIABLE _QOI-CA
VARIABLE _QOI-VR
VARIABLE _QOI-VG
VARIABLE _QOI-VB
VARIABLE _QOI-VGR
VARIABLE _QOI-VGB

\ =====================================================================
\  Helpers
\ =====================================================================

\ Write one byte to output buffer, advance pos
: _QOI-B!  ( byte -- )
    _QOI-BUF @ _QOI-POS @ + C!
    1 _QOI-POS +!
;

\ Write a big-endian 32-bit value
: _QOI-BE32!  ( u32 -- )
    DUP 24 RSHIFT 255 AND _QOI-B!
    DUP 16 RSHIFT 255 AND _QOI-B!
    DUP  8 RSHIFT 255 AND _QOI-B!
        255 AND _QOI-B!
;

\ Unpack RGBA pixel (R=bits31-24 G=23-16 B=15-8 A=7-0)
: _QOI-UNPACK  ( rgba -- r g b a )
    DUP 24 RSHIFT 255 AND SWAP
    DUP 16 RSHIFT 255 AND SWAP
    DUP  8 RSHIFT 255 AND SWAP
        255 AND
;

\ Pack r g b a → RGBA pixel
: _QOI-PACK  ( r g b a -- rgba )
    SWAP  8 LSHIFT OR
    SWAP 16 LSHIFT OR
    SWAP 24 LSHIFT OR
;

\ Compute hash index: (r*3 + g*5 + b*7 + a*11) % 64
: _QOI-HASH-IDX  ( r g b a -- idx )
    11 *
    SWAP 7 * +
    SWAP 5 * +
    SWAP 3 * +
    63 AND
;

\ Store pixel in hash table at its hash position
: _QOI-HASH-SET  ( rgba -- )
    DUP _QOI-UNPACK _QOI-HASH-IDX   ( rgba idx )
    8 * _QOI-TAB @ +                ( rgba addr )
    !
;

\ Get pixel from hash table at index
: _QOI-HASH-GET  ( idx -- rgba )
    8 * _QOI-TAB @ + @
;

\ Zero the hash table: 64 cells
: _QOI-HASH-CLEAR  ( -- )
    64 0 DO
        0  I 8 * _QOI-TAB @ +  !
    LOOP
;

\ Signed-byte conversion: mask to 8 bits, sign-extend if >= 128
: _QOI-SBYTE  ( n -- signed-byte )
    255 AND
    DUP 128 >= IF 256 - THEN
;

\ =====================================================================
\  Encoder: write end marker (7x 0x00 + 0x01)
\ =====================================================================

: _QOI-WRITE-END  ( -- )
    7 0 DO 0 _QOI-B! LOOP
    1 _QOI-B!
;

\ =====================================================================
\  Encoder: flush a pending run
\ =====================================================================

: _QOI-FLUSH-RUN  ( -- )
    _QOI-RUN @ 0 > IF
        QOI_OP_RUN  _QOI-RUN @ 1 - OR  _QOI-B!
        0 _QOI-RUN !
    THEN
;

\ =====================================================================
\  Encoder: encode one pixel
\ =====================================================================

: _QOI-ENCODE-PIXEL  ( -- )
    \ Read current pixel from surface
    _QOI-SRC @ L@  _QOI-CUR !
    4 _QOI-SRC +!

    \ Unpack current pixel channels
    _QOI-CUR @ _QOI-UNPACK
    _QOI-CA !  _QOI-CB !  _QOI-CG !  _QOI-CR !

    \ Check if same as previous
    _QOI-CUR @ _QOI-PREV @ = IF
        1 _QOI-RUN +!
        \ Flush run at 62 or end of image
        _QOI-RUN @ 62 = IF
            _QOI-FLUSH-RUN
        THEN
        EXIT
    THEN

    \ Different pixel — flush any pending run first
    _QOI-FLUSH-RUN

    \ Compute hash index for current pixel
    _QOI-CR @ _QOI-CG @ _QOI-CB @ _QOI-CA @ _QOI-HASH-IDX
    ( hash-idx )

    \ Check hash table
    DUP _QOI-HASH-GET _QOI-CUR @ = IF
        \ QOI_OP_INDEX
        QOI_OP_INDEX OR _QOI-B!
        _QOI-CUR @ _QOI-PREV !
        EXIT
    THEN
    DROP   \ drop hash-idx

    \ Store current in hash table
    _QOI-CUR @ _QOI-HASH-SET

    \ Unpack previous pixel channels
    _QOI-PREV @ _QOI-UNPACK
    _QOI-PA !  _QOI-PB !  _QOI-PG !  _QOI-PR !

    \ Check if alpha changed
    _QOI-CA @ _QOI-PA @ = IF
        \ Alpha same — try DIFF and LUMA
        _QOI-CR @ _QOI-PR @ - _QOI-SBYTE _QOI-VR !
        _QOI-CG @ _QOI-PG @ - _QOI-SBYTE _QOI-VG !
        _QOI-CB @ _QOI-PB @ - _QOI-SBYTE _QOI-VB !

        \ Try QOI_OP_DIFF: all diffs in -2..1
        _QOI-VR @ -2 >= _QOI-VR @ 2 < AND
        _QOI-VG @ -2 >= _QOI-VG @ 2 < AND AND
        _QOI-VB @ -2 >= _QOI-VB @ 2 < AND AND
        IF
            QOI_OP_DIFF
            _QOI-VR @ 2 + 4 LSHIFT OR
            _QOI-VG @ 2 + 2 LSHIFT OR
            _QOI-VB @ 2 + OR
            _QOI-B!
            _QOI-CUR @ _QOI-PREV !
            EXIT
        THEN

        \ Try QOI_OP_LUMA
        _QOI-VR @ _QOI-VG @ - _QOI-VGR !
        _QOI-VB @ _QOI-VG @ - _QOI-VGB !

        _QOI-VG @  -32 >= _QOI-VG @  32 < AND
        _QOI-VGR @  -8 >= _QOI-VGR @  8 < AND AND
        _QOI-VGB @  -8 >= _QOI-VGB @  8 < AND AND
        IF
            QOI_OP_LUMA  _QOI-VG @ 32 + OR  _QOI-B!
            _QOI-VGR @ 8 + 4 LSHIFT  _QOI-VGB @ 8 + OR  _QOI-B!
            _QOI-CUR @ _QOI-PREV !
            EXIT
        THEN

        \ Fallback: QOI_OP_RGB
        QOI_OP_RGB _QOI-B!
        _QOI-CR @ _QOI-B!
        _QOI-CG @ _QOI-B!
        _QOI-CB @ _QOI-B!
        _QOI-CUR @ _QOI-PREV !
        EXIT
    THEN

    \ Alpha changed — QOI_OP_RGBA
    QOI_OP_RGBA _QOI-B!
    _QOI-CR @ _QOI-B!
    _QOI-CG @ _QOI-B!
    _QOI-CB @ _QOI-B!
    _QOI-CA @ _QOI-B!
    _QOI-CUR @ _QOI-PREV !
;

\ =====================================================================
\  A picture a row at a time
\ =====================================================================

\ QOI-ENC-HEADER ( w h channels dst -- dst' )
\   The header of a W by H picture of CHANNELS (3 or 4), sRGB.
: QOI-ENC-HEADER  ( w h channels dst -- dst' )
    _QOI-BUF !  0 _QOI-POS !
    ROT ROT  0x716F6966 _QOI-BE32!  SWAP _QOI-BE32! _QOI-BE32!
    _QOI-B!  0 _QOI-B!
    _QOI-BUF @ _QOI-POS @ + ;

\ A record's state into the variables, and back.
: _QOI-LOAD   ( enc -- )
    DUP _QOI-E.PREV @ _QOI-PREV !  DUP _QOI-E.RUN @ _QOI-RUN !  _QOI-E.TAB _QOI-TAB ! ;
: _QOI-STORE  ( enc -- )  _QOI-PREV @ OVER _QOI-E.PREV !  _QOI-RUN @ SWAP _QOI-E.RUN ! ;

\ QOI-ENC-START ( enc -- )
\   A new picture: the pixel before the first opaque black, no run, the
\   index empty.
: QOI-ENC-START  ( enc -- )
    DUP _QOI-E.TAB _QOI-TAB !  _QOI-HASH-CLEAR
    0 OVER _QOI-E.RUN !  0x000000FF SWAP _QOI-E.PREV ! ;

\ QOI-ENC-ROOM ( n -- bytes )   The most QOI-ENC-PIXELS writes for N.
: QOI-ENC-ROOM  ( n -- bytes )  5 * 1+ ;

\ QOI-ENC-PIXELS ( src n dst enc -- dst' )   N pixels at SRC onto DST.
: QOI-ENC-PIXELS  ( src n dst enc -- dst' )
    DUP >R _QOI-LOAD
    _QOI-BUF !  0 _QOI-POS !  SWAP _QOI-SRC !
    0 ?DO _QOI-ENCODE-PIXEL LOOP
    R> _QOI-STORE  _QOI-BUF @ _QOI-POS @ + ;

\ QOI-ENC-END ( dst enc -- dst' )   The run that waits, and the end marker.
: QOI-ENC-END  ( dst enc -- dst' )
    DUP >R _QOI-LOAD  _QOI-BUF !  0 _QOI-POS !
    _QOI-FLUSH-RUN  _QOI-WRITE-END
    R> _QOI-STORE  _QOI-BUF @ _QOI-POS @ + ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _qoi-rows-guard

' QOI-ENC-HEADER  CONSTANT _qoi-enc-header-xt
' QOI-ENC-START   CONSTANT _qoi-enc-start-xt
' QOI-ENC-PIXELS  CONSTANT _qoi-enc-pixels-xt
' QOI-ENC-END     CONSTANT _qoi-enc-end-xt

: QOI-ENC-HEADER  _qoi-enc-header-xt _qoi-rows-guard WITH-GUARD ;
: QOI-ENC-START   _qoi-enc-start-xt _qoi-rows-guard WITH-GUARD ;
: QOI-ENC-PIXELS  _qoi-enc-pixels-xt _qoi-rows-guard WITH-GUARD ;
: QOI-ENC-END     _qoi-enc-end-xt _qoi-rows-guard WITH-GUARD ;
[THEN] [THEN]
