\ =================================================================
\  inflate.f  —  resumable DEFLATE decoder, with zlib and gzip
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: INFL- (public), _IF- (private)
\  Depends on: math/adler32.f, math/crc.f
\
\  Public API:
\   INFL-SIZE     ( -- bytes )     the decoder's record
\   INFL-INIT     ( window-a window-u wrapper infl -- )
\   INFL-FEED     ( in-a in-u out-a out-u infl -- in-used out-used status )
\   INFL-REASON@  ( infl -- reason )   why a stream is damaged, or 0
\   INFL-TOTAL@   ( infl -- bytes )    bytes the stream has given so far
\
\  Wrappers: INFL-W-RAW (bare deflate), INFL-W-ZLIB (RFC 1950, its
\  Adler-32 checked), INFL-W-GZIP (RFC 1952, one member, its CRC-32 and
\  length checked).
\
\  Statuses, from INFL-FEED:
\   INFL-S-MORE  all of the input is used and the stream wants more
\   INFL-S-FULL  the output is full and the stream has more to give
\   INFL-S-DONE  the stream has ended and its sum matches
\   INFL-S-BAD   the stream is damaged; INFL-REASON@ says why
\  DONE and BAD stay: a later feed uses nothing and gives nothing.
\
\  The caller owns the record, INFL-SIZE bytes, and the window, a power
\  of two from 256 bytes to 32 KB; the decoder allocates nothing.  A feed
\  takes whatever input the caller has and fills whatever output room it
\  gives.  A symbol cut between two feeds waits in the record's bit
\  buffer, so MORE means every input byte is used.  After DONE the input
\  the stream did not need is not counted as used.
\
\  A caller that keeps the whole output in one run gives no window, a
\  size of 0.  The output is then the window: each feed's room begins
\  right after the bytes the stream has given, and before it gives one,
\  any room begins it.  A feed whose room begins anywhere else finds the
\  stream bad, for its window.
\
\  Huffman codes decode through lookup tables built in the record for
\  each block: a code of up to nine bits for a literal or length, and of
\  up to eight for a distance, is one lookup, and a longer one is read a
\  bit at a time.  Back-references copy within the window, which then
\  goes to the output in runs.
\
\  Not reentrant: a feed keeps its working state in module variables, so
\  one feed runs at a time, though any number of records may take turns.
\ =================================================================

PROVIDED akashic-inflate

REQUIRE ../math/adler32.f
REQUIRE ../math/crc.f

\ =====================================================================
\  Constants
\ =====================================================================

0 CONSTANT INFL-W-RAW
1 CONSTANT INFL-W-ZLIB
2 CONSTANT INFL-W-GZIP

0 CONSTANT INFL-S-MORE
1 CONSTANT INFL-S-FULL
2 CONSTANT INFL-S-DONE
3 CONSTANT INFL-S-BAD

\ Why a stream is damaged.
1 CONSTANT INFL-R-HEADER       \ a zlib or gzip header that is not one
2 CONSTANT INFL-R-WINDOW       \ the window is too small for the stream
3 CONSTANT INFL-R-DICTIONARY   \ a zlib stream that needs a preset dictionary
4 CONSTANT INFL-R-BLOCK        \ a block of the reserved type
5 CONSTANT INFL-R-STORED       \ a stored block whose length is not checked
6 CONSTANT INFL-R-CODES        \ code lengths that make no prefix code
7 CONSTANT INFL-R-SYMBOL       \ bits that are no symbol, or a symbol not used
8 CONSTANT INFL-R-DISTANCE     \ a distance before the stream's start
9 CONSTANT INFL-R-SUM          \ a sum that does not match the data
10 CONSTANT INFL-R-LENGTH      \ a gzip length that does not match the data

\ =====================================================================
\  The record
\ =====================================================================
\   +0    phase                 +8    wrapper
\   +16   status                +24   reason
\   +32   bit buffer            +40   bits in it
\   +48   window address        +56   window size - 1
\   +64   bytes produced        +72   running sum
\   +80   last block?           +88   bytes left of a stored block or a field
\   +96   copy length left      +104  copy distance
\   +112  literal/length codes  +120  distance codes
\   +128  code-length codes     +136  lengths read
\   +144  gzip flags            +152  header bytes kept
\   +160  header CRC            +168  bytes kept (16)
\   +184  code lengths (320)
\   +504  code-length code lengths (24)
\   +528  literal/length table (512 entries of 16 bits)
\   +1552 distance table (256)
\   +2064 code-length table (128)
\   +2320 literal/length counts (16)      +2352 their symbols (288)
\   +2928 distance counts (16)            +2960 their symbols (32)

: _IF.PHASE    ( r -- a )         ;
: _IF.WRAPPER  ( r -- a )    8 + ;
: _IF.STATUS   ( r -- a )   16 + ;
: _IF.REASON   ( r -- a )   24 + ;
: _IF.BB       ( r -- a )   32 + ;
: _IF.BC       ( r -- a )   40 + ;
: _IF.WIN      ( r -- a )   48 + ;
: _IF.MASK     ( r -- a )   56 + ;
: _IF.TOTAL    ( r -- a )   64 + ;
: _IF.SUM      ( r -- a )   72 + ;
: _IF.FINAL    ( r -- a )   80 + ;
: _IF.REMAIN   ( r -- a )   88 + ;
: _IF.COPY-LEN ( r -- a )   96 + ;
: _IF.COPY-DIST ( r -- a ) 104 + ;
: _IF.HLIT     ( r -- a )  112 + ;
: _IF.HDIST    ( r -- a )  120 + ;
: _IF.HCLEN    ( r -- a )  128 + ;
: _IF.NLENS    ( r -- a )  136 + ;
: _IF.GZFLAGS  ( r -- a )  144 + ;
: _IF.KEPT-N   ( r -- a )  152 + ;
: _IF.HCRC     ( r -- a )  160 + ;
: _IF.KEPT     ( r -- a )  168 + ;
: _IF.LENS     ( r -- a )  184 + ;
: _IF.CLLENS   ( r -- a )  504 + ;
: _IF.LIT      ( r -- a )  528 + ;
: _IF.DIST     ( r -- a ) 1552 + ;
: _IF.CL       ( r -- a ) 2064 + ;
: _IF.LCOUNT   ( r -- a ) 2320 + ;
: _IF.LSYMS    ( r -- a ) 2352 + ;
: _IF.DCOUNT   ( r -- a ) 2928 + ;
: _IF.DSYMS    ( r -- a ) 2960 + ;
3024 CONSTANT INFL-SIZE

