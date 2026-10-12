\ =================================================================
\  png.f  —  resumable PNG decoder
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PNG- (public), _PN- (private)
\  Depends on: utils/inflate.f, math/crc.f
\
\  Public API:
\   PNG-HDR-SIZE  ( -- 33 )      bytes PNG-HEADER reads
\   PNG-HEADER    ( a u -- w h status )
\   PNG-DEC-SIZE  ( w -- bytes ) a decoder for pictures W pixels wide
\   PNG-DEC-INIT  ( w dec -- )
\   PNG-DEC-FEED  ( src-a src-u row-a dec -- used status )
\   PNG-DEC-ROWS@ ( dec -- rows )
\   PNG-UNFILTER  ( filter row prev n bpp -- ok? )
\
\  PNG-HEADER reads a file's signature and IHDR chunk: the picture's size
\  and PNG-H-OK when this module decodes it, PNG-H-NOT for no PNG file,
\  PNG-H-DAMAGED for a wrong IHDR, and PNG-H-UNSUPPORTED for an
\  interlaced one.
\
\  The decoder reads the file from its first byte, as the caller has it,
\  and hands back one row at a time as R, G, B, A bytes, like the QOI
\  decoder, with the same statuses: PNG-S-MORE (all input used, the row
\  unfinished), PNG-S-ROW (a row is in the caller's row buffer, W * 4
\  bytes), PNG-S-DONE (the file ended well after its last row), PNG-S-BAD
\  (damaged).  DONE and BAD stay.  It checks every chunk's CRC, takes the
\  palette and transparency, inflates the image data across its chunks,
\  undoes each row's filter, and widens every colour type and bit depth
\  to eight bits a channel: sixteen-bit samples by their high byte, and
\  smaller grey samples scaled to the full range.
\
\  The caller owns the decoder, PNG-DEC-SIZE bytes for the picture's
\  width, cell-aligned: its record, the inflater's window and the two rows
\  a filter needs.  It allocates nothing.  PNG-UNFILTER undoes one row's
\  filter for any caller, such as a PDF Flate stream's predictor.
\
\  Not reentrant: one feed runs at a time, though any number of decoders
\  may take turns.
\ =================================================================

PROVIDED akashic-png

REQUIRE ../utils/inflate.f
REQUIRE ../math/crc.f

0 CONSTANT PNG-S-MORE
1 CONSTANT PNG-S-ROW
2 CONSTANT PNG-S-DONE
3 CONSTANT PNG-S-BAD

0 CONSTANT PNG-H-OK
1 CONSTANT PNG-H-NOT
2 CONSTANT PNG-H-DAMAGED
3 CONSTANT PNG-H-UNSUPPORTED

33 CONSTANT PNG-HDR-SIZE

\ =====================================================================
\  The rows' filters
\ =====================================================================

\ The Paeth predictor of A, B and C.
: _PN-PAETH  ( a b c -- p )
    2 PICK 2 PICK + OVER -                       ( a b c p )
    3 PICK OVER - ABS                            ( a b c p pa )
    3 PICK 2 PICK - ABS                          ( a b c p pa pb )
    ROT 3 PICK - ABS                             ( a b c pa pb pc )
    2 PICK 2 PICK > 0= 3 PICK 2 PICK > 0= AND IF 2DROP 2DROP DROP EXIT THEN
    > 0= IF 2DROP NIP EXIT THEN
    DROP NIP NIP ;

VARIABLE _PNF-ROW  VARIABLE _PNF-PREV  VARIABLE _PNF-BPP

