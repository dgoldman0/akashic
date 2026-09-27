\ =================================================================
\  text-row.f — one row of logical text on the cell grid
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TROW- / _TR-
\  Depends on: utf8.f, unicode-props.f, grapheme.f, bidi.f
\
\  Lays out one row of UTF-8 text as the shared text contract
\  (docs/rich-terminal/APT-1-TEXT.md Sections 3 to 9) describes:
\  characters (extended grapheme clusters) with their widths, one
\  bidi paragraph whose characters are reordered whole, mirrored
\  glyphs at odd levels, and Arabic letters in their joined forms.
\  The result says which character sits in which cells and maps
\  between logical positions and columns.
\
\  Rows of printable ASCII in an LTR or AUTO paragraph take a byte
\  fast path.  Rows with no R, AL, AN, RLE, RLO, RLI, or FSI scalar
\  skip bidi and joining entirely (Section 11).
\
\  Row object (TROW-SIZE bytes of caller storage):
\    TROW-INIT    ( row -- )
\    TROW-FREE    ( row -- )                  release its buffer
\    TROW-LAYOUT  ( addr u flags direction row -- ok? )
\        FLAGS: TROW-F-TAB keeps U+0009 as a blank one-cell character;
\        TROW-F-UNTRUSTED ignores explicit embeddings, overrides, and
\        isolates.  DIRECTION: BIDI-AUTO, BIDI-LTR, or BIDI-RTL.
\        False only when the buffer cannot grow to hold the row.
\    TROW-LENGTH  ( row -- n )     scalars in the logical row
\    TROW-WIDTH   ( row -- cells )
\    TROW-PARA    ( row -- level ) resolved paragraph level
\    TROW-CHARS   ( row -- n )     characters, including width 0
\    TROW-CHAR    ( j row -- rec ) j-th character in logical order
\    TROW-VISIBLE ( row -- n )     characters with width > 0
\    TROW-VCHAR   ( k row -- rec ) k-th visible character, left to right
\  Character record fields ( rec -- x ):
\    TROW.START TROW.BYTE TROW.CP0 TROW.COLUMN TROW.SCALARS TROW.BYTES
\    TROW.WIDTH TROW.LEVEL
\    CP0 is the displayed first scalar, after mirroring and joining;
\    COLUMN is counted from the row's left edge.
\  Mapping:
\    TROW-DISPLAY     ( rec buf row -- n )  display scalars, 32-bit each
\    TROW-AT-COLUMN   ( column row -- rec | 0 )
\    TROW-POSITION-AT ( column row -- offset )   Section 9.1
\    TROW-CARET       ( offset row -- rec | 0 )   Section 9.2
\    TROW-BYTE>OFFSET ( byte row -- offset )
\    TROW-OFFSET>BYTE ( offset row -- byte )
\
\  Layout keeps its scratch state in module variables and takes the
\  module guard in GUARDED builds.  The read words only touch the row.
\ =================================================================

PROVIDED akashic-text-row

REQUIRE utf8.f
REQUIRE unicode-props.f
REQUIRE grapheme.f
REQUIRE bidi.f

1 CONSTANT TROW-F-TAB
2 CONSTANT TROW-F-UNTRUSTED

\ =====================================================================
\  §1 — Row object and buffer
\ =====================================================================

 0 CONSTANT _TR-O-BUF       \ heap buffer, or 0
 8 CONSTANT _TR-O-CAP       \ source bytes the buffer is sized for
16 CONSTANT _TR-O-N         \ scalars
24 CONSTANT _TR-O-CHARS     \ characters
32 CONSTANT _TR-O-VIS       \ visible characters
40 CONSTANT _TR-O-WIDTH
48 CONSTANT _TR-O-PARA
56 CONSTANT _TR-O-BYTES     \ source bytes laid out
64 CONSTANT TROW-SIZE

32 CONSTANT _TR-REC         \ bytes per character record

: TROW-INIT  ( row -- )  TROW-SIZE 0 FILL ;

: TROW-FREE  ( row -- )
    DUP _TR-O-BUF + @ ?DUP IF FREE THEN
    TROW-INIT ;

