\ qoi-encode.f — encode a surface as a QOI picture
\
\ Encodes a surface (RGBA8888) as a QOI file ("Quite OK Image").  The
\ format's constants and the decoder are qoi.f.
\
\ Load with:   REQUIRE qoi-encode.f
\
\ Public API:
\   QOI-FILE-SIZE  ( w h -- max-bytes )          Worst-case output size
\   QOI-ENCODE     ( surf buf max -- len | 0 )   Encode surface → QOI
\
\ Returns 0 from QOI-ENCODE if the buffer is too small.
\ =====================================================================

REQUIRE qoi.f
REQUIRE surface.f

PROVIDED akashic-qoi-encode

\ =====================================================================
\  QOI-FILE-SIZE  ( w h -- max-bytes )
\ =====================================================================
\  Worst case: every pixel needs 5 bytes (RGBA tag + 4 channel bytes),
\  plus header and end marker.

: QOI-FILE-SIZE  ( w h -- max-bytes )
    * 5 *                     \ w*h*5  worst case pixel data
    QOI-HDR-SIZE +
    QOI-END-SIZE +
;

\ =====================================================================
\  Encoder variables
\ =====================================================================

VARIABLE _QOI-SURF
VARIABLE _QOI-BUF
VARIABLE _QOI-POS
VARIABLE _QOI-W
VARIABLE _QOI-H
VARIABLE _QOI-RUN
VARIABLE _QOI-PREV       \ previous pixel as packed 32-bit RGBA
VARIABLE _QOI-CUR        \ current pixel as packed 32-bit RGBA
VARIABLE _QOI-SRC        \ source pointer into surface buffer
VARIABLE _QOI-TOTAL      \ total pixels
VARIABLE _QOI-PIDX       \ pixel index counter

\ Hash table: 64 entries, each a 64-bit cell holding a packed RGBA value.
\ The encoder's state is module state, so its table is too.
CREATE _QOI-HASH-TABLE 512 ALLOT

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
    8 * _QOI-HASH-TABLE +           ( rgba addr )
    !
;

\ Get pixel from hash table at index
: _QOI-HASH-GET  ( idx -- rgba )
    8 * _QOI-HASH-TABLE + @
;

\ Zero the hash table: 64 cells
: _QOI-HASH-CLEAR  ( -- )
    64 0 DO
        0  I 8 * _QOI-HASH-TABLE +  !
    LOOP
;

\ Signed-byte conversion: mask to 8 bits, sign-extend if >= 128
: _QOI-SBYTE  ( n -- signed-byte )
    255 AND
    DUP 128 >= IF 256 - THEN
;

\ =====================================================================
\  Encoder: write header
\ =====================================================================

: _QOI-WRITE-HDR  ( -- )
    \ "qoif" magic = 0x716F6966
    0x716F6966 _QOI-BE32!
    _QOI-W @ _QOI-BE32!
    _QOI-H @ _QOI-BE32!
    4 _QOI-B!                 \ channels = 4 (RGBA)
    0 _QOI-B!                 \ colorspace = 0 (sRGB)
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
\  QOI-ENCODE  ( surf buf max -- len | 0 )
\ =====================================================================

: QOI-ENCODE  ( surf buf max -- len | 0 )
    >R >R                             \ R: max buf
    DUP SURF-W OVER SURF-H
    _QOI-H !  _QOI-W !
    _QOI-SURF !

    \ Check buffer size
    _QOI-W @ _QOI-H @ QOI-FILE-SIZE
    R> R>                              \ needed buf max
    ROT                                \ buf max needed
    2DUP < IF
        DROP DROP DROP
        0 EXIT
    THEN
    NIP                                \ buf needed
    >R
    _QOI-BUF !
    0 _QOI-POS !

    _QOI-HASH-CLEAR

    \ Init state
    0 _QOI-RUN !
    \ prev pixel = r:0 g:0 b:0 a:255 = 0x000000FF
    0x000000FF _QOI-PREV !

    \ Write header
    _QOI-WRITE-HDR

    \ Set up source pointer
    _QOI-SURF @ SURF-BUF  _QOI-SRC !
    _QOI-W @ _QOI-H @ *  _QOI-TOTAL !

    \ Encode all pixels
    _QOI-TOTAL @ 0 DO
        _QOI-ENCODE-PIXEL
    LOOP

    \ Flush any remaining run
    _QOI-FLUSH-RUN

    \ Write end marker
    _QOI-WRITE-END

    \ Return actual bytes written (not worst-case)
    R> DROP                \ drop the max we saved
    _QOI-POS @
;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _qoi-encode-guard

' QOI-FILE-SIZE   CONSTANT _qoi-file-size-xt
' QOI-ENCODE      CONSTANT _qoi-encode-xt

: QOI-FILE-SIZE   _qoi-file-size-xt _qoi-encode-guard WITH-GUARD ;
: QOI-ENCODE      _qoi-encode-xt _qoi-encode-guard WITH-GUARD ;
[THEN] [THEN]