\ PNG-UNFILTER ( filter row prev n bpp -- ok? )
\   Undo FILTER on N bytes at ROW in place, with the row before at PREV,
\   zeros for the first row, and BPP bytes a whole pixel, at least one.
\   False for no filter PNG defines.
: PNG-UNFILTER  ( filter row prev n bpp -- ok? )
    _PNF-BPP ! >R _PNF-PREV ! _PNF-ROW ! R>             ( filter n )
    SWAP CASE
        0 OF DROP -1 ENDOF
        1 OF _PNF-BPP @ ?DO
                 _PNF-ROW @ I + DUP C@ OVER _PNF-BPP @ - C@ + SWAP C!
             LOOP -1 ENDOF
        2 OF 0 ?DO
                 _PNF-ROW @ I + DUP C@ _PNF-PREV @ I + C@ + SWAP C!
             LOOP -1 ENDOF
        3 OF 0 ?DO
                 I _PNF-BPP @ < IF 0 ELSE _PNF-ROW @ I + _PNF-BPP @ - C@ THEN
                 _PNF-PREV @ I + C@ + 1 RSHIFT
                 _PNF-ROW @ I + DUP C@ ROT + SWAP C!
             LOOP -1 ENDOF
        4 OF 0 ?DO
                 I _PNF-BPP @ < IF
                     0 _PNF-PREV @ I + C@ 0
                 ELSE
                     _PNF-ROW @ I + _PNF-BPP @ - C@
                     _PNF-PREV @ I + C@
                     _PNF-PREV @ I + _PNF-BPP @ - C@
                 THEN _PN-PAETH
                 _PNF-ROW @ I + DUP C@ ROT + SWAP C!
             LOOP -1 ENDOF
        NIP 0 SWAP
    ENDCASE ;

\ =====================================================================
\  The header
\ =====================================================================

CREATE _PN-SIGNATURE  137 C, 80 C, 78 C, 71 C, 13 C, 10 C, 26 C, 10 C,

: _PN-BE32  ( a -- u )
    DUP C@ 24 LSHIFT OVER 1+ C@ 16 LSHIFT OR
    OVER 2 + C@ 8 LSHIFT OR SWAP 3 + C@ OR ;

: _PN-BE16  ( a -- u )  DUP C@ 8 LSHIFT SWAP 1+ C@ OR ;

\ A bit depth and colour type PNG allows together.
: _PN-DEPTH-OK?  ( depth colour -- flag )
    CASE
        0 OF DUP 1 = OVER 2 = OR OVER 4 = OR OVER 8 = OR SWAP 16 = OR ENDOF
        3 OF DUP 1 = OVER 2 = OR OVER 4 = OR SWAP 8 = OR ENDOF
        2 OF DUP 8 = SWAP 16 = OR ENDOF
        4 OF DUP 8 = SWAP 16 = OR ENDOF
        6 OF DUP 8 = SWAP 16 = OR ENDOF
        NIP 0 SWAP
    ENDCASE ;

\ PNG-HEADER ( a u -- w h status )
\   The size and status of the PNG file whose first U bytes are at A, U at
\   least PNG-HDR-SIZE for any answer but PNG-H-NOT.
: PNG-HEADER  ( a u -- w h status )
    DUP 8 < IF 2DROP 0 0 PNG-H-NOT EXIT THEN
    OVER 8 _PN-SIGNATURE 8 COMPARE IF 2DROP 0 0 PNG-H-NOT EXIT THEN
    PNG-HDR-SIZE < IF DROP 0 0 PNG-H-DAMAGED EXIT THEN    ( a )
    DUP 8 + _PN-BE32 13 <>
    OVER 12 + 4 S" IHDR" COMPARE OR
    OVER 29 + _PN-BE32  0 3 PICK 12 + 17 CRC32-UPDATE <> OR IF
        DROP 0 0 PNG-H-DAMAGED EXIT
    THEN
    DUP 16 + _PN-BE32 OVER 20 + _PN-BE32                   ( a w h )
    OVER 1 0x80000000 WITHIN 0= OVER 1 0x80000000 WITHIN 0= OR
    3 PICK 24 + C@ 4 PICK 25 + C@ _PN-DEPTH-OK? 0= OR
    3 PICK 26 + C@ OR  3 PICK 27 + C@ OR
    3 PICK 28 + C@ 1 > OR IF ROT DROP PNG-H-DAMAGED EXIT THEN
    ROT 28 + C@ IF PNG-H-UNSUPPORTED ELSE PNG-H-OK THEN ;

\ =====================================================================
\  The decoder
\ =====================================================================
\   +0   phase              +8   status, once done or damaged
\   +16  width              +24  height
\   +32  bit depth          +40  colour type
\   +48  bytes a pixel      +56  bytes a row, after its filter byte
\   +64  rows done          +72  chunk bytes left
\   +80  chunk type         +88  chunk CRC so far
\   +96  bytes kept         +104 kept (16)
\   +120 bytes of the row   +128 this row          +136 the row before
\   +144 palette entries    +152 transparency key? +160 key (3 cells)
\   +184 chunks seen        +192 image data over?  +200 stream ended?
\   +208 chunk length
\   +216 palette (256 R, G, B, A)
\   +1240 a chunk's data until it is whole (768)
\   +2008 the inflater      +5032 its window (32 KB)
\   +37800 two rows

  0 CONSTANT _PN.PHASE
  8 CONSTANT _PN.STATUS
 16 CONSTANT _PN.W
 24 CONSTANT _PN.H
 32 CONSTANT _PN.DEPTH
 40 CONSTANT _PN.COLOUR
 48 CONSTANT _PN.BPP
 56 CONSTANT _PN.STRIDE
 64 CONSTANT _PN.Y
 72 CONSTANT _PN.LEFT
 80 CONSTANT _PN.TYPE
 88 CONSTANT _PN.CRC
 96 CONSTANT _PN.KEPT-N
