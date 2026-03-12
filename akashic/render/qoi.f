\ qoi.f — QOI image encoder/decoder
\
\ Encodes a surface (RGBA8888) as a QOI file ("Quite OK Image").
\ Also decodes QOI data back into a surface.
\
\ Load with:   REQUIRE qoi.f
\ Depends on:  surface.f
\
\ Public API:
\   QOI-FILE-SIZE  ( w h -- max-bytes )          Worst-case output size
\   QOI-ENCODE     ( surf buf max -- len | 0 )   Encode surface → QOI
\   QOI-DECODE     ( qoi-a qoi-u -- surf )       Decode QOI → new surface
\
\ Returns 0 from QOI-ENCODE if buffer is too small.
\ Returns 0 from QOI-DECODE on invalid data.
\ =====================================================================

REQUIRE surface.f

PROVIDED akashic-qoi

\ =====================================================================
\  Constants
\ =====================================================================

14 CONSTANT QOI-HDR-SIZE
 8 CONSTANT QOI-END-SIZE

\ Op tags
0x00 CONSTANT QOI_OP_INDEX
0x40 CONSTANT QOI_OP_DIFF
0x80 CONSTANT QOI_OP_LUMA
0xC0 CONSTANT QOI_OP_RUN
0xFE CONSTANT QOI_OP_RGB
0xFF CONSTANT QOI_OP_RGBA
0xC0 CONSTANT QOI_MASK_2

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
\ We use ALLOCATE / FREE at runtime.
VARIABLE _QOI-HASH       \ pointer to hash table (64 cells = 512 bytes)

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
    8 * _QOI-HASH @ +               ( rgba addr )
    !
;

\ Get pixel from hash table at index
: _QOI-HASH-GET  ( idx -- rgba )
    8 * _QOI-HASH @ + @
;

\ Zero the hash table: 64 cells
: _QOI-HASH-CLEAR  ( -- )
    64 0 DO
        0  I 8 * _QOI-HASH @ +  !
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

    \ Allocate hash table
    512 ALLOCATE DROP _QOI-HASH !
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

    \ Free hash table
    _QOI-HASH @ FREE DROP

    \ Return actual bytes written (not worst-case)
    R> DROP                \ drop the max we saved
    _QOI-POS @
;

\ =====================================================================
\  Decoder variables
\ =====================================================================

VARIABLE _QOI-IN          \ input buffer address
VARIABLE _QOI-IPOS        \ input read position
VARIABLE _QOI-ILEN        \ input length
VARIABLE _QOI-DST         \ destination surface
VARIABLE _QOI-DPTR        \ destination pixel pointer
VARIABLE _QOI-DRUN        \ decoder run counter
VARIABLE _QOI-DPX         \ decoder current pixel (packed RGBA)
VARIABLE _QOI-B1          \ first byte of chunk

\ Read one byte from input, advance position
: _QOI-RB  ( -- byte )
    _QOI-IN @ _QOI-IPOS @ + C@
    1 _QOI-IPOS +!
;

\ Read big-endian 32-bit from input
: _QOI-RBE32  ( -- u32 )
    _QOI-RB 24 LSHIFT
    _QOI-RB 16 LSHIFT OR
    _QOI-RB  8 LSHIFT OR
    _QOI-RB OR
;

\ =====================================================================
\  QOI-DECODE  ( qoi-a qoi-u -- surf | 0 )
\ =====================================================================