\ The window size less one when the output is the window: larger than
\ any stream, so the window never wraps or fills.
1 62 LSHIFT 1- CONSTANT _IF-NO-WINDOW

9 CONSTANT _IF-LIT-ROOT
8 CONSTANT _IF-DIST-ROOT
7 CONSTANT _IF-CL-ROOT
\ A table entry for a code longer than its table's root.
0xFFF0 CONSTANT _IF-LONG

\ Phases.
0  CONSTANT _IF-P-ZHEAD
1  CONSTANT _IF-P-GHEAD
2  CONSTANT _IF-P-GXLEN
3  CONSTANT _IF-P-GEXTRA
4  CONSTANT _IF-P-GNAME
5  CONSTANT _IF-P-GCOMMENT
6  CONSTANT _IF-P-GHCRC
7  CONSTANT _IF-P-BLOCK
8  CONSTANT _IF-P-STORED-LEN
9  CONSTANT _IF-P-STORED
10 CONSTANT _IF-P-DYN-HEAD
11 CONSTANT _IF-P-DYN-CL
12 CONSTANT _IF-P-DYN-LENS
13 CONSTANT _IF-P-CODES
14 CONSTANT _IF-P-TRAILER
15 CONSTANT _IF-P-END

\ Length and distance bases and extra bits (RFC 1951 section 3.2.5).
CREATE _IF-LBASE
  3 , 4 , 5 , 6 , 7 , 8 , 9 , 10 , 11 , 13 , 15 , 17 , 19 ,
  23 , 27 , 31 , 35 , 43 , 51 , 59 , 67 , 83 , 99 , 115 ,
  131 , 163 , 195 , 227 , 258 ,
CREATE _IF-LEXT
  0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 1 C, 1 C, 1 C, 1 C, 2 C, 2 C,
  2 C, 2 C, 3 C, 3 C, 3 C, 3 C, 4 C, 4 C, 4 C, 4 C, 5 C, 5 C, 5 C, 5 C, 0 C,
CREATE _IF-DBASE
  1 , 2 , 3 , 4 , 5 , 7 , 9 , 13 , 17 , 25 , 33 , 49 , 65 ,
  97 , 129 , 193 , 257 , 385 , 513 , 769 , 1025 , 1537 , 2049 ,
  3073 , 4097 , 6145 , 8193 , 12289 , 16385 , 24577 ,
CREATE _IF-DEXT
  0 C, 0 C, 0 C, 0 C, 1 C, 1 C, 2 C, 2 C, 3 C, 3 C, 4 C, 4 C, 5 C, 5 C,
  6 C, 6 C, 7 C, 7 C, 8 C, 8 C, 9 C, 9 C, 10 C, 10 C, 11 C, 11 C, 12 C,
  12 C, 13 C, 13 C,
\ The order code-length code lengths arrive in.
CREATE _IF-CLORDER
  16 C, 17 C, 18 C, 0 C, 8 C, 7 C, 9 C, 6 C, 10 C, 5 C, 11 C, 4 C, 12 C,
  3 C, 13 C, 2 C, 14 C, 1 C, 15 C,

\ =====================================================================
\  A feed's working state
\ =====================================================================

VARIABLE _IF-R         \ the record
VARIABLE _IF-BB        \ bit buffer: the next bit is bit 0
VARIABLE _IF-BC        \ bits in it
VARIABLE _IF-IP        \ the next input byte
VARIABLE _IF-IL        \ input bytes left
VARIABLE _IF-PULLED    \ bytes taken from this feed's input
VARIABLE _IF-OP        \ where the next output byte goes
VARIABLE _IF-OR        \ output bytes that may still be produced
VARIABLE _IF-WIN       \ window address
VARIABLE _IF-MASK      \ window size - 1
VARIABLE _IF-TOTAL     \ bytes produced
VARIABLE _IF-PEND      \ bytes in the window not yet in the output
VARIABLE _IF-SUM       \ running sum of the output
VARIABLE _IF-IN0       \ where this feed's input began
VARIABLE _IF-OUT0      \ where this feed's output began

\ =====================================================================
\  Bits and bytes
\ =====================================================================

\ Take input bytes into the bit buffer while it has room for one.
: _IF-REFILL  ( -- )
    BEGIN _IF-BC @ 57 < _IF-IL @ 0> AND WHILE
        _IF-IP @ C@ _IF-BC @ LSHIFT _IF-BB @ OR _IF-BB !
        8 _IF-BC +!  1 _IF-IP +!  -1 _IF-IL +!  1 _IF-PULLED +!
    REPEAT ;

\ N bits from bit OFF of the buffer, the first in bit 0.
: _IF-BITS  ( off n -- value )
    1 SWAP LSHIFT 1- SWAP _IF-BB @ SWAP RSHIFT AND ;

: _IF-DROP  ( n -- )
    DUP _IF-BB @ SWAP RSHIFT _IF-BB !  NEGATE _IF-BC +! ;

\ Drop to the next byte boundary.
: _IF-ALIGN  ( -- )  _IF-BC @ 7 AND _IF-DROP ;

\ The next whole byte, from the bit buffer after any whole bytes there,
\ then from the input; only at a byte boundary.
: _IF-BYTE?  ( -- byte true | false )
    _IF-BC @ 8 < 0= IF _IF-BB @ 255 AND 8 _IF-DROP -1 EXIT THEN
    _IF-IL @ 0= IF 0 EXIT THEN
    _IF-IP @ C@  1 _IF-IP +!  -1 _IF-IL +!  1 _IF-PULLED +!  -1 ;