104 CONSTANT _PN.KEPT
120 CONSTANT _PN.RPOS
128 CONSTANT _PN.CUR
136 CONSTANT _PN.PREV
144 CONSTANT _PN.PLTE-N
152 CONSTANT _PN.HAVE-KEY
160 CONSTANT _PN.KEY
184 CONSTANT _PN.SEEN
192 CONSTANT _PN.ENDED
200 CONSTANT _PN.ZDONE
208 CONSTANT _PN.CHUNK-LEN
216 CONSTANT _PN.PALETTE
1240 CONSTANT _PN.STAGE
2008 CONSTANT _PN.INFL
_PN.INFL INFL-SIZE + CONSTANT _PN.WINDOW
_PN.WINDOW 32768 + CONSTANT _PN.ROWS

\ The bytes of one row buffer for a picture W pixels wide: its filter
\ byte and up to eight bytes a pixel, rounded to a cell.
: _PN-ROW-BYTES  ( w -- bytes )  8 * 1+ 7 + -8 AND ;

\ PNG-DEC-SIZE ( w -- bytes )   A decoder for pictures W pixels wide.
: PNG-DEC-SIZE  ( w -- bytes )  _PN-ROW-BYTES 2* _PN.ROWS + ;

\ Phases.
0 CONSTANT _PN-P-SIG
1 CONSTANT _PN-P-HEAD
2 CONSTANT _PN-P-DATA
3 CONSTANT _PN-P-CRC

\ Chunks seen.
1 CONSTANT _PN-SEEN-IHDR
2 CONSTANT _PN-SEEN-PLTE
4 CONSTANT _PN-SEEN-IDAT
8 CONSTANT _PN-SEEN-TRNS

VARIABLE _PN-D        \ the decoder
VARIABLE _PN-SRC      \ the next input byte
VARIABLE _PN-LEFT     \ input bytes left
VARIABLE _PN-ROW-A    \ the caller's row

: _PN@  ( offset -- x )  _PN-D @ + @ ;
: _PN!  ( x offset -- )  _PN-D @ + ! ;
: _PN-KEPT   ( -- a )  _PN-D @ _PN.KEPT + ;
: _PN-STAGED ( -- a )  _PN-D @ _PN.STAGE + ;

\ PNG-DEC-INIT ( w dec -- )   Start decoding a picture W pixels wide.
: PNG-DEC-INIT  ( w dec -- )
    DUP _PN-D !  _PN.ROWS 0 FILL
    DUP _PN.W _PN!
    _PN-D @ _PN.ROWS + _PN.CUR _PN!
    _PN-ROW-BYTES DUP _PN-D @ _PN.ROWS + + DUP _PN.PREV _PN!
    \ The first row's filter reads zeros for the row before.
    SWAP 0 FILL ;

\ PNG-DEC-ROWS@ ( dec -- rows )   Rows handed back so far.
: PNG-DEC-ROWS@  ( dec -- rows )  _PN.Y + @ ;

: _PN-BAD  ( -- status )  PNG-S-BAD DUP _PN.STATUS _PN! ;

\ Take N input bytes, which count toward the chunk's CRC.
: _PN-TAKE  ( n -- )
    _PN.CRC _PN@ _PN-SRC @ 2 PICK CRC32-UPDATE _PN.CRC _PN!
    DUP _PN-SRC +!  NEGATE _PN-LEFT +! ;

\ Keep input bytes until N are kept: true once they are.
: _PN-KEEP?  ( n -- all? )
    DUP _PN.KEPT-N _PN@ - _PN-LEFT @ MIN                 ( n k )
    _PN-SRC @ _PN-KEPT _PN.KEPT-N _PN@ + 2 PICK MOVE
    DUP _PN.KEPT-N _PN@ + _PN.KEPT-N _PN!
    DUP _PN-SRC +!  NEGATE _PN-LEFT +!
    _PN.KEPT-N _PN@ = ;

