\ qoi.f — QOI pictures: the header and a resumable decoder
\
\ Decodes QOI files ("Quite OK Image") a chunk at a time.  The decoder
\ keeps its whole state in a record its caller owns and never allocates.
\ It reads whatever chunks of the file the caller has, picks up an
\ operation split between two chunks, and writes one row at a time into a
\ caller row buffer, in R, G, B, A byte order (the order the rich
\ terminal's RGBA8 resources use).  A caller can therefore scale, hash or
\ send each row without ever holding the whole picture.
\
\ Encoding a surface is qoi-encode.f, kept apart so a decoder never loads
\ the surface renderer.
\
\ Load with:   REQUIRE qoi.f
\
\ Public API:
\   QOI-HEADER     ( a u -- w h channels colorspace true | false )
\   QOI-DEC-SIZE   ( -- bytes )                  Decoder record size
\   QOI-DEC-INIT   ( w h dec -- )                Start after the header
\   QOI-DEC-FEED   ( src-a src-u row-a dec -- used status )
\   QOI-DEC-ROWS@  ( dec -- rows )               Rows completed
\
\ QOI-DEC-FEED statuses: QOI-S-MORE (all input used, row unfinished),
\ QOI-S-ROW (ROW-A holds the next complete row; USED may be less than
\ SRC-U), QOI-S-DONE (every pixel and the end marker read), QOI-S-BAD
\ (the end marker is wrong).
\ =====================================================================

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

' QOI-HEADER      CONSTANT _qoi-header-xt
' QOI-DEC-FEED    CONSTANT _qoi-dec-feed-xt

: QOI-HEADER      _qoi-header-xt _qoi-guard WITH-GUARD ;
: QOI-DEC-FEED    _qoi-dec-feed-xt _qoi-guard WITH-GUARD ;
[THEN] [THEN]