\ Buffer layout for a capacity of C source bytes (so at most C scalars
\ and C characters): scalars and byte offsets (4 bytes each), bidi
\ classes (1), character records (32), visible levels (1), visible to
\ character map (4), visual order (4), then the bidi workspace.
: _TR-ALIGN  ( n -- n' )  7 + -8 AND ;

VARIABLE _TR-C
: _TR-SCALARS-OFF  ( -- u )  0 ;
: _TR-OFFSETS-OFF  ( -- u )  _TR-C @ 4 * ;
: _TR-CLASSES-OFF  ( -- u )  _TR-C @ 8 * ;
: _TR-RECS-OFF     ( -- u )  _TR-C @ 9 * _TR-ALIGN ;
: _TR-VLEVELS-OFF  ( -- u )  _TR-RECS-OFF _TR-C @ _TR-REC * + ;
: _TR-VMAP-OFF     ( -- u )  _TR-VLEVELS-OFF _TR-C @ + _TR-ALIGN ;
: _TR-ORDER-OFF    ( -- u )  _TR-VMAP-OFF _TR-C @ 4 * + ;
: _TR-WORK-OFF     ( -- u )  _TR-ORDER-OFF _TR-C @ 4 * + _TR-ALIGN ;
: _TR-BUFFER-BYTES ( -- u )  _TR-WORK-OFF _TR-C @ BIDI-WORK-BYTES + ;

\ The accessors below work on the row being laid out or read, named by
\ _TR-R, with _TR-C holding its capacity.
VARIABLE _TR-R
: _TR-SELECT  ( row -- )  DUP _TR-R ! _TR-O-CAP + @ _TR-C ! ;
: _TR-BASE    ( -- a )    _TR-R @ _TR-O-BUF + @ ;
: _TR-SCALAR@ ( i -- cp )    4 * _TR-BASE + L@ ;
: _TR-SCALAR! ( cp i -- )    4 * _TR-BASE + L! ;
: _TR-OFFSET@ ( i -- byte )  4 * _TR-OFFSETS-OFF + _TR-BASE + L@ ;
: _TR-OFFSET! ( byte i -- )  4 * _TR-OFFSETS-OFF + _TR-BASE + L! ;
: _TR-CLASSES ( -- a )       _TR-CLASSES-OFF _TR-BASE + ;
: _TR-RECORD  ( j -- rec )   _TR-REC * _TR-RECS-OFF + _TR-BASE + ;
: _TR-VLEVELS ( -- a )       _TR-VLEVELS-OFF _TR-BASE + ;
: _TR-VMAP@   ( v -- j )     4 * _TR-VMAP-OFF + _TR-BASE + L@ ;
: _TR-VMAP!   ( j v -- )     4 * _TR-VMAP-OFF + _TR-BASE + L! ;
: _TR-ORDER   ( -- a )       _TR-ORDER-OFF _TR-BASE + ;
: _TR-WORK    ( -- a )       _TR-WORK-OFF _TR-BASE + ;

\ Character record fields.
: TROW.START    ( rec -- n )   L@ ;
: TROW.BYTE     ( rec -- n )   4 + L@ ;
: TROW.CP0      ( rec -- cp )  8 + L@ ;
: TROW.COLUMN   ( rec -- n )   12 + L@ ;
: TROW.SCALARS  ( rec -- n )   16 + L@ ;
: TROW.BYTES    ( rec -- n )   20 + L@ ;
: TROW.WIDTH    ( rec -- n )   24 + C@ ;
: TROW.LEVEL    ( rec -- n )   25 + C@ ;

\ _TR-ENSURE ( u -- ok? )
\   Size the selected row's buffer for U source bytes.  It only grows,
\   so a row reused for similar text does not reallocate.
: _TR-ENSURE  ( u -- ok? )
    16 MAX
    DUP _TR-R @ _TR-O-CAP + @ <= _TR-R @ _TR-O-BUF + @ 0<> AND IF
        DROP _TR-R @ _TR-O-CAP + @ _TR-C ! -1 EXIT
    THEN
    DUP _TR-C ! _TR-BUFFER-BYTES ALLOCATE IF
        2DROP _TR-R @ _TR-O-CAP + @ _TR-C ! 0 EXIT
    THEN                                      ( u buffer )
    _TR-R @ _TR-O-BUF + @ ?DUP IF FREE THEN
    _TR-R @ _TR-O-BUF + !
    _TR-R @ _TR-O-CAP + !
    -1 ;

: TROW-LENGTH   ( row -- n )     _TR-O-N + @ ;
: TROW-WIDTH    ( row -- cells ) _TR-O-WIDTH + @ ;
: TROW-PARA     ( row -- level ) _TR-O-PARA + @ ;
: TROW-CHARS    ( row -- n )     _TR-O-CHARS + @ ;
: TROW-VISIBLE  ( row -- n )     _TR-O-VIS + @ ;
: TROW-CHAR     ( j row -- rec ) _TR-SELECT _TR-RECORD ;
: TROW-VCHAR    ( k row -- rec )
    _TR-SELECT 4 * _TR-ORDER + L@ _TR-RECORD ;

\ =====================================================================
\  §2 — Reading the text
\ =====================================================================

VARIABLE _TR-A
VARIABLE _TR-U
VARIABLE _TR-FLAGS
VARIABLE _TR-DIR
VARIABLE _TR-POS
VARIABLE _TR-I
VARIABLE _TR-J
VARIABLE _TR-TRIGGER
VARIABLE _TR-CP  VARIABLE _TR-PROPS  VARIABLE _TR-LEN
\ The character being read: its first scalar's properties, second scalar
\ and properties, and whether every scalar so far is default-ignorable.
VARIABLE _TR-P0  VARIABLE _TR-CP1  VARIABLE _TR-P1  VARIABLE _TR-IGN

CREATE _TR-DEC UTF8-DECODE-STATE-SIZE ALLOT
CREATE _TR-SEG GR-STATE-SIZE ALLOT

\ Bidi classes that can make any level odd (Section 11).
: _TR-TRIGGER?  ( class -- flag )
    DUP UP-BC-R = OVER UP-BC-AL = OR OVER UP-BC-AN = OR
    OVER UP-BC-RLE = OR OVER UP-BC-RLO = OR OVER UP-BC-RLI = OR
    SWAP UP-BC-FSI = OR ;

: _TR-FINISH-CHAR  ( -- )
    _TR-J @ 0< IF EXIT THEN
    _TR-P0 @ _TR-CP1 @ _TR-P1 @ _TR-J @ _TR-RECORD TROW.SCALARS _TR-IGN @
    GR-CHAR-WIDTH _TR-J @ _TR-RECORD 24 + C! ;

: _TR-NEW-CHAR  ( -- )
    _TR-FINISH-CHAR
    1 _TR-J +!
    _TR-J @ _TR-RECORD DUP _TR-REC 0 FILL
    _TR-I @ OVER L!
    _TR-POS @ OVER 4 + L!
    _TR-CP @ OVER 8 + L!
    1 OVER 16 + L!
    _TR-LEN @ SWAP 20 + L!
    _TR-PROPS @ _TR-P0 !
    -1 _TR-CP1 ! 0 _TR-P1 !
    _TR-PROPS @ UP-IGNORABLE? _TR-IGN ! ;

: _TR-EXTEND-CHAR  ( -- )
    _TR-J @ _TR-RECORD
    DUP 16 + DUP L@ 1+ SWAP L!
    20 + DUP L@ _TR-LEN @ + SWAP L!
    _TR-J @ _TR-RECORD TROW.SCALARS 2 = IF
        _TR-CP @ _TR-CP1 ! _TR-PROPS @ _TR-P1 !
    THEN
    _TR-PROPS @ UP-IGNORABLE? 0= IF 0 _TR-IGN ! THEN ;

: _TR-READ  ( -- )
    0 _TR-POS ! 0 _TR-I ! -1 _TR-J ! 0 _TR-TRIGGER !
    _TR-SEG GR-RESET
    BEGIN _TR-POS @ _TR-U @ < WHILE
        _TR-A @ _TR-POS @ + _TR-U @ _TR-POS @ -
        _TR-FLAGS @ TROW-F-TAB AND _TR-DEC GR-DECODE
        _TR-LEN ! _TR-PROPS ! _TR-CP !
        _TR-CP @ _TR-I @ _TR-SCALAR!
        _TR-POS @ _TR-I @ _TR-OFFSET!
        _TR-PROPS @ UP-BIDI
        _TR-FLAGS @ TROW-F-UNTRUSTED AND IF
            DUP UP-BC-LRE UP-BC-PDI 1+ WITHIN IF DROP UP-BC-BN THEN
        THEN
        DUP _TR-TRIGGER? IF -1 _TR-TRIGGER ! THEN
        _TR-CLASSES _TR-I @ + C!
        _TR-PROPS @ _TR-SEG GR-BREAK? _TR-J @ 0< OR IF
            _TR-NEW-CHAR
        ELSE
            _TR-EXTEND-CHAR
        THEN
        _TR-LEN @ _TR-POS +!
        1 _TR-I +!
    REPEAT
    _TR-FINISH-CHAR
    _TR-I @ _TR-R @ _TR-O-N + !
    _TR-J @ 1+ _TR-R @ _TR-O-CHARS + ! ;

\ =====================================================================
\  §3 — Levels, mirroring, and joining
\ =====================================================================

\ The level of character J: that of its first scalar that X9 keeps, or
\ the paragraph level when X9 removes them all.
: _TR-CHAR-LEVEL  ( j -- level )
    _TR-RECORD DUP TROW.START SWAP TROW.SCALARS OVER + SWAP ?DO
        _TR-WORK BIDI-LEVELS I + C@ DUP BIDI-REMOVED <> IF UNLOOP EXIT THEN
        DROP
    LOOP
    _TR-R @ _TR-O-PARA + @ ;

VARIABLE _TR-JT

: _TR-JOINING-TYPE  ( i -- type )  _TR-SCALAR@ UP-PROPS UP-JOINING ;

\ The joining type of the nearest scalar before (STEP -1) or after
\ (STEP 1) scalar I that is not transparent, or U at the paragraph edge.
: _TR-JOIN-NEIGHBOUR  ( i step -- type )
    >R
    BEGIN R@ + DUP 0< 0= OVER _TR-R @ _TR-O-N + @ < AND WHILE
        DUP _TR-JOINING-TYPE DUP UP-JT-T <> IF NIP R> DROP EXIT THEN
        DROP
    REPEAT
    DROP R> DROP UP-JT-U ;

\ _TR-FORM ( i -- form | -1 )  Section 8 for scalar I, or -1 when it
\   does not take a joining form.
: _TR-FORM  ( i -- form | -1 )
    DUP _TR-JOINING-TYPE _TR-JT !
    _TR-JT @ UP-JT-D = _TR-JT @ UP-JT-R = OR _TR-JT @ UP-JT-L = OR 0= IF
        DROP -1 EXIT
    THEN
    DUP -1 _TR-JOIN-NEIGHBOUR                 ( i prev )
    DUP UP-JT-D = OVER UP-JT-L = OR SWAP UP-JT-C = OR
    _TR-JT @ UP-JT-D = _TR-JT @ UP-JT-R = OR AND     ( i joins-prev )
    SWAP 1 _TR-JOIN-NEIGHBOUR                 ( joins-prev next )
    DUP UP-JT-D = OVER UP-JT-R = OR SWAP UP-JT-C = OR
    _TR-JT @ UP-JT-D = _TR-JT @ UP-JT-L = OR AND     ( joins-prev joins-next )
    2DUP AND IF 2DROP UP-FORM-MEDIAL EXIT THEN
    IF DROP UP-FORM-INITIAL EXIT THEN
    IF UP-FORM-FINAL ELSE UP-FORM-ISOLATED THEN ;

: _TR-SHAPE  ( -- )
    _TR-R @ _TR-O-CHARS + @ 0 ?DO
        I _TR-RECORD
        _TR-TRIGGER @ IF I _TR-CHAR-LEVEL ELSE 0 THEN OVER 25 + C!
        DUP TROW.LEVEL 1 AND IF
            DUP TROW.CP0 DUP UP-PROPS UP-MIRRORED? IF
                UP-MIRROR OVER 8 + L!
            ELSE DROP THEN
        THEN
        _TR-TRIGGER @ IF
            DUP TROW.CP0 UP-PROPS UP-ARABIC-FORMS? IF
                DUP TROW.START _TR-FORM DUP 0< IF
                    DROP
                ELSE
                    OVER TROW.CP0 SWAP UP-ARABIC-FORM ?DUP IF OVER 8 + L! THEN
                THEN
            THEN
        THEN
        DROP
    LOOP ;

\ =====================================================================
\  §4 — Visual order and columns
\ =====================================================================

: _TR-ORDER-VISIBLE  ( -- )
    0 _TR-R @ _TR-O-VIS + !
    _TR-R @ _TR-O-CHARS + @ 0 ?DO
        I _TR-RECORD TROW.WIDTH IF
            I _TR-R @ _TR-O-VIS + @ _TR-VMAP!
            I _TR-RECORD TROW.LEVEL _TR-VLEVELS _TR-R @ _TR-O-VIS + @ + C!
            1 _TR-R @ _TR-O-VIS + +!
        THEN
    LOOP
    _TR-TRIGGER @ IF
        _TR-VLEVELS _TR-R @ _TR-O-VIS + @ _TR-ORDER BIDI-REORDER DROP
    ELSE
        _TR-R @ _TR-O-VIS + @ 0 ?DO I I 4 * _TR-ORDER + L! LOOP
    THEN
    \ The order now names visible indexes; turn them into characters and
    \ give each its column, left to right.
    0 _TR-R @ _TR-O-VIS + @ 0 ?DO
        I 4 * _TR-ORDER + DUP L@ _TR-VMAP@ DUP ROT L!   ( column j )
        _TR-RECORD 2DUP 12 + L! TROW.WIDTH +
    LOOP
    _TR-R @ _TR-O-WIDTH + ! ;

\ Printable ASCII, not forced RTL: one character per byte, in order.
VARIABLE _TR-PS  VARIABLE _TR-PO  VARIABLE _TR-PR  VARIABLE _TR-PD

: _TR-ASCII?  ( -- flag )
    _TR-DIR @ BIDI-RTL = IF 0 EXIT THEN
    _TR-A @ _TR-U @
    BEGIN DUP 0> WHILE
        OVER C@ 32 127 WITHIN 0= IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT 2DROP -1 ;

: _TR-ASCII-LAYOUT  ( -- )
    \ Every field is the byte's index except the scalar itself, so walk
    \ the four arrays with running pointers instead of recomputing them.
    _TR-BASE _TR-PS !
    _TR-OFFSETS-OFF _TR-BASE + _TR-PO !
    0 _TR-RECORD DUP _TR-PR ! _TR-U @ _TR-REC * 0 FILL
    _TR-ORDER _TR-PD !
    _TR-U @ 0 ?DO
        _TR-A @ I + C@
        DUP _TR-PS @ L!  4 _TR-PS +!
        I _TR-PO @ L!    4 _TR-PO +!
        I _TR-PD @ L!    4 _TR-PD +!
        _TR-PR @ TUCK 8 + L!
        I OVER L!  I OVER 4 + L!  I OVER 12 + L!
        1 OVER 16 + L!  1 OVER 20 + L!  1 SWAP 24 + C!
        _TR-REC _TR-PR +!
    LOOP
    _TR-U @ DUP _TR-R @ _TR-O-N + ! DUP _TR-R @ _TR-O-CHARS + !
    DUP _TR-R @ _TR-O-VIS + ! _TR-R @ _TR-O-WIDTH + !
    0 _TR-R @ _TR-O-PARA + ! ;

: TROW-LAYOUT  ( addr u flags direction row -- ok? )
    _TR-SELECT _TR-DIR ! _TR-FLAGS ! _TR-U ! _TR-A !
    _TR-U @ _TR-ENSURE 0= IF 0 EXIT THEN
    _TR-U @ _TR-R @ _TR-O-BYTES + !
    _TR-ASCII? IF _TR-ASCII-LAYOUT -1 EXIT THEN
    _TR-READ
    _TR-DIR @ BIDI-RTL = IF -1 _TR-TRIGGER ! THEN
    _TR-TRIGGER @ IF
        _TR-CLASSES _TR-BASE _TR-R @ _TR-O-N + @ _TR-DIR @ _TR-WORK
        BIDI-RESOLVE
        _TR-R @ _TR-O-PARA + !
    ELSE
        0 _TR-R @ _TR-O-PARA + !
    THEN
    _TR-SHAPE
    _TR-ORDER-VISIBLE
    -1 ;

\ =====================================================================
\  §5 — Mapping between columns, positions, and bytes
\ =====================================================================

: TROW-DISPLAY  ( rec buf row -- n )
    _TR-SELECT                                ( rec buf )
    OVER TROW.CP0 OVER L!
    OVER TROW.SCALARS 1 ?DO
        OVER TROW.START I + _TR-SCALAR@ OVER I 4 * + L!
    LOOP
    DROP TROW.SCALARS ;

\ The visible character covering COLUMN, found by binary search over
\ the left-to-right columns.
: TROW-AT-COLUMN  ( column row -- rec | 0 )
    DUP _TR-SELECT
    OVER 0< IF 2DROP 0 EXIT THEN
    DUP TROW-WIDTH 2 PICK <= IF 2DROP 0 EXIT THEN
    TROW-VISIBLE 0 SWAP                       ( column lo hi )
    BEGIN 2DUP SWAP - 1 > WHILE
        2DUP + 2/ DUP 4 * _TR-ORDER + L@ _TR-RECORD TROW.COLUMN
        4 PICK > IF NIP ELSE ROT DROP SWAP THEN
    REPEAT
    DROP NIP 4 * _TR-ORDER + L@ _TR-RECORD ;

: TROW-POSITION-AT  ( column row -- offset )
    OVER 0< IF NIP 0 SWAP THEN
    TUCK TROW-AT-COLUMN ?DUP IF NIP TROW.START EXIT THEN
    TROW-LENGTH ;

\ The character containing scalar OFFSET, by binary search over the
\ logical records; -1 past the end.
: _TR-CHAR-INDEX  ( offset -- j | -1 )
    DUP _TR-R @ _TR-O-N + @ >= IF DROP -1 EXIT THEN
    0 _TR-R @ _TR-O-CHARS + @                 ( offset lo hi )
    BEGIN 2DUP SWAP - 1 > WHILE
        2DUP + 2/ DUP _TR-RECORD TROW.START
        4 PICK > IF NIP ELSE ROT DROP SWAP THEN
    REPEAT
    DROP NIP ;

: TROW-CARET  ( offset row -- rec | 0 )
    _TR-SELECT
    _TR-CHAR-INDEX DUP 0< IF DROP 0 EXIT THEN
    _TR-R @ _TR-O-CHARS + @ SWAP ?DO
        I _TR-RECORD DUP TROW.WIDTH IF UNLOOP EXIT THEN DROP
    LOOP
    0 ;

: TROW-OFFSET>BYTE  ( offset row -- byte )
    _TR-SELECT
    DUP _TR-R @ _TR-O-N + @ >= IF DROP _TR-R @ _TR-O-BYTES + @ EXIT THEN
    0 MAX _TR-OFFSET@ ;

: TROW-BYTE>OFFSET  ( byte row -- offset )
    _TR-SELECT
    DUP _TR-R @ _TR-O-BYTES + @ >= IF DROP _TR-R @ _TR-O-N + @ EXIT THEN
    0 _TR-R @ _TR-O-N + @                     ( byte lo hi )
    BEGIN 2DUP SWAP - 1 > WHILE
        2DUP + 2/ DUP _TR-OFFSET@
        4 PICK > IF NIP ELSE ROT DROP SWAP THEN
    REPEAT
    DROP NIP ;

\ =====================================================================
\  §6 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _trow-guard

' TROW-LAYOUT      CONSTANT _trow-layout-xt
' TROW-CHAR        CONSTANT _trow-char-xt
' TROW-VCHAR       CONSTANT _trow-vchar-xt
' TROW-DISPLAY     CONSTANT _trow-display-xt
' TROW-AT-COLUMN   CONSTANT _trow-at-column-xt
' TROW-POSITION-AT CONSTANT _trow-position-at-xt
' TROW-CARET       CONSTANT _trow-caret-xt
' TROW-OFFSET>BYTE CONSTANT _trow-offset-byte-xt
' TROW-BYTE>OFFSET CONSTANT _trow-byte-offset-xt

: TROW-LAYOUT      _trow-layout-xt _trow-guard WITH-GUARD ;
: TROW-CHAR        _trow-char-xt _trow-guard WITH-GUARD ;
: TROW-VCHAR       _trow-vchar-xt _trow-guard WITH-GUARD ;
: TROW-DISPLAY     _trow-display-xt _trow-guard WITH-GUARD ;
: TROW-AT-COLUMN   _trow-at-column-xt _trow-guard WITH-GUARD ;
: TROW-POSITION-AT _trow-position-at-xt _trow-guard WITH-GUARD ;
: TROW-CARET       _trow-caret-xt _trow-guard WITH-GUARD ;
: TROW-OFFSET>BYTE _trow-offset-byte-xt _trow-guard WITH-GUARD ;
: TROW-BYTE>OFFSET _trow-byte-offset-xt _trow-guard WITH-GUARD ;
[THEN] [THEN]