\ Give back to the input the whole bytes at the top of the bit buffer
\ that this feed took, keeping the bits of a byte partly used.
: _IF-GIVE-BACK  ( -- )
    _IF-BC @ 3 RSHIFT _IF-PULLED @ MIN
    DUP NEGATE _IF-IP +!  DUP _IF-IL +!  DUP NEGATE _IF-PULLED +!
    3 LSHIFT NEGATE _IF-BC +!
    _IF-BB @ 1 _IF-BC @ LSHIFT 1- AND _IF-BB ! ;

\ =====================================================================
\  Output through the window
\ =====================================================================

: _IF-SIZE  ( -- size )  _IF-MASK @ 1+ ;

: _IF-SUM+  ( a u -- )
    _IF-R @ _IF.WRAPPER @
    DUP INFL-W-ZLIB = IF DROP _IF-SUM @ -ROT ADLER32-UPDATE _IF-SUM ! EXIT THEN
    INFL-W-GZIP = IF _IF-SUM @ -ROT CRC32-UPDATE _IF-SUM ! EXIT THEN
    2DROP ;

\ Copy U bytes of the window from position P to the output.  When the
\ output is the window they are there already.
: _IF-OUT  ( p u -- )
    DUP 0= IF 2DROP EXIT THEN
    SWAP _IF-WIN @ + _IF-OP @ ROT DUP >R
    2 PICK 2 PICK <> IF MOVE ELSE DROP 2DROP THEN
    _IF-OP @ R@ _IF-SUM+  R> _IF-OP +! ;

\ Give the output every byte the window holds for it.
: _IF-FLUSH  ( -- )
    _IF-PEND @ 0= IF EXIT THEN
    _IF-TOTAL @ _IF-PEND @ - _IF-MASK @ AND           ( start )
    DUP _IF-SIZE SWAP - _IF-PEND @ MIN                 ( start n1 )
    2DUP _IF-OUT
    _IF-PEND @ SWAP - 0 SWAP _IF-OUT DROP
    0 _IF-PEND ! ;

\ Put one byte into the window.
: _IF-PUT  ( byte -- )
    _IF-PEND @ _IF-SIZE = IF _IF-FLUSH THEN
    _IF-WIN @ _IF-TOTAL @ _IF-MASK @ AND + C!
    1 _IF-TOTAL +!  1 _IF-PEND +!  -1 _IF-OR +! ;

\ Copy N bytes within the window, from DIST back, where N leaves room
\ for every byte not yet in the output.  CMOVE copies forward a byte at a
\ time, so a run shorter than its distance repeats as deflate means.
: _IF-RING-COPY  ( n dist -- )
    _IF-TOTAL @ SWAP - _IF-MASK @ AND                  ( n s )
    _IF-TOTAL @ _IF-MASK @ AND                         ( n s d )
    ROT DUP _IF-TOTAL +!  DUP _IF-PEND +!  DUP NEGATE _IF-OR +!
    BEGIN DUP WHILE                                    ( s d n )
        DUP _IF-SIZE 4 PICK - MIN  _IF-SIZE 3 PICK - MIN   ( s d n k )
        3 PICK _IF-WIN @ + 3 PICK _IF-WIN @ + 2 PICK CMOVE
        >R  ROT R@ + _IF-MASK @ AND  ROT R@ + _IF-MASK @ AND
        ROT R> -
    REPEAT DROP 2DROP ;

\ Finish the copy the record holds, as far as the output allows.
\ True when the output filled first.
: _IF-COPY  ( -- full? )
    BEGIN _IF-R @ _IF.COPY-LEN @ WHILE
        _IF-OR @ 0= IF -1 EXIT THEN
        _IF-PEND @ _IF-SIZE = IF _IF-FLUSH THEN
        _IF-R @ _IF.COPY-LEN @ _IF-OR @ MIN _IF-SIZE _IF-PEND @ - MIN
        DUP NEGATE _IF-R @ _IF.COPY-LEN +!
        _IF-R @ _IF.COPY-DIST @ _IF-RING-COPY
    REPEAT 0 ;

\ =====================================================================
\  Prefix codes
\ =====================================================================

CREATE _IFB-OFFS 16 CELLS ALLOT
CREATE _IFB-NEXT 16 CELLS ALLOT
VARIABLE _IFB-LENS   VARIABLE _IFB-N      VARIABLE _IFB-TABLE
VARIABLE _IFB-ROOT   VARIABLE _IFB-COUNTS VARIABLE _IFB-SYMS
VARIABLE _IFB-CODES  VARIABLE _IFB-MAX

: _IFB-COUNT@  ( len -- n )  2* _IFB-COUNTS @ + W@ ;

\ The LEN bits of CODE in the order they are read.
: _IF-REVERSE  ( code len -- r )
    0 SWAP 0 ?DO 2* OVER 1 AND OR SWAP 1 RSHIFT SWAP LOOP NIP ;

\ Count the code lengths and check they make a prefix code: none
\ over-subscribed, and incomplete only as one code of one bit, which is
\ never the code-length code.
: _IFB-COUNT?  ( -- ok? )
    _IFB-COUNTS @ 32 0 FILL  0 _IFB-MAX !
    _IFB-N @ 0 ?DO
        _IFB-LENS @ I + C@ ?DUP IF
            DUP _IFB-MAX @ MAX _IFB-MAX !
            2* _IFB-COUNTS @ + DUP W@ 1+ SWAP W!
        THEN
    LOOP
    _IFB-MAX @ 0= IF -1 EXIT THEN
    1 16 1 DO 2* I _IFB-COUNT@ - DUP 0< IF DROP 0 UNLOOP EXIT THEN LOOP
    DUP 0> IF DROP _IFB-CODES @ 0= _IFB-MAX @ 1 = AND EXIT THEN
    DROP -1 ;