\ =====================================================================
\  Rows out
\ =====================================================================

VARIABLE _PNE-S     \ next sample byte
VARIABLE _PNE-D     \ next output byte
VARIABLE _PNE-BIT   \ bits used of the sample byte

\ The next sample of DEPTH bits from a packed row, high bits first.
: _PN-SAMPLE  ( depth -- v )
    DUP 8 < IF
        _PNE-S @ C@ 8 _PNE-BIT @ - 2 PICK - RSHIFT
        1 2 PICK LSHIFT 1- AND
        SWAP _PNE-BIT +!
        _PNE-BIT @ 8 = IF 0 _PNE-BIT !  1 _PNE-S +! THEN EXIT
    THEN
    8 = IF _PNE-S @ C@ 1 _PNE-S +! EXIT THEN
    _PNE-S @ C@ 8 LSHIFT _PNE-S @ 1+ C@ OR  2 _PNE-S +! ;

\ A sample of DEPTH bits widened to eight.
: _PN-WIDEN  ( v depth -- byte )
    CASE
        1 OF 255 * ENDOF
        2 OF 85 * ENDOF
        4 OF 17 * ENDOF
        16 OF 8 RSHIFT ENDOF
    ENDCASE ;

: _PN-PUT  ( byte -- )  _PNE-D @ C!  1 _PNE-D +! ;
: _PN-KEY@  ( i -- v )  CELLS _PN.KEY + _PN@ ;
: _PN-NEXT  ( -- byte )  _PN.DEPTH _PN@ DUP _PN-SAMPLE SWAP _PN-WIDEN ;

\ Widen the unfiltered row to R, G, B, A in the caller's row.  False for a
\ palette index past the palette.
: _PN-EMIT  ( -- ok? )
    _PN.CUR _PN@ 1+ _PNE-S !  _PN-ROW-A @ _PNE-D !  0 _PNE-BIT !
    _PN.W _PN@ 0 ?DO
        _PN.COLOUR _PN@ CASE
            0 OF
                _PN.DEPTH _PN@ _PN-SAMPLE
                DUP _PN.DEPTH _PN@ _PN-WIDEN DUP _PN-PUT DUP _PN-PUT _PN-PUT
                _PN.HAVE-KEY _PN@ IF 0 _PN-KEY@ = IF 0 ELSE 255 THEN
                ELSE DROP 255 THEN _PN-PUT
            ENDOF
            2 OF
                _PN.DEPTH _PN@ _PN-SAMPLE _PN.DEPTH _PN@ _PN-SAMPLE
                _PN.DEPTH _PN@ _PN-SAMPLE                     ( r g b )
                _PN.HAVE-KEY _PN@ IF
                    DUP 2 _PN-KEY@ = 2 PICK 1 _PN-KEY@ = AND
                    3 PICK 0 _PN-KEY@ = AND
                ELSE 0 THEN >R
                ROT _PN.DEPTH _PN@ _PN-WIDEN _PN-PUT
                SWAP _PN.DEPTH _PN@ _PN-WIDEN _PN-PUT
                _PN.DEPTH _PN@ _PN-WIDEN _PN-PUT
                R> IF 0 ELSE 255 THEN _PN-PUT
            ENDOF
            3 OF
                _PN.DEPTH _PN@ _PN-SAMPLE
                DUP _PN.PLTE-N _PN@ < 0= IF DROP 0 UNLOOP EXIT THEN
                4 * _PN-D @ _PN.PALETTE + + _PNE-D @ 4 MOVE  4 _PNE-D +!
            ENDOF
            4 OF _PN-NEXT DUP _PN-PUT DUP _PN-PUT _PN-PUT _PN-NEXT _PN-PUT ENDOF
            6 OF _PN-NEXT _PN-PUT _PN-NEXT _PN-PUT _PN-NEXT _PN-PUT _PN-NEXT _PN-PUT ENDOF
        ENDCASE
    LOOP -1 ;

