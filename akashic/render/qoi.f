\ qoi.f — QOI image encoder and resumable decoder
\
\ Encodes a surface (RGBA8888) as a QOI file ("Quite OK Image"), and
\ decodes QOI files a chunk at a time.
\
\ The decoder keeps its whole state in a record its caller owns and never
\ allocates.  It reads whatever chunks of the file the caller has, picks
\ up an operation split between two chunks, and writes one row at a time
\ into a caller row buffer, in R, G, B, A byte order (the order the rich
\ terminal's RGBA8 resources use).  A caller can therefore scale, hash or
\ send each row without ever holding the whole picture.
\
\ Load with:   REQUIRE qoi.f
\ Depends on:  surface.f (the encoder)
\
\ Public API:
\   QOI-FILE-SIZE  ( w h -- max-bytes )          Worst-case output size
\   QOI-ENCODE     ( surf buf max -- len | 0 )   Encode surface → QOI
\   QOI-HEADER     ( a u -- w h channels colorspace true | false )
\   QOI-DEC-SIZE   ( -- bytes )                  Decoder record size
\   QOI-DEC-INIT   ( w h dec -- )                Start after the header
\   QOI-DEC-FEED   ( src-a src-u row-a dec -- used status )
\   QOI-DEC-ROWS@  ( dec -- rows )               Rows completed
\
\ QOI-DEC-FEED statuses: QOI-S-MORE (all input used, row unfinished),
\ QOI-S-ROW (ROW-A holds the next complete row; USED may be less than
\ SRC-U), QOI-S-DONE (every pixel and the end marker read), QOI-S-BAD
\ (the end marker is wrong).  Returns 0 from QOI-ENCODE if the buffer is
\ too small.
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

\ =====================================================================
\  Header
\ =====================================================================

: _QOI-BE32@  ( a -- u32 )
    DUP C@ 24 LSHIFT
    OVER 1+ C@ 16 LSHIFT OR
    OVER 2 + C@ 8 LSHIFT OR
    SWAP 3 + C@ OR ;

VARIABLE _QH-A

\ QOI-HEADER ( a u -- w h channels colorspace true | false )
\   Read the 14-byte header that starts a QOI file.  False unless the magic
\   is "qoif", both dimensions are positive, channels is 3 or 4, and the
\   colorspace is 0 (sRGB) or 1 (linear).
: QOI-HEADER  ( a u -- w h channels colorspace true | false )
    QOI-HDR-SIZE < IF DROP FALSE EXIT THEN
    _QH-A !
    _QH-A @ _QOI-BE32@ 0x716F6966 <> IF FALSE EXIT THEN
    _QH-A @ 4 + _QOI-BE32@ 0= IF FALSE EXIT THEN
    _QH-A @ 8 + _QOI-BE32@ 0= IF FALSE EXIT THEN
    _QH-A @ 12 + C@ DUP 3 <> SWAP 4 <> AND IF FALSE EXIT THEN
    _QH-A @ 13 + C@ 1 U> IF FALSE EXIT THEN
    _QH-A @ 4 + _QOI-BE32@  _QH-A @ 8 + _QOI-BE32@
    _QH-A @ 12 + C@  _QH-A @ 13 + C@  TRUE ;

\ =====================================================================
\  Decoder record
\ =====================================================================
\
\  A pixel is a little-endian u32 whose bytes are R, G, B, A, so L! writes
\  it in the order the row buffer needs.

 0 CONSTANT _QD.W        \ width
 8 CONSTANT _QD.H        \ height
16 CONSTANT _QD.X        \ next pixel in the current row
24 CONSTANT _QD.Y        \ rows completed
32 CONSTANT _QD.RUN      \ pixels the current run still repeats
40 CONSTANT _QD.PX       \ previous pixel
48 CONSTANT _QD.PHASE
56 CONSTANT _QD.PART-N   \ bytes held of an operation split across chunks
64 CONSTANT _QD.PART     \ that operation, at most five bytes
72 CONSTANT _QD.END-N    \ end-marker bytes matched
80 CONSTANT _QD.INDEX    \ 64 pixels, four bytes each
336 CONSTANT QOI-DEC-SIZE

0 CONSTANT _QD-PH-PIXELS
1 CONSTANT _QD-PH-END
2 CONSTANT _QD-PH-DONE
3 CONSTANT _QD-PH-BAD

0 CONSTANT QOI-S-MORE
1 CONSTANT QOI-S-ROW
2 CONSTANT QOI-S-DONE
3 CONSTANT QOI-S-BAD

\ QOI-DEC-INIT ( w h dec -- )
\   Start decoding a W by H picture whose header has been read; the next
\   byte fed is the first byte after the header.
: QOI-DEC-INIT  ( w h dec -- )
    >R R@ QOI-DEC-SIZE 0 FILL
    R@ _QD.H + !  R@ _QD.W + !
    0xFF000000 R> _QD.PX + ! ;

: QOI-DEC-ROWS@  ( dec -- rows )  _QD.Y + @ ;

\ =====================================================================
\  Decoder: one feed
\ =====================================================================

VARIABLE _QD-S       \ the record
VARIABLE _QD-SRC     \ first input byte of this feed
VARIABLE _QD-P       \ next input byte
VARIABLE _QD-END     \ end of input
VARIABLE _QD-ROW     \ row buffer
VARIABLE _QD-X
VARIABLE _QD-W
VARIABLE _QD-RUN
VARIABLE _QD-PX
VARIABLE _QD-N       \ bytes of the operation gathered so far
VARIABLE _QD-DG

: _QD-LOAD  ( -- )
    _QD-S @ _QD.X + @ _QD-X !
    _QD-S @ _QD.W + @ _QD-W !
    _QD-S @ _QD.RUN + @ _QD-RUN !
    _QD-S @ _QD.PX + @ _QD-PX ! ;

: _QD-SAVE  ( -- )
    _QD-X @ _QD-S @ _QD.X + !
    _QD-RUN @ _QD-S @ _QD.RUN + !
    _QD-PX @ _QD-S @ _QD.PX + ! ;

: _QD-USED  ( -- used )  _QD-P @ _QD-SRC @ - ;

\ Where PX goes in the index: (r*3 + g*5 + b*7 + a*11) mod 64.
: _QD-SLOT  ( px -- addr )
    DUP 255 AND 3 *
    OVER 8 RSHIFT 255 AND 5 * +
    OVER 16 RSHIFT 255 AND 7 * +
    SWAP 24 RSHIFT 255 AND 11 * +
    63 AND 4 * _QD-S @ _QD.INDEX + + ;

\ Add DELTA to the channel at bit SHIFT, wrapping at 256.
: _QD-ADD  ( px delta shift -- px' )
    >R OVER R@ RSHIFT + 255 AND R@ LSHIFT
    SWAP 255 R> LSHIFT INVERT AND OR ;

: _QD-OP-LEN  ( op -- bytes )
    DUP 0xFF = IF DROP 5 EXIT THEN
    DUP 0xFE = IF DROP 4 EXIT THEN
    0xC0 AND 0x80 = IF 2 EXIT THEN
    1 ;

\ Gather the next whole operation into the record.  False when the input
\ ran out first; the bytes gathered so far wait in the record.
: _QD-TAKE  ( -- complete? )
    _QD-S @ _QD.PART-N + @ _QD-N !
    BEGIN
        _QD-N @ IF
            _QD-N @ _QD-S @ _QD.PART + C@ _QD-OP-LEN >= IF
                0 _QD-S @ _QD.PART-N + !  TRUE EXIT
            THEN
        THEN
        _QD-P @ _QD-END @ = IF
            _QD-N @ _QD-S @ _QD.PART-N + !  FALSE EXIT
        THEN
        _QD-P @ C@  _QD-S @ _QD.PART + _QD-N @ + C!
        1 _QD-P +!  1 _QD-N +!
    AGAIN ;

: _QD-RGB  ( a -- )
    DUP C@ OVER 1+ C@ 8 LSHIFT OR SWAP 2 + C@ 16 LSHIFT OR
    _QD-PX @ 0xFF000000 AND OR _QD-PX ! ;

: _QD-RGBA  ( a -- )
    DUP C@ OVER 1+ C@ 8 LSHIFT OR OVER 2 + C@ 16 LSHIFT OR
    SWAP 3 + C@ 24 LSHIFT OR _QD-PX ! ;

: _QD-DIFF  ( op -- )
    _QD-PX @
    OVER 4 RSHIFT 3 AND 2 - 0 _QD-ADD
    OVER 2 RSHIFT 3 AND 2 - 8 _QD-ADD
    SWAP 3 AND 2 - 16 _QD-ADD
    _QD-PX ! ;

: _QD-LUMA  ( op b2 -- )
    SWAP 63 AND 32 - _QD-DG !
    _QD-PX @
    OVER 4 RSHIFT 8 - _QD-DG @ + 0 _QD-ADD
    _QD-DG @ 8 _QD-ADD
    SWAP 15 AND 8 - _QD-DG @ + 16 _QD-ADD
    _QD-PX ! ;

\ Apply the gathered operation.  A run sets how many more pixels repeat
\ this one.  Every operation records the pixel in the index.
: _QD-APPLY  ( -- )
    _QD-S @ _QD.PART + DUP C@
    DUP 0xFE = IF DROP 1+ _QD-RGB ELSE
    DUP 0xFF = IF DROP 1+ _QD-RGBA ELSE
    DUP 0xC0 AND 0x00 = IF NIP 63 AND 4 * _QD-S @ _QD.INDEX + + L@ _QD-PX ! ELSE
    DUP 0xC0 AND 0x40 = IF NIP _QD-DIFF ELSE
    DUP 0xC0 AND 0x80 = IF SWAP 1+ C@ _QD-LUMA ELSE
        NIP 63 AND _QD-RUN !
    THEN THEN THEN THEN THEN
    _QD-PX @ DUP _QD-SLOT L! ;

: _QD-PUT  ( -- )
    _QD-PX @ _QD-ROW @ _QD-X @ 4 * + L!
    1 _QD-X +! ;

\ Seven zero bytes and a one end the file.
CREATE _QD-MARKER 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 1 C,

: _QD-END-MARKER  ( -- used status )
    BEGIN
        _QD-S @ _QD.END-N + @ 8 = IF
            _QD-PH-DONE _QD-S @ _QD.PHASE + !
            _QD-USED QOI-S-DONE EXIT
        THEN
        _QD-P @ _QD-END @ = IF _QD-USED QOI-S-MORE EXIT THEN
        _QD-P @ C@  _QD-MARKER _QD-S @ _QD.END-N + @ + C@ <> IF
            _QD-PH-BAD _QD-S @ _QD.PHASE + !
            _QD-USED QOI-S-BAD EXIT
        THEN
        1 _QD-P +!  1 _QD-S @ _QD.END-N + +!
    AGAIN ;

\ QOI-DEC-FEED ( src-a src-u row-a dec -- used status )
\   Decode from SRC until the next row is complete, the input runs out, or
\   the file ends.  ROW-A holds at least width * 4 bytes and keeps a partly
\   decoded row between feeds.
: QOI-DEC-FEED  ( src-a src-u row-a dec -- used status )
    _QD-S ! _QD-ROW !
    OVER + _QD-END !  DUP _QD-SRC !  _QD-P !
    _QD-S @ _QD.PHASE + @
    DUP _QD-PH-DONE = IF DROP 0 QOI-S-DONE EXIT THEN
    DUP _QD-PH-BAD = IF DROP 0 QOI-S-BAD EXIT THEN
    _QD-PH-END = IF _QD-END-MARKER EXIT THEN
    _QD-LOAD
    BEGIN
        _QD-RUN @ IF
            -1 _QD-RUN +!  _QD-PUT
        ELSE
            _QD-TAKE 0= IF _QD-SAVE _QD-USED QOI-S-MORE EXIT THEN
            _QD-APPLY _QD-PUT
        THEN
        _QD-X @ _QD-W @ =
    UNTIL
    0 _QD-X !
    1 _QD-S @ _QD.Y + +!
    \ A run longer than the picture ends with it.
    _QD-S @ _QD.Y + @ _QD-S @ _QD.H + @ = IF
        _QD-PH-END _QD-S @ _QD.PHASE + !
    THEN
    _QD-SAVE _QD-USED QOI-S-ROW ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _qoi-guard

' QOI-FILE-SIZE   CONSTANT _qoi-file-size-xt
' QOI-ENCODE      CONSTANT _qoi-encode-xt
' QOI-HEADER      CONSTANT _qoi-header-xt
' QOI-DEC-FEED    CONSTANT _qoi-dec-feed-xt

: QOI-FILE-SIZE   _qoi-file-size-xt _qoi-guard WITH-GUARD ;
: QOI-ENCODE      _qoi-encode-xt _qoi-guard WITH-GUARD ;
: QOI-HEADER      _qoi-header-xt _qoi-guard WITH-GUARD ;
: QOI-DEC-FEED    _qoi-dec-feed-xt _qoi-guard WITH-GUARD ;
[THEN] [THEN]