\ Symbols in code order, for codes read a bit at a time.
: _IFB-SORT  ( -- )
    0 1 BEGIN DUP 16 < WHILE
        2DUP CELLS _IFB-OFFS + !  TUCK _IFB-COUNT@ + SWAP 1+
    REPEAT 2DROP
    _IFB-N @ 0 ?DO
        _IFB-LENS @ I + C@ ?DUP IF
            CELLS _IFB-OFFS + DUP @ 2* _IFB-SYMS @ + I SWAP W!
            1 SWAP +!
        THEN
    LOOP ;

\ The first code of each length.
: _IFB-FIRSTS  ( -- )
    0 16 1 DO
        I 1- ?DUP IF _IFB-COUNT@ ELSE 0 THEN + 2*
        DUP I CELLS _IFB-NEXT + !
    LOOP DROP ;

\ Fill the table: each code of at most ROOT bits fills every entry its
\ bits begin, and the first ROOT bits of a longer code mark it long.
: _IFB-FILL  ( -- )
    _IFB-TABLE @ 1 _IFB-ROOT @ LSHIFT 2* 0 FILL
    _IFB-N @ 0 ?DO
        _IFB-LENS @ I + C@ ?DUP IF                      ( len )
            DUP CELLS _IFB-NEXT + DUP @ SWAP 1 SWAP +!  ( len code )
            OVER _IFB-ROOT @ > IF
                OVER _IFB-ROOT @ - RSHIFT _IFB-ROOT @ _IF-REVERSE
                2* _IFB-TABLE @ + _IF-LONG SWAP W!  DROP
            ELSE
                \ KDOS's +LOOP does not stop on stepping past its limit.
                OVER _IF-REVERSE                          ( len r )
                I 4 LSHIFT 2 PICK OR                      ( len r entry )
                ROT 1 SWAP LSHIFT ROT                     ( entry step r )
                BEGIN DUP 1 _IFB-ROOT @ LSHIFT < WHILE
                    2 PICK OVER 2* _IFB-TABLE @ + W!  OVER +
                REPEAT
                DROP 2DROP
            THEN
        THEN
    LOOP ;

\ Build a code from N lengths at LENS into TABLE, ROOT bits, with COUNTS
\ and SYMS for longer codes.  CODES? for the code-length code.
: _IF-BUILD  ( lens n table root counts syms codes? -- ok? )
    _IFB-CODES ! _IFB-SYMS ! _IFB-COUNTS ! _IFB-ROOT ! _IFB-TABLE !
    _IFB-N ! _IFB-LENS !
    _IFB-COUNT? 0= IF 0 EXIT THEN
    _IFB-SORT _IFB-FIRSTS _IFB-FILL -1 ;

\ A code's symbol at bit OFF of the buffer: SYM and its length, or -1 0
\ when the buffer holds too few bits, or -2 0 when the bits are no code.
VARIABLE _IFD-TABLE  VARIABLE _IFD-ROOT  VARIABLE _IFD-COUNTS  VARIABLE _IFD-SYMS
VARIABLE _IFS-CODE   VARIABLE _IFS-FIRST VARIABLE _IFS-INDEX

\ A code longer than its table's root, a bit at a time.
: _IF-SLOW  ( off -- sym len | -1 0 | -2 0 )
    0 _IFS-CODE !  0 _IFS-FIRST !  0 _IFS-INDEX !
    16 1 DO
        DUP I + _IF-BC @ > IF DROP -1 0 UNLOOP EXIT THEN
        DUP I + 1- 1 _IF-BITS _IFS-CODE @ OR _IFS-CODE !
        I 2* _IFD-COUNTS @ + W@                           ( off count )
        _IFS-CODE @ _IFS-FIRST @ - OVER U< IF
            2DROP
            _IFS-CODE @ _IFS-FIRST @ - _IFS-INDEX @ + 2* _IFD-SYMS @ + W@
            I UNLOOP EXIT
        THEN
        DUP _IFS-INDEX +!  _IFS-FIRST @ + 2* _IFS-FIRST !
        _IFS-CODE @ 2* _IFS-CODE !
    LOOP
    DROP -2 0 ;

: _IF-DECODE  ( off -- sym len | -1 0 | -2 0 )
    DUP _IFD-ROOT @ _IF-BITS 2* _IFD-TABLE @ + W@     ( off entry )
    DUP _IF-LONG = IF DROP _IF-SLOW EXIT THEN
    DUP 15 AND ?DUP IF                                 ( off entry len )
        ROT OVER + _IF-BC @ > IF 2DROP -1 0 EXIT THEN
        SWAP 4 RSHIFT SWAP EXIT
    THEN
    DROP _IFD-ROOT @ + _IF-BC @ > IF -1 0 ELSE -2 0 THEN ;

: _IF-LIT-SYM  ( off -- sym len | -1 0 | -2 0 )
    _IF-R @ DUP _IF.LIT _IFD-TABLE !  DUP _IF.LCOUNT _IFD-COUNTS !
    _IF.LSYMS _IFD-SYMS !  _IF-LIT-ROOT _IFD-ROOT !  _IF-DECODE ;

: _IF-DIST-SYM  ( off -- sym len | -1 0 | -2 0 )
    _IF-R @ DUP _IF.DIST _IFD-TABLE !  DUP _IF.DCOUNT _IFD-COUNTS !
    _IF.DSYMS _IFD-SYMS !  _IF-DIST-ROOT _IFD-ROOT !  _IF-DECODE ;

\ The code-length code is at most seven bits, its table's root.
: _IF-CL-SYM  ( off -- sym len | -1 0 | -2 0 )
    _IF-R @ _IF.CL _IFD-TABLE !  _IF-CL-ROOT _IFD-ROOT !  _IF-DECODE ;

\ =====================================================================
\  The phases
\ =====================================================================
\ Each phase word returns -1 to go on, or the status to return.

: _IF-PHASE!  ( phase -- )  _IF-R @ _IF.PHASE ! ;

: _IF-BAD  ( reason -- status )
    _IF-R @ _IF.REASON !  INFL-S-BAD ;