\ The current row is whole: undo its filter, hand it back, and keep it
\ as the row before.
: _PN-ROW-DONE  ( -- status )
    _PN.CUR _PN@ C@ _PN.CUR _PN@ 1+ _PN.PREV _PN@ 1+
    _PN.STRIDE _PN@ _PN.BPP _PN@ PNG-UNFILTER 0= IF _PN-BAD EXIT THEN
    _PN-EMIT 0= IF _PN-BAD EXIT THEN
    _PN.CUR _PN@ _PN.PREV _PN@ _PN.CUR _PN! _PN.PREV _PN!
    0 _PN.RPOS _PN!
    _PN.Y _PN@ 1+ _PN.Y _PN!
    PNG-S-ROW ;

\ =====================================================================
\  Chunks
\ =====================================================================

CREATE _PN-T-IHDR  73 C, 72 C, 68 C, 82 C,
CREATE _PN-T-PLTE  80 C, 76 C, 84 C, 69 C,
CREATE _PN-T-IDAT  73 C, 68 C, 65 C, 84 C,
CREATE _PN-T-IEND  73 C, 69 C, 78 C, 68 C,
CREATE _PN-T-TRNS  116 C, 82 C, 78 C, 83 C,

: _PN-TYPE?  ( c-addr -- flag )  _PN-BE32 _PN.TYPE _PN@ = ;
: _PN-SEEN?  ( flag -- set? )  _PN.SEEN _PN@ AND 0<> ;
: _PN-SEEN!  ( flag -- )  _PN.SEEN _PN@ OR _PN.SEEN _PN! ;

\ The IHDR's fields set the picture's shape and start the inflater.
: _PN-IHDR  ( -- ok? )
    _PN-STAGED _PN-BE32 _PN.W _PN@ <> IF 0 EXIT THEN
    _PN-STAGED 4 + _PN-BE32 DUP 1 0x80000000 WITHIN 0= IF DROP 0 EXIT THEN
    _PN.H _PN!
    _PN-STAGED 8 + C@ _PN-STAGED 9 + C@                  ( depth colour )
    2DUP _PN-DEPTH-OK? 0= IF 2DROP 0 EXIT THEN
    _PN.COLOUR _PN!  _PN.DEPTH _PN!
    _PN-STAGED 10 + C@ _PN-STAGED 11 + C@ OR _PN-STAGED 12 + C@ OR IF 0 EXIT THEN
    \ Samples a pixel, then bits a pixel.
    _PN.COLOUR _PN@ CASE 0 OF 1 ENDOF 2 OF 3 ENDOF 3 OF 1 ENDOF 4 OF 2 ENDOF
        6 OF 4 ENDOF ENDCASE
    _PN.DEPTH _PN@ *                                      ( bits )
    DUP 7 + 3 RSHIFT 1 MAX _PN.BPP _PN!
    _PN.W _PN@ * 7 + 3 RSHIFT _PN.STRIDE _PN!
    _PN-D @ _PN.WINDOW + 32768 INFL-W-ZLIB _PN-D @ _PN.INFL + INFL-INIT
    -1 ;

\ A whole IHDR, PLTE or tRNS takes effect.
: _PN-APPLY  ( -- ok? )
    _PN-T-IHDR _PN-TYPE? IF _PN-IHDR DUP IF _PN-SEEN-IHDR _PN-SEEN! THEN EXIT THEN
    _PN-T-PLTE _PN-TYPE? IF
        _PN.PLTE-N _PN@ 0 ?DO
            _PN-STAGED I 3 * +  _PN-D @ _PN.PALETTE + I 4 * +  3 MOVE
            255 _PN-D @ _PN.PALETTE + I 4 * + 3 + C!
        LOOP  _PN-SEEN-PLTE _PN-SEEN!  -1 EXIT
    THEN
    _PN-T-TRNS _PN-TYPE? IF
        _PN.COLOUR _PN@ 3 = IF
            _PN.CHUNK-LEN _PN@ 0 ?DO
                _PN-STAGED I + C@  _PN-D @ _PN.PALETTE + I 4 * + 3 + C!
            LOOP
        ELSE
            _PN.CHUNK-LEN _PN@ 2/ 0 ?DO
                _PN-STAGED I 2* + _PN-BE16  I CELLS _PN.KEY + _PN!
            LOOP  -1 _PN.HAVE-KEY _PN!
        THEN  -1 EXIT
    THEN
    -1 ;

\ Where a chunk's data waits until it is whole, or 0 to skip it.
: _PN-STAGE  ( -- a|0 )
    _PN-T-IHDR _PN-TYPE? _PN-T-PLTE _PN-TYPE? OR _PN-T-TRNS _PN-TYPE? OR
    IF _PN-STAGED ELSE 0 THEN ;