: QOI-DECODE  ( qoi-a qoi-u -- surf | 0 )
    _QOI-ILEN !
    _QOI-IN !
    0 _QOI-IPOS !

    \ Check minimum size
    _QOI-ILEN @ QOI-HDR-SIZE QOI-END-SIZE + < IF 0 EXIT THEN

    \ Read header
    _QOI-RBE32                         \ magic
    0x716F6966 <> IF 0 EXIT THEN       \ must be "qoif"
    _QOI-RBE32 _QOI-W !               \ width
    _QOI-RBE32 _QOI-H !               \ height
    _QOI-RB DROP                       \ channels (ignore, always treat as 4)
    _QOI-RB DROP                       \ colorspace (ignore)

    \ Validate
    _QOI-W @ 0 = IF 0 EXIT THEN
    _QOI-H @ 0 = IF 0 EXIT THEN

    \ Create output surface
    _QOI-W @ _QOI-H @ SURF-CREATE _QOI-DST !
    _QOI-DST @ SURF-BUF _QOI-DPTR !

    \ Allocate + clear hash table
    512 ALLOCATE DROP _QOI-HASH !
    _QOI-HASH-CLEAR

    \ Init decoder state
    0 _QOI-DRUN !
    0x000000FF _QOI-DPX !      \ prev = (0,0,0,255)

    _QOI-W @ _QOI-H @ * _QOI-TOTAL !
    _QOI-ILEN @ QOI-END-SIZE -          \ chunks end position

    _QOI-TOTAL @ 0 DO
        _QOI-DRUN @ 0 > IF
            \ Continuing a run
            -1 _QOI-DRUN +!
        ELSE
            _QOI-IPOS @ OVER < IF       ( chunks-end )
                _QOI-RB _QOI-B1 !

                _QOI-B1 @ QOI_OP_RGB = IF
                    \ QOI_OP_RGB
                    _QOI-DPX @ _QOI-UNPACK _QOI-CA !
                    DROP DROP DROP       \ drop old r g b
                    _QOI-RB _QOI-RB _QOI-RB
                    ( r g b )
                    _QOI-CA @
                    _QOI-PACK _QOI-DPX !
                ELSE _QOI-B1 @ QOI_OP_RGBA = IF
                    \ QOI_OP_RGBA
                    _QOI-RB _QOI-RB _QOI-RB _QOI-RB
                    _QOI-PACK _QOI-DPX !
                ELSE _QOI-B1 @ QOI_MASK_2 AND QOI_OP_INDEX = IF
                    \ QOI_OP_INDEX
                    _QOI-B1 @ 63 AND _QOI-HASH-GET _QOI-DPX !
                ELSE _QOI-B1 @ QOI_MASK_2 AND QOI_OP_DIFF = IF
                    \ QOI_OP_DIFF
                    _QOI-DPX @ _QOI-UNPACK
                    _QOI-CA !  _QOI-CB !  _QOI-CG !  _QOI-CR !
                    _QOI-CR @  _QOI-B1 @ 4 RSHIFT 3 AND 2 - +  255 AND  _QOI-CR !
                    _QOI-CG @  _QOI-B1 @ 2 RSHIFT 3 AND 2 - +  255 AND  _QOI-CG !
                    _QOI-CB @  _QOI-B1 @          3 AND 2 - +  255 AND  _QOI-CB !
                    _QOI-CR @ _QOI-CG @ _QOI-CB @ _QOI-CA @
                    _QOI-PACK _QOI-DPX !
                ELSE _QOI-B1 @ QOI_MASK_2 AND QOI_OP_LUMA = IF
                    \ QOI_OP_LUMA
                    _QOI-DPX @ _QOI-UNPACK
                    _QOI-CA !  _QOI-CB !  _QOI-CG !  _QOI-CR !
                    _QOI-B1 @ 63 AND 32 -         ( vg )
                    _QOI-RB                        ( vg b2 )
                    OVER OVER                      ( vg b2 vg b2 )
                    4 RSHIFT 15 AND 8 -            ( vg b2 vg vgr )
                    SWAP +                         ( vg b2 dr )
                    _QOI-CR @ + 255 AND _QOI-CR !  ( vg b2 )
                    15 AND 8 -                     ( vg vgb )
                    OVER +                         ( vg db )
                    _QOI-CB @ + 255 AND _QOI-CB !  ( vg )
                    _QOI-CG @ + 255 AND _QOI-CG !
                    _QOI-CR @ _QOI-CG @ _QOI-CB @ _QOI-CA @
                    _QOI-PACK _QOI-DPX !
                ELSE _QOI-B1 @ QOI_MASK_2 AND QOI_OP_RUN = IF
                    \ QOI_OP_RUN
                    _QOI-B1 @ 63 AND _QOI-DRUN !
                    \ run includes this pixel, so decrement by 1
                    \ (the bias is already -1 in the stored value,
                    \  but this iteration consumes one pixel)
                THEN THEN THEN THEN THEN THEN

                \ Update hash table
                _QOI-DPX @ _QOI-HASH-SET
            THEN
        THEN

        \ Write pixel to surface
        _QOI-DPX @  _QOI-DPTR @  L!
        4 _QOI-DPTR +!
    LOOP
    DROP   \ drop chunks-end

    \ Free hash table
    _QOI-HASH @ FREE DROP

    \ Return surface
    _QOI-DST @
;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _qoi-guard

' QOI-FILE-SIZE   CONSTANT _qoi-file-size-xt
' QOI-ENCODE      CONSTANT _qoi-encode-xt
' QOI-DECODE      CONSTANT _qoi-decode-xt

: QOI-FILE-SIZE   _qoi-file-size-xt _qoi-guard WITH-GUARD ;
: QOI-ENCODE      _qoi-encode-xt _qoi-guard WITH-GUARD ;
: QOI-DECODE      _qoi-decode-xt _qoi-guard WITH-GUARD ;
[THEN] [THEN]