\ Keep header or trailer bytes until N are kept: true once they are.
: _IF-KEEP?  ( n -- all? )
    BEGIN DUP _IF-R @ _IF.KEPT-N @ > WHILE
        _IF-BYTE? 0= IF DROP 0 EXIT THEN
        _IF-R @ DUP _IF.KEPT SWAP _IF.KEPT-N @ + C!
        1 _IF-R @ _IF.KEPT-N +!
    REPEAT DROP -1 ;

: _IF-KEPT@  ( i -- byte )  _IF-R @ _IF.KEPT + C@ ;
: _IF-KEPT-CLEAR  ( -- )  0 _IF-R @ _IF.KEPT-N ! ;

\ The header CRC continued over N kept bytes.
: _IF-HCRC+  ( n -- )
    >R _IF-R @ _IF.HCRC @ _IF-R @ _IF.KEPT R> CRC32-UPDATE
    _IF-R @ _IF.HCRC ! ;

: _IF-ZHEAD  ( -- status|-1 )
    2 _IF-KEEP? 0= IF INFL-S-MORE EXIT THEN
    0 _IF-KEPT@ 8 LSHIFT 1 _IF-KEPT@ OR 31 MOD IF INFL-R-HEADER _IF-BAD EXIT THEN
    0 _IF-KEPT@ 15 AND 8 <> IF INFL-R-HEADER _IF-BAD EXIT THEN
    0 _IF-KEPT@ 4 RSHIFT DUP 7 > IF DROP INFL-R-HEADER _IF-BAD EXIT THEN
    256 SWAP LSHIFT _IF-SIZE > IF INFL-R-WINDOW _IF-BAD EXIT THEN
    1 _IF-KEPT@ 32 AND IF INFL-R-DICTIONARY _IF-BAD EXIT THEN
    _IF-KEPT-CLEAR  _IF-P-BLOCK _IF-PHASE! -1 ;

\ After the fixed part of a gzip header: its optional fields in order.
: _IF-GNEXT  ( -- )
    _IF-R @ _IF.GZFLAGS @
    DUP 4 AND IF DROP _IF-P-GXLEN _IF-PHASE! EXIT THEN
    DUP 8 AND IF DROP _IF-P-GNAME _IF-PHASE! EXIT THEN
    DUP 16 AND IF DROP _IF-P-GCOMMENT _IF-PHASE! EXIT THEN
    2 AND IF _IF-P-GHCRC _IF-PHASE! EXIT THEN
    _IF-P-BLOCK _IF-PHASE! ;

: _IF-GHEAD  ( -- status|-1 )
    10 _IF-KEEP? 0= IF INFL-S-MORE EXIT THEN
    0 _IF-KEPT@ 31 <> 1 _IF-KEPT@ 139 <> OR 2 _IF-KEPT@ 8 <> OR
    3 _IF-KEPT@ 0xE0 AND OR IF INFL-R-HEADER _IF-BAD EXIT THEN
    3 _IF-KEPT@ _IF-R @ _IF.GZFLAGS !
    10 _IF-HCRC+  _IF-KEPT-CLEAR  _IF-GNEXT -1 ;

: _IF-GXLEN  ( -- status|-1 )
    2 _IF-KEEP? 0= IF INFL-S-MORE EXIT THEN
    2 _IF-HCRC+
    0 _IF-KEPT@ 1 _IF-KEPT@ 8 LSHIFT OR _IF-R @ _IF.REMAIN !
    _IF-KEPT-CLEAR  _IF-P-GEXTRA _IF-PHASE! -1 ;

\ Clear FLAG among the gzip flags still to read.
: _IF-GFLAG-CLEAR  ( flag -- )
    INVERT _IF-R @ _IF.GZFLAGS DUP @ ROT AND SWAP ! ;

: _IF-GEXTRA  ( -- status|-1 )
    BEGIN _IF-R @ _IF.REMAIN @ WHILE
        1 _IF-KEEP? 0= IF INFL-S-MORE EXIT THEN
        1 _IF-HCRC+  _IF-KEPT-CLEAR  -1 _IF-R @ _IF.REMAIN +!
    REPEAT
    4 _IF-GFLAG-CLEAR  _IF-GNEXT -1 ;

\ Skip a gzip header's text to its zero byte, then clear FLAG.
: _IF-GTEXT  ( flag -- status|-1 )
    BEGIN
        1 _IF-KEEP? 0= IF DROP INFL-S-MORE EXIT THEN
        1 _IF-HCRC+  0 _IF-KEPT@  _IF-KEPT-CLEAR  0=
    UNTIL
    _IF-GFLAG-CLEAR  _IF-GNEXT -1 ;

: _IF-GHCRC  ( -- status|-1 )
    2 _IF-KEEP? 0= IF INFL-S-MORE EXIT THEN
    0 _IF-KEPT@ 1 _IF-KEPT@ 8 LSHIFT OR
    _IF-R @ _IF.HCRC @ 0xFFFF AND <> IF INFL-R-HEADER _IF-BAD EXIT THEN
    _IF-KEPT-CLEAR  _IF-P-BLOCK _IF-PHASE! -1 ;

\ The fixed codes (RFC 1951 section 3.2.6).  The distance code holds all
\ 32 five-bit codes, two of them unused symbols, so it is complete.
: _IF-FIXED  ( -- )
    _IF-R @ _IF.LENS
    DUP 144 8 FILL  DUP 144 + 112 9 FILL  DUP 256 + 24 7 FILL
    DUP 280 + 8 8 FILL  288 + 32 5 FILL
    _IF-R @ _IF.LENS 288 _IF-R @ _IF.LIT _IF-LIT-ROOT
    _IF-R @ _IF.LCOUNT _IF-R @ _IF.LSYMS 0 _IF-BUILD DROP
    _IF-R @ _IF.LENS 288 + 32 _IF-R @ _IF.DIST _IF-DIST-ROOT
    _IF-R @ _IF.DCOUNT _IF-R @ _IF.DSYMS 0 _IF-BUILD DROP ;