\ A chunk's head is kept: its length and type.
: _PN-HEAD  ( -- status|-1 )
    _PN-KEPT _PN-BE32 DUP 0x7FFFFFFF U> IF DROP _PN-BAD EXIT THEN
    DUP _PN.LEFT _PN!  _PN.CHUNK-LEN _PN!
    _PN-KEPT 4 + _PN-BE32 _PN.TYPE _PN!
    0 _PN-KEPT 4 + 4 CRC32-UPDATE _PN.CRC _PN!
    0 _PN.KEPT-N _PN!
    _PN-SEEN-IHDR _PN-SEEN? 0= IF
        _PN-T-IHDR _PN-TYPE? 0= _PN.LEFT _PN@ 13 <> OR IF _PN-BAD EXIT THEN
    ELSE
        _PN-T-IHDR _PN-TYPE? IF _PN-BAD EXIT THEN
        _PN-T-PLTE _PN-TYPE? IF
            _PN.LEFT _PN@ DUP 3 MOD SWAP 768 > OR _PN.LEFT _PN@ 0= OR
            _PN-SEEN-PLTE _PN-SEEN? OR  _PN-SEEN-IDAT _PN-SEEN? OR
            IF _PN-BAD EXIT THEN
            _PN.LEFT _PN@ 3 / _PN.PLTE-N _PN!
        THEN
        _PN-T-TRNS _PN-TYPE? IF
            _PN-SEEN-IDAT _PN-SEEN? _PN-SEEN-TRNS _PN-SEEN? OR IF _PN-BAD EXIT THEN
            _PN.COLOUR _PN@ 4 AND IF _PN-BAD EXIT THEN
            _PN.COLOUR _PN@ 3 = IF
                _PN.LEFT _PN@ _PN.PLTE-N _PN@ > IF _PN-BAD EXIT THEN
            ELSE
                _PN.LEFT _PN@ _PN.COLOUR _PN@ 2 = IF 6 ELSE 2 THEN <>
                IF _PN-BAD EXIT THEN
            THEN
            _PN-SEEN-TRNS _PN-SEEN!
        THEN
        _PN-T-IDAT _PN-TYPE? IF
            _PN.ENDED _PN@ IF _PN-BAD EXIT THEN
            _PN.COLOUR _PN@ 3 = _PN-SEEN-PLTE _PN-SEEN? 0= AND IF _PN-BAD EXIT THEN
            _PN-SEEN-IDAT _PN-SEEN!
        ELSE
            _PN-SEEN-IDAT _PN-SEEN? IF -1 _PN.ENDED _PN! THEN
        THEN
        \ An unknown chunk is skipped unless it is critical.
        _PN.TYPE _PN@ 24 RSHIFT 32 AND 0=
        _PN-T-PLTE _PN-TYPE? 0= AND  _PN-T-IDAT _PN-TYPE? 0= AND
        _PN-T-IEND _PN-TYPE? 0= AND IF _PN-BAD EXIT THEN
        _PN-T-IEND _PN-TYPE? _PN.LEFT _PN@ 0<> AND IF _PN-BAD EXIT THEN
    THEN
    _PN.LEFT _PN@ IF _PN-P-DATA ELSE _PN-P-CRC THEN _PN.PHASE _PN!  -1 ;

\ Image data: inflate into the row being assembled.
VARIABLE _PNI-USED  VARIABLE _PNI-GIVEN  VARIABLE _PNI-STATUS
: _PN-IDAT  ( -- status|-1 )
    BEGIN _PN.LEFT _PN@ _PN-LEFT @ MIN ?DUP WHILE          ( n )
        _PN.ZDONE _PN@ IF
            \ Data after the stream's end is skipped.
            DUP _PN-TAKE  NEGATE _PN.LEFT _PN@ + _PN.LEFT _PN!
        ELSE
            _PN-SRC @ SWAP
            _PN.Y _PN@ _PN.H _PN@ < IF
                _PN.CUR _PN@ _PN.RPOS _PN@ +
                _PN.STRIDE _PN@ 1+ _PN.RPOS _PN@ -
            ELSE _PN-ROW-A @ 0 THEN
            _PN-D @ _PN.INFL + INFL-FEED
            _PNI-STATUS ! _PNI-GIVEN ! _PNI-USED !
            _PNI-USED @ _PN-TAKE  _PNI-USED @ NEGATE _PN.LEFT _PN@ + _PN.LEFT _PN!
            _PNI-GIVEN @ _PN.RPOS _PN@ + _PN.RPOS _PN!
            _PNI-STATUS @ INFL-S-BAD = IF _PN-BAD EXIT THEN
            _PNI-STATUS @ INFL-S-DONE = IF -1 _PN.ZDONE _PN! THEN
            _PN.Y _PN@ _PN.H _PN@ < IF
                _PN.RPOS _PN@ _PN.STRIDE _PN@ 1+ = IF _PN-ROW-DONE EXIT THEN
                \ The stream ended before the picture did.
                _PNI-STATUS @ INFL-S-DONE = IF _PN-BAD EXIT THEN
            ELSE
                \ After the last row only the stream's end may follow.
                _PNI-STATUS @ INFL-S-FULL = IF _PN-BAD EXIT THEN
            THEN
        THEN
    REPEAT
    _PN.LEFT _PN@ IF PNG-S-MORE EXIT THEN
    _PN-P-CRC _PN.PHASE _PN!  -1 ;

\ A chunk's data.
: _PN-DATA  ( -- status|-1 )
    _PN-T-IDAT _PN-TYPE? IF _PN-IDAT EXIT THEN
    _PN.LEFT _PN@ _PN-LEFT @ MIN                            ( n )
    _PN-STAGE ?DUP IF
        _PN.CHUNK-LEN _PN@ _PN.LEFT _PN@ - +                ( n dst )
        _PN-SRC @ SWAP 2 PICK MOVE
    THEN
    DUP _PN-TAKE  NEGATE _PN.LEFT _PN@ + _PN.LEFT _PN!
    _PN.LEFT _PN@ IF PNG-S-MORE EXIT THEN
    _PN-APPLY 0= IF _PN-BAD EXIT THEN
    _PN-P-CRC _PN.PHASE _PN!  -1 ;

: _PN-CRC  ( -- status|-1 )
    4 _PN-KEEP? 0= IF PNG-S-MORE EXIT THEN
    _PN-KEPT _PN-BE32 _PN.CRC _PN@ <> IF _PN-BAD EXIT THEN
    0 _PN.KEPT-N _PN!
    _PN-T-IEND _PN-TYPE? IF
        _PN.Y _PN@ _PN.H _PN@ = _PN.ZDONE _PN@ AND 0= IF _PN-BAD EXIT THEN
        PNG-S-DONE DUP _PN.STATUS _PN! EXIT
    THEN
    _PN-P-HEAD _PN.PHASE _PN!  -1 ;

: _PN-SIG  ( -- status|-1 )
    8 _PN-KEEP? 0= IF PNG-S-MORE EXIT THEN
    _PN-KEPT 8 _PN-SIGNATURE 8 COMPARE IF _PN-BAD EXIT THEN
    0 _PN.KEPT-N _PN!  _PN-P-HEAD _PN.PHASE _PN!  -1 ;

: _PN-STEP  ( -- status|-1 )
    _PN.PHASE _PN@ CASE
        _PN-P-SIG  OF _PN-SIG ENDOF
        _PN-P-HEAD OF 8 _PN-KEEP? IF _PN-HEAD ELSE PNG-S-MORE THEN ENDOF
        _PN-P-DATA OF _PN-DATA ENDOF
        _PN-P-CRC  OF _PN-CRC ENDOF
        PNG-S-BAD SWAP
    ENDCASE ;

\ PNG-DEC-FEED ( src-a src-u row-a dec -- used status )
\   Decode from SRC-U bytes at SRC-A, the file's next bytes, a row at most,
\   into the row at ROW-A.
: PNG-DEC-FEED  ( src-a src-u row-a dec -- used status )
    _PN-D !  _PN-ROW-A !  _PN-LEFT !  DUP _PN-SRC !  >R
    _PN.STATUS _PN@ ?DUP IF R> DROP 0 SWAP EXIT THEN
    BEGIN _PN-STEP DUP -1 = WHILE DROP REPEAT
    _PN-SRC @ R> - SWAP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _png-guard

' PNG-DEC-FEED  CONSTANT _png-dec-feed-xt

: PNG-DEC-FEED  _png-dec-feed-xt _png-guard WITH-GUARD ;
[THEN] [THEN]