: _IF-BLOCK  ( -- status|-1 )
    _IF-R @ _IF.FINAL @ IF _IF-P-TRAILER _IF-PHASE! -1 EXIT THEN
    _IF-REFILL
    _IF-BC @ 3 < IF INFL-S-MORE EXIT THEN
    0 1 _IF-BITS _IF-R @ _IF.FINAL !
    1 2 _IF-BITS  3 _IF-DROP
    DUP 0= IF DROP _IF-KEPT-CLEAR  _IF-P-STORED-LEN _IF-PHASE! -1 EXIT THEN
    DUP 1 = IF DROP _IF-FIXED _IF-P-CODES _IF-PHASE! -1 EXIT THEN
    2 = IF _IF-P-DYN-HEAD _IF-PHASE! -1 EXIT THEN
    INFL-R-BLOCK _IF-BAD ;

: _IF-STORED-LEN  ( -- status|-1 )
    _IF-ALIGN
    4 _IF-KEEP? 0= IF INFL-S-MORE EXIT THEN
    0 _IF-KEPT@ 1 _IF-KEPT@ 8 LSHIFT OR
    2 _IF-KEPT@ 3 _IF-KEPT@ 8 LSHIFT OR
    OVER XOR 0xFFFF <> IF DROP INFL-R-STORED _IF-BAD EXIT THEN
    _IF-R @ _IF.REMAIN !  _IF-KEPT-CLEAR
    _IF-P-STORED _IF-PHASE! -1 ;

\ Copy a stored block's bytes: those in the bit buffer one at a time,
\ then the input's in runs.
: _IF-STORED  ( -- status|-1 )
    BEGIN _IF-R @ _IF.REMAIN @ WHILE
        _IF-OR @ 0= IF INFL-S-FULL EXIT THEN
        _IF-PEND @ _IF-SIZE = IF _IF-FLUSH THEN
        _IF-BC @ 8 < 0= IF
            _IF-BB @ 255 AND 8 _IF-DROP _IF-PUT  -1 _IF-R @ _IF.REMAIN +!
        ELSE
            _IF-IL @ 0= IF INFL-S-MORE EXIT THEN
            _IF-R @ _IF.REMAIN @ _IF-OR @ MIN _IF-IL @ MIN
            _IF-SIZE _IF-PEND @ - MIN
            _IF-SIZE _IF-TOTAL @ _IF-MASK @ AND - MIN       ( n )
            _IF-IP @ _IF-WIN @ _IF-TOTAL @ _IF-MASK @ AND + 2 PICK MOVE
            DUP _IF-IP +!  DUP NEGATE _IF-IL +!  DUP _IF-PULLED +!
            DUP _IF-TOTAL +!  DUP _IF-PEND +!  DUP NEGATE _IF-OR +!
            NEGATE _IF-R @ _IF.REMAIN +!
        THEN
    REPEAT
    _IF-P-BLOCK _IF-PHASE! -1 ;

: _IF-DYN-HEAD  ( -- status|-1 )
    _IF-REFILL
    _IF-BC @ 14 < IF INFL-S-MORE EXIT THEN
    0 5 _IF-BITS 257 + _IF-R @ _IF.HLIT !
    5 5 _IF-BITS 1+ _IF-R @ _IF.HDIST !
    10 4 _IF-BITS 4 + _IF-R @ _IF.HCLEN !
    14 _IF-DROP
    _IF-R @ _IF.HLIT @ 286 > _IF-R @ _IF.HDIST @ 30 > OR IF
        INFL-R-CODES _IF-BAD EXIT
    THEN
    _IF-R @ _IF.CLLENS 19 0 FILL  0 _IF-R @ _IF.NLENS !
    _IF-P-DYN-CL _IF-PHASE! -1 ;

\ The code-length code's lengths, then the code, whose counts and
\ symbols use the literal code's arrays until that code is built.
: _IF-DYN-CL  ( -- status|-1 )
    BEGIN _IF-R @ _IF.NLENS @ _IF-R @ _IF.HCLEN @ < WHILE
        _IF-REFILL
        _IF-BC @ 3 < IF INFL-S-MORE EXIT THEN
        0 3 _IF-BITS 3 _IF-DROP
        _IF-R @ _IF.NLENS @ _IF-CLORDER + C@ _IF-R @ _IF.CLLENS + C!
        1 _IF-R @ _IF.NLENS +!
    REPEAT
    _IF-R @ _IF.CLLENS 19 _IF-R @ _IF.CL _IF-CL-ROOT
    _IF-R @ _IF.LCOUNT _IF-R @ _IF.LSYMS -1 _IF-BUILD
    0= IF INFL-R-CODES _IF-BAD EXIT THEN
    0 _IF-R @ _IF.NLENS !  _IF-P-DYN-LENS _IF-PHASE! -1 ;

\ After the code lengths: the two codes, which must give the end of the
\ block a code.
: _IF-DYN-CODES  ( -- status|-1 )
    _IF-R @ _IF.LENS 256 + C@ 0= IF INFL-R-CODES _IF-BAD EXIT THEN
    _IF-R @ _IF.LENS _IF-R @ _IF.HLIT @ _IF-R @ _IF.LIT _IF-LIT-ROOT
    _IF-R @ _IF.LCOUNT _IF-R @ _IF.LSYMS 0 _IF-BUILD
    0= IF INFL-R-CODES _IF-BAD EXIT THEN
    _IF-R @ _IF.LENS _IF-R @ _IF.HLIT @ + _IF-R @ _IF.HDIST @
    _IF-R @ _IF.DIST _IF-DIST-ROOT _IF-R @ _IF.DCOUNT _IF-R @ _IF.DSYMS 0
    _IF-BUILD 0= IF INFL-R-CODES _IF-BAD EXIT THEN
    _IF-P-CODES _IF-PHASE! -1 ;

\ Put COUNT code lengths of VALUE, unless they run past the lengths due.
: _IF-LENS-PUT  ( value count -- ok? )
    DUP _IF-R @ _IF.NLENS @ +
    _IF-R @ DUP _IF.HLIT @ SWAP _IF.HDIST @ + > IF 2DROP 0 EXIT THEN
    _IF-R @ DUP _IF.LENS SWAP _IF.NLENS @ +              ( value count addr )
    OVER >R  SWAP ROT FILL
    R> _IF-R @ _IF.NLENS +! -1 ;

: _IF-DYN-LENS  ( -- status|-1 )
    BEGIN
        _IF-R @ _IF.NLENS @ _IF-R @ DUP _IF.HLIT @ SWAP _IF.HDIST @ + <
    WHILE
        _IF-REFILL
        0 _IF-CL-SYM                                   ( sym len )
        DUP 0= IF
            DROP -2 = IF INFL-R-CODES _IF-BAD ELSE INFL-S-MORE THEN EXIT
        THEN
        OVER 16 < IF
            _IF-DROP 1 _IF-LENS-PUT DROP
        ELSE
            OVER 16 = IF 2 3 ELSE OVER 17 = IF 3 3 ELSE 7 11 THEN THEN
            >R                                          ( sym len extra )
            2DUP + _IF-BC @ > IF R> DROP 2DROP DROP INFL-S-MORE EXIT THEN
            2DUP _IF-BITS R> + >R                       ( sym len extra )
            + _IF-DROP R>                               ( sym count )
            SWAP 16 = IF
                _IF-R @ _IF.NLENS @ 0= IF DROP INFL-R-CODES _IF-BAD EXIT THEN
                _IF-R @ DUP _IF.LENS SWAP _IF.NLENS @ + 1- C@ SWAP
            ELSE 0 SWAP THEN                            ( value count )
            _IF-LENS-PUT 0= IF INFL-R-CODES _IF-BAD EXIT THEN
        THEN
    REPEAT
    _IF-DYN-CODES ;

\ The rest of a length and distance pair, after its length symbol SYM of
\ LEN bits: all its bits are in the buffer, or nothing is used.
VARIABLE _IFL-OFF  VARIABLE _IFL-LEN
: _IF-PAIR  ( sym len -- status|-1 )
    _IFL-OFF !  257 -
    DUP 29 < 0= IF DROP INFL-R-SYMBOL _IF-BAD EXIT THEN          ( i )
    DUP _IF-LEXT + C@                                           ( i lext )
    _IFL-OFF @ OVER + _IF-BC @ > IF 2DROP INFL-S-MORE EXIT THEN
    _IFL-OFF @ OVER _IF-BITS                                    ( i lext x )
    ROT CELLS _IF-LBASE + @ + _IFL-LEN !  _IFL-OFF +!
    _IFL-OFF @ _IF-DIST-SYM                                     ( dsym dlen )
    DUP 0= IF DROP -2 = IF INFL-R-SYMBOL _IF-BAD ELSE INFL-S-MORE THEN EXIT THEN
    _IFL-OFF +!                                                 ( dsym )
    DUP 30 < 0= IF DROP INFL-R-SYMBOL _IF-BAD EXIT THEN
    DUP _IF-DEXT + C@                                           ( dsym dext )
    _IFL-OFF @ OVER + _IF-BC @ > IF 2DROP INFL-S-MORE EXIT THEN
    _IFL-OFF @ OVER _IF-BITS                                    ( dsym dext x )
    ROT CELLS _IF-DBASE + @ +  SWAP _IFL-OFF +!                   ( dist )
    DUP _IF-TOTAL @ > IF DROP INFL-R-DISTANCE _IF-BAD EXIT THEN
    DUP _IF-SIZE > IF DROP INFL-R-WINDOW _IF-BAD EXIT THEN
    _IFL-OFF @ _IF-DROP
    _IF-R @ _IF.COPY-DIST !  _IFL-LEN @ _IF-R @ _IF.COPY-LEN !  -1 ;

: _IF-CODES  ( -- status|-1 )
    BEGIN
        _IF-COPY IF INFL-S-FULL EXIT THEN
        _IF-REFILL
        0 _IF-LIT-SYM                                  ( sym len )
        DUP 0= IF
            DROP -2 = IF INFL-R-SYMBOL _IF-BAD ELSE INFL-S-MORE THEN EXIT
        THEN
        OVER 256 < IF
            _IF-OR @ 0= IF 2DROP INFL-S-FULL EXIT THEN
            _IF-DROP _IF-PUT
        ELSE OVER 256 = IF
            _IF-DROP DROP  _IF-P-BLOCK _IF-PHASE! -1 EXIT
        ELSE
            _IF-PAIR DUP -1 <> IF EXIT THEN DROP
        THEN THEN
    AGAIN ;

\ The 32-bit value of four kept bytes from I, least significant first.
: _IF-KEPT-LE  ( i -- u )
    DUP 3 + _IF-KEPT@ 8 LSHIFT  OVER 2 + _IF-KEPT@ OR 8 LSHIFT
    OVER 1+ _IF-KEPT@ OR 8 LSHIFT  SWAP _IF-KEPT@ OR ;

: _IF-TRAILER  ( -- status|-1 )
    _IF-ALIGN  _IF-FLUSH
    _IF-R @ _IF.WRAPPER @ DUP INFL-W-RAW = IF
        DROP _IF-P-END _IF-PHASE! INFL-S-DONE EXIT
    THEN
    INFL-W-ZLIB = IF
        4 _IF-KEEP? 0= IF INFL-S-MORE EXIT THEN
        0 _IF-KEPT@ 24 LSHIFT 1 _IF-KEPT@ 16 LSHIFT OR
        2 _IF-KEPT@ 8 LSHIFT OR 3 _IF-KEPT@ OR
        _IF-SUM @ <> IF INFL-R-SUM _IF-BAD EXIT THEN
    ELSE
        8 _IF-KEEP? 0= IF INFL-S-MORE EXIT THEN
        0 _IF-KEPT-LE _IF-SUM @ <> IF INFL-R-SUM _IF-BAD EXIT THEN
        4 _IF-KEPT-LE _IF-TOTAL @ 0xFFFFFFFF AND <> IF
            INFL-R-LENGTH _IF-BAD EXIT
        THEN
    THEN
    _IF-P-END _IF-PHASE! INFL-S-DONE ;

: _IF-STEP  ( -- status|-1 )
    _IF-R @ _IF.PHASE @ CASE
        _IF-P-ZHEAD      OF _IF-ZHEAD ENDOF
        _IF-P-GHEAD      OF _IF-GHEAD ENDOF
        _IF-P-GXLEN      OF _IF-GXLEN ENDOF
        _IF-P-GEXTRA     OF _IF-GEXTRA ENDOF
        _IF-P-GNAME      OF 8 _IF-GTEXT ENDOF
        _IF-P-GCOMMENT   OF 16 _IF-GTEXT ENDOF
        _IF-P-GHCRC      OF _IF-GHCRC ENDOF
        _IF-P-BLOCK      OF _IF-BLOCK ENDOF
        _IF-P-STORED-LEN OF _IF-STORED-LEN ENDOF
        _IF-P-STORED     OF _IF-STORED ENDOF
        _IF-P-DYN-HEAD   OF _IF-DYN-HEAD ENDOF
        _IF-P-DYN-CL     OF _IF-DYN-CL ENDOF
        _IF-P-DYN-LENS   OF _IF-DYN-LENS ENDOF
        _IF-P-CODES      OF _IF-CODES ENDOF
        _IF-P-TRAILER    OF _IF-TRAILER ENDOF
        INFL-S-DONE SWAP
    ENDCASE ;

\ =====================================================================
\  Public words
\ =====================================================================

\ INFL-INIT ( window-a window-u wrapper infl -- )
\   Start a stream of WRAPPER, with the window of WINDOW-U bytes at
\   WINDOW-A, a power of two from 256 to 32768, or with no window when
\   WINDOW-U is 0.  Any other window, or an unknown wrapper, leaves the
\   decoder damaged.
: INFL-INIT  ( window-a window-u wrapper infl -- )
    DUP INFL-SIZE 0 FILL  >R
    DUP R@ _IF.WRAPPER !
    DUP INFL-W-ZLIB = IF _IF-P-ZHEAD R@ _IF.PHASE !  ADLER32-INIT R@ _IF.SUM ! THEN
    DUP INFL-W-GZIP = IF _IF-P-GHEAD R@ _IF.PHASE ! THEN
    DUP INFL-W-RAW = IF _IF-P-BLOCK R@ _IF.PHASE ! THEN
    INFL-W-GZIP U> IF
        INFL-R-HEADER R@ _IF.REASON !  INFL-S-BAD R@ _IF.STATUS !
    THEN
    DUP 0= IF 2DROP _IF-NO-WINDOW R> _IF.MASK ! EXIT THEN
    DUP 256 < OVER 32768 > OR OVER DUP 1- AND OR IF
        INFL-R-WINDOW R@ _IF.REASON !  INFL-S-BAD R@ _IF.STATUS !
    THEN
    1- R@ _IF.MASK !  R> _IF.WIN ! ;

\ INFL-REASON@ ( infl -- reason )   Why the stream is damaged, or 0.
: INFL-REASON@  ( infl -- reason )  _IF.REASON @ ;

\ INFL-TOTAL@ ( infl -- bytes )   Bytes the stream has given so far.
: INFL-TOTAL@  ( infl -- bytes )  _IF.TOTAL @ ;

: _IF-LOAD  ( -- )
    0 _IF-PULLED !  0 _IF-PEND !
    _IF-R @ DUP _IF.BB @ _IF-BB !  DUP _IF.BC @ _IF-BC !
    DUP _IF.WIN @ _IF-WIN !  DUP _IF.MASK @ _IF-MASK !
    DUP _IF.TOTAL @ _IF-TOTAL !  _IF.SUM @ _IF-SUM ! ;

: _IF-SAVE  ( -- )
    _IF-R @ >R  _IF-BB @ R@ _IF.BB !  _IF-BC @ R@ _IF.BC !
    _IF-TOTAL @ R@ _IF.TOTAL !  _IF-SUM @ R> _IF.SUM ! ;

\ With no window, whether this feed's room begins right after the bytes
\ the stream has given.  Until it gives one, any room begins it.
: _IF-FOLLOWS?  ( -- flag )
    _IF-MASK @ _IF-NO-WINDOW <> IF -1 EXIT THEN
    _IF-TOTAL @ 0= IF _IF-OP @ DUP _IF-WIN ! _IF-R @ _IF.WIN ! -1 EXIT THEN
    _IF-WIN @ _IF-TOTAL @ + _IF-OP @ = ;

\ INFL-FEED ( in-a in-u out-a out-u infl -- in-used out-used status )
\   Decode from IN-U bytes at IN-A into OUT-U bytes of room at OUT-A.
: INFL-FEED  ( in-a in-u out-a out-u infl -- in-used out-used status )
    _IF-R !
    _IF-R @ _IF.STATUS @ ?DUP IF >R 2DROP 2DROP 0 0 R> EXIT THEN
    _IF-OR ! DUP _IF-OP ! _IF-OUT0 !  _IF-IL ! DUP _IF-IP ! _IF-IN0 !
    _IF-LOAD
    _IF-FOLLOWS? IF
        BEGIN _IF-STEP DUP -1 = WHILE DROP REPEAT    ( status )
    ELSE
        INFL-R-WINDOW _IF-BAD
    THEN
    _IF-FLUSH
    DUP INFL-S-FULL = OVER INFL-S-DONE = OR IF _IF-GIVE-BACK THEN
    DUP INFL-S-DONE = OVER INFL-S-BAD = OR IF DUP _IF-R @ _IF.STATUS ! THEN
    _IF-SAVE
    >R _IF-IP @ _IF-IN0 @ -  _IF-OP @ _IF-OUT0 @ -  R> ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _infl-guard

' INFL-FEED  CONSTANT _infl-feed-xt

: INFL-FEED  _infl-feed-xt _infl-guard WITH-GUARD ;
[THEN] [THEN]
