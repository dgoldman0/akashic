\ =====================================================================
\  akashic/game/map.f — Text Maps
\ =====================================================================
\
\  A map is a UTF-8 text file a person writes and reads in Pad: a header
\  of `key: value` lines that holds a legend, then rows of glyphs.
\
\      name: The Bindery
\      width: 6
\      height: 3
\      tile: . floor 0 clear
\      tile: # shelf 1 opaque
\      spawn: @ archivist on .
\      spawn: f folio on .
\      rows:
\      ######
\      #@.f.#
\      ######
\
\  A `tile:` line gives a glyph, the name of its tile kind, the collision
\  value its tiles take, 0 to 255, and whether they let sight through,
\  `clear`, or block it, `opaque`.  A `spawn:` line gives a glyph that
\  marks where something starts, the mark's name, and `on` with the glyph
\  of a tile declared above it, which lies beneath the mark.  Any other
\  key holds a value the game reads, such as a room's name.  `width:` and
\  `height:` are required, whole numbers from 1; the `rows:` line ends the
\  header, and exactly `height` rows of exactly `width` glyphs follow it.
\  A glyph is one Unicode character other than a space or tab, used once
\  in the legend; a name holds letters, digits, `-` and `_`, and a key
\  appears once.  A map declares at most 256 tile kinds, the values a
\  byte of the kind layer holds; marks have no such bound.  Blank lines
\  may stand in the header and after the rows, and a CR before a line's
\  end is dropped.
\
\  A map gives a game three layers in the collision map's form
\  (collide.f), a byte a tile: the collision values, the sight map, 1
\  where a tile blocks sight, and the kinds, each tile's place in the
\  legend; then the spawns, where each mark stood, and the header's
\  values.  A map read from a file checks the file's size first and reads
\  exactly that.  The reader checks every line, and a map it refuses
\  answers a status, with GMAP-WHERE naming the line it broke at.  One
\  pass counts and a second fills exact allocations, so a map's storage
\  follows its text.
\
\  Map Descriptor (120 bytes):
\    +0   text      The map's text, which names and values point into
\    +8   len       Its bytes
\    +16  w         Width in tiles
\    +24  h         Height in tiles
\    +32  cmap      Collision values
\    +40  sight     1 where a tile blocks sight
\    +48  kinds     Each tile's kind
\    +56  tiles     Tile legend: 32-byte entries of glyph, name address,
\                   name length, and collision value + 256 when opaque
\    +64  ntiles
\    +72  marks     Spawn legend: glyph, name address, name length, and
\                   the tile kind beneath
\    +80  nmarks
\    +88  spawns    24-byte entries of x, y and mark
\    +96  nspawns
\    +104 values    32-byte entries of key address and length, value
\                   address and length
\    +112 nvalues
\
\  Public API:
\    GMAP-PARSE       ( text-a text-u -- map status )
\    GMAP-LOAD        ( path-a path-u place -- map status )
\    GMAP-FREE        ( map -- )
\    GMAP-WHERE       ( -- line )
\    GMAP-W  GMAP-H   ( map -- n )
\    GMAP-CMAP  GMAP-SIGHT  GMAP-KINDS   ( map -- cmap )
\    GMAP-TILE@       ( map x y -- kind )
\    GMAP-TILES       ( map -- n )
\    GMAP-TILE        ( map name-a name-u -- kind | -1 )
\    GMAP-TILE-NAME   ( map kind -- a u )
\    GMAP-TILE-GLYPH  ( map kind -- char )
\    GMAP-TILE-COLLISION ( map kind -- value )
\    GMAP-TILE-OPAQUE? ( map kind -- flag )
\    GMAP-MARKS       ( map -- n )
\    GMAP-MARK        ( map name-a name-u -- mark | -1 )
\    GMAP-MARK-NAME   ( map mark -- a u )
\    GMAP-MARK-GLYPH  ( map mark -- char )
\    GMAP-MARK-TILE   ( map mark -- kind )
\    GMAP-SPAWNS      ( map -- n )
\    GMAP-SPAWN@      ( map i -- x y mark )
\    GMAP-VALUE       ( map key-a key-u -- val-a val-u found? )
\
\  Prefix: GMAP- (public), _GMAP- / _GMP- / _GML- (internal)
\  Provider: akashic-game-map
\  Dependencies: utf8.f, collide.f, places.f, vfs-access.f

PROVIDED akashic-game-map

REQUIRE ../text/utf8.f
REQUIRE 2d/collide.f
REQUIRE ../utils/fs/places.f
REQUIRE ../utils/fs/vfs-access.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

0 CONSTANT GMAP-S-OK
1 CONSTANT GMAP-S-MISSING   \ no such file
2 CONSTANT GMAP-S-IO        \ reading the file failed
3 CONSTANT GMAP-S-NOMEM     \ no memory for the map
4 CONSTANT GMAP-S-UTF8      \ a line that is not UTF-8
5 CONSTANT GMAP-S-HEADER    \ a line that is no `key: value`, a key given
                            \ twice, or no `rows:` line
6 CONSTANT GMAP-S-SIZE      \ width or height missing, or not a whole
                            \ number from 1
7 CONSTANT GMAP-S-LEGEND    \ a malformed tile or spawn line, a glyph or
                            \ name given twice, a mark on no tile, or a
                            \ 257th tile kind
8 CONSTANT GMAP-S-ROW       \ a row of another width, a row missing, or
                            \ text after the rows
9 CONSTANT GMAP-S-GLYPH     \ a glyph in a row that the legend lacks

0   CONSTANT _GMAP-O-TEXT
8   CONSTANT _GMAP-O-LEN
16  CONSTANT _GMAP-O-W
24  CONSTANT _GMAP-O-H
32  CONSTANT _GMAP-O-CMAP
40  CONSTANT _GMAP-O-SIGHT
48  CONSTANT _GMAP-O-KINDS
56  CONSTANT _GMAP-O-TILES
64  CONSTANT _GMAP-O-NTILES
72  CONSTANT _GMAP-O-MARKS
80  CONSTANT _GMAP-O-NMARKS
88  CONSTANT _GMAP-O-SPAWNS
96  CONSTANT _GMAP-O-NSPAWNS
104 CONSTANT _GMAP-O-VALUES
112 CONSTANT _GMAP-O-NVALUES
120 CONSTANT _GMAP-DESC-SZ

\ Legend entries and values are 32 bytes; spawns 24
32 CONSTANT _GMAP-ENTRY-SZ
24 CONSTANT _GMAP-SPAWN-SZ
256 CONSTANT _GMAP-OPAQUE
256 CONSTANT _GMAP-MAX-TILES   \ the kinds a byte of the kind layer holds

\ =====================================================================
\  §2 — Reading Lines
\ =====================================================================

VARIABLE _GMP-MAP      \ the map being read
VARIABLE _GMP-P        \ where the next line starts
VARIABLE _GMP-END      \ the text's end
VARIABLE _GMP-LINE     \ the current line's number, from 1
VARIABLE _GMP-LA       \ the current line, without its end
VARIABLE _GMP-LU
VARIABLE _GMP-WHERE    \ the line the last refused map broke at
VARIABLE _GMP-FILL     \ false while a pass counts, true while it fills
VARIABLE _GMP-ROWS     \ where the rows begin
VARIABLE _GMP-ROWS-LINE
VARIABLE _GMP-NT       \ tiles, marks, values and spawns a pass has met
VARIABLE _GMP-NM
VARIABLE _GMP-NV
VARIABLE _GMP-NS

\ Refuse the map at the current line.
: _GMP-FAIL  ( status -- )  _GMP-LINE @ _GMP-WHERE !  THROW ;

\ The address of the LF that ends the line at p, or the text's end
: _GMP-EOL  ( p -- p' )
    BEGIN DUP _GMP-END @ U< IF DUP C@ 10 <> ELSE FALSE THEN WHILE 1+ REPEAT ;

\ Make the next line current; false at the text's end.
: _GMP-NEXT-LINE  ( -- flag )
    _GMP-P @ _GMP-END @ U< 0= IF FALSE EXIT THEN
    _GMP-P @ DUP _GMP-EOL DUP 1+ _GMP-P !          ( start eol )
    OVER -
    DUP IF 2DUP + 1- C@ 13 = IF 1- THEN THEN
    _GMP-LU ! _GMP-LA !
    1 _GMP-LINE +!  TRUE ;

: _GMP-ADV  ( a u n -- a' u' )  TUCK - >R + R> ;

: _GMP-SPACE?  ( c -- flag )  DUP 32 = SWAP 9 = OR ;

\ Skip spaces and tabs.
: _GMP-SKIP  ( a u -- a' u' )
    BEGIN DUP IF OVER C@ _GMP-SPACE? ELSE FALSE THEN WHILE 1 _GMP-ADV REPEAT ;

\ Drop the spaces and tabs at the end.
: _GMP-TRIM  ( a u -- a u' )
    BEGIN DUP IF 2DUP + 1- C@ _GMP-SPACE? ELSE FALSE THEN WHILE 1- REPEAT ;

: _GMP-BLANK?  ( a u -- flag )  _GMP-SKIP NIP 0= ;

\ The next field, up to a space or tab, and what follows it
: _GMP-FIELD  ( a u -- rest-a rest-u field-a field-u )
    _GMP-SKIP OVER >R
    BEGIN DUP IF OVER C@ _GMP-SPACE? 0= ELSE FALSE THEN WHILE 1 _GMP-ADV REPEAT
    OVER R@ - R> SWAP ;

: _GMP=  ( a1 u1 a2 u2 -- flag )  COMPARE 0= ;

: _GMP-NAME-CHAR?  ( c -- flag )
    DUP [CHAR] a [CHAR] z 1+ WITHIN  OVER [CHAR] A [CHAR] Z 1+ WITHIN OR
    OVER [CHAR] 0 [CHAR] 9 1+ WITHIN OR  OVER [CHAR] - = OR
    SWAP [CHAR] _ = OR ;

\ A name: letters, digits, - and _
: _GMP-NAME?  ( a u -- flag )
    DUP 0= IF 2DROP FALSE EXIT THEN
    BEGIN DUP WHILE
        OVER C@ _GMP-NAME-CHAR? 0= IF 2DROP FALSE EXIT THEN
        1 _GMP-ADV
    REPEAT
    2DROP TRUE ;

\ The parsing words below answer their results and a flag, the results
\ meaningless when the flag is false, so a refusal's path and the
\ success's hold the same items.

\ A whole number in decimal digits, of at most 18 of them
: _GMP-NUMBER  ( a u -- n flag )
    DUP 0= OVER 18 > OR IF 2DROP 0 FALSE EXIT THEN
    0 -ROT
    BEGIN DUP WHILE
        OVER C@ [CHAR] 0 - DUP 10 U< 0= IF DROP 2DROP FALSE EXIT THEN
        >R ROT 10 * R> + -ROT  1 _GMP-ADV
    REPEAT
    2DROP TRUE ;

\ One character: its code point
: _GMP-GLYPH  ( a u -- char flag )
    DUP 0= IF 2DROP 0 FALSE EXIT THEN
    UTF8-DECODE NIP 0= ;

\ The line as `key: value`: the key, and the value without the spaces
\ around it; the flag is false when the line holds no colon or its key
\ is no name
: _GMP-KEY-VALUE  ( a u -- key-a key-u val-a val-u flag )
    2DUP
    BEGIN DUP IF OVER C@ [CHAR] : <> ELSE FALSE THEN WHILE 1 _GMP-ADV REPEAT
    DUP 0= IF FALSE EXIT THEN                     ( a u colon-a colon-u )
    OVER >R  1 _GMP-ADV _GMP-SKIP _GMP-TRIM       ( a u val-a val-u  R: colon )
    2SWAP DROP R> OVER -                          ( val-a val-u a key-u )
    2SWAP 2OVER _GMP-NAME? ;

\ =====================================================================
\  §3 — The Legend and the Values
\ =====================================================================

: _GMP-TILE-TABLE  ( -- table )  _GMP-MAP @ _GMAP-O-TILES + @ ;
: _GMP-MARK-TABLE  ( -- table )  _GMP-MAP @ _GMAP-O-MARKS + @ ;
: _GMP-VALUE-TABLE ( -- table )  _GMP-MAP @ _GMAP-O-VALUES + @ ;

\ The entry among n whose glyph is char, or -1
: _GMP-FIND-GLYPH  ( char table n -- index|-1 )
    0 ?DO
        2DUP I _GMAP-ENTRY-SZ * + @ = IF 2DROP I UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ The entry among n whose text at offset off is a u, or -1
: _GMP-FIND-AT  ( a u table n off -- index|-1 )
    ROT + SWAP
    0 ?DO
        DUP I _GMAP-ENTRY-SZ * + DUP @ SWAP CELL+ @
        4 PICK 4 PICK _GMP= IF DROP 2DROP I UNLOOP EXIT THEN
    LOOP
    DROP 2DROP -1 ;

\ Is the glyph in the legend so far?
: _GMP-GLYPH-TAKEN?  ( char -- flag )
    DUP _GMP-TILE-TABLE _GMP-NT @ _GMP-FIND-GLYPH 0< 0=
    SWAP _GMP-MARK-TABLE _GMP-NM @ _GMP-FIND-GLYPH 0< 0= OR ;

\ Write a legend entry: glyph, name and its last cell.
: _GMP-ENTRY!  ( char name-a name-u extra entry -- )
    TUCK 24 + !  TUCK 16 + !  TUCK 8 + !  ! ;

\ The legend's glyph and name at the start of a tile or spawn line,
\ each new to the legend so far
: _GMP-GLYPH-NAME  ( a u table n -- rest-a rest-u char name-a name-u )
    2>R
    _GMP-FIELD _GMP-GLYPH 0= IF GMAP-S-LEGEND _GMP-FAIL THEN
    DUP _GMP-GLYPH-TAKEN? IF GMAP-S-LEGEND _GMP-FAIL THEN
    -ROT _GMP-FIELD                               ( char rest-a rest-u name-a name-u )
    2DUP _GMP-NAME? 0= IF GMAP-S-LEGEND _GMP-FAIL THEN
    2DUP 2R> 8 _GMP-FIND-AT 0< 0= IF GMAP-S-LEGEND _GMP-FAIL THEN
    2>R ROT 2R> ;

\ Nothing may follow a legend line's last field.
: _GMP-LINE-END  ( a u -- )
    _GMP-SKIP NIP IF GMAP-S-LEGEND _GMP-FAIL THEN ;

\ A `tile:` line's value: glyph, name, collision value, clear or opaque
: _GMP-TILE-LINE  ( a u -- )
    _GMP-FILL @ 0= IF 2DROP 1 _GMP-NT +! EXIT THEN
    _GMP-NT @ _GMAP-MAX-TILES = IF GMAP-S-LEGEND _GMP-FAIL THEN
    _GMP-TILE-TABLE _GMP-NT @ _GMP-GLYPH-NAME 2>R >R    ( a u  R: name char )
    _GMP-FIELD _GMP-NUMBER 0= IF GMAP-S-LEGEND _GMP-FAIL THEN
    DUP 255 > IF GMAP-S-LEGEND _GMP-FAIL THEN -ROT     ( value a u )
    _GMP-FIELD 2DUP S" opaque" _GMP= IF
        2DROP _GMAP-OPAQUE
    ELSE
        S" clear" _GMP= 0= IF GMAP-S-LEGEND _GMP-FAIL THEN 0
    THEN                                          ( value a u sight )
    -ROT _GMP-LINE-END OR                         ( extra )
    R> SWAP 2R> ROT                               ( char name-a name-u extra )
    _GMP-TILE-TABLE _GMP-NT @ _GMAP-ENTRY-SZ * + _GMP-ENTRY!
    1 _GMP-NT +! ;

\ A `spawn:` line's value: glyph, name, `on`, the glyph of a tile above
: _GMP-MARK-LINE  ( a u -- )
    _GMP-FILL @ 0= IF 2DROP 1 _GMP-NM +! EXIT THEN
    _GMP-MARK-TABLE _GMP-NM @ _GMP-GLYPH-NAME 2>R >R    ( a u  R: name char )
    _GMP-FIELD S" on" _GMP= 0= IF GMAP-S-LEGEND _GMP-FAIL THEN
    _GMP-FIELD _GMP-GLYPH 0= IF GMAP-S-LEGEND _GMP-FAIL THEN
    _GMP-TILE-TABLE _GMP-NT @ _GMP-FIND-GLYPH
    DUP 0< IF GMAP-S-LEGEND _GMP-FAIL THEN -ROT   ( kind a u )
    _GMP-LINE-END                                 ( kind )
    R> SWAP 2R> ROT                               ( char name-a name-u kind )
    _GMP-MARK-TABLE _GMP-NM @ _GMAP-ENTRY-SZ * + _GMP-ENTRY!
    1 _GMP-NM +! ;

\ Width or height from its value
: _GMP-SIZE!  ( val-a val-u offset -- )
    >R _GMP-NUMBER 0= IF GMAP-S-SIZE _GMP-FAIL THEN
    DUP 0= IF GMAP-S-SIZE _GMP-FAIL THEN
    _GMP-MAP @ R> + ! ;

\ Any other `key: value` line, a value the game reads
: _GMP-VALUE-LINE  ( key-a key-u val-a val-u -- )
    _GMP-FILL @ 0= IF 2DROP 2DROP 1 _GMP-NV +! EXIT THEN
    2OVER _GMP-VALUE-TABLE _GMP-NV @ 0 _GMP-FIND-AT 0< 0= IF
        GMAP-S-HEADER _GMP-FAIL
    THEN
    2OVER S" width" _GMP= IF 2DUP _GMAP-O-W _GMP-SIZE! THEN
    2OVER S" height" _GMP= IF 2DUP _GMAP-O-H _GMP-SIZE! THEN
    _GMP-VALUE-TABLE _GMP-NV @ _GMAP-ENTRY-SZ * + _GMP-ENTRY!
    1 _GMP-NV +! ;

\ Read the header to its `rows:` line, counting or filling.
: _GMP-HEADER  ( -- )
    0 _GMP-NT !  0 _GMP-NM !  0 _GMP-NV !
    BEGIN
        _GMP-NEXT-LINE 0= IF 1 _GMP-LINE +!  GMAP-S-HEADER _GMP-FAIL THEN
        _GMP-FILL @ 0= IF
            _GMP-LA @ _GMP-LU @ UTF8-VALID? 0= IF GMAP-S-UTF8 _GMP-FAIL THEN
        THEN
        _GMP-LA @ _GMP-LU @ _GMP-BLANK? 0= IF
            _GMP-LA @ _GMP-LU @ _GMP-KEY-VALUE 0= IF GMAP-S-HEADER _GMP-FAIL THEN
            2OVER S" rows" _GMP= IF
                NIP NIP NIP IF GMAP-S-HEADER _GMP-FAIL THEN EXIT
            THEN
            2OVER S" tile" _GMP= IF
                2SWAP 2DROP _GMP-TILE-LINE
            ELSE 2OVER S" spawn" _GMP= IF
                2SWAP 2DROP _GMP-MARK-LINE
            ELSE
                _GMP-VALUE-LINE
            THEN THEN
        THEN
    AGAIN ;

\ =====================================================================
\  §4 — The Rows
\ =====================================================================

: _GMP-TILE-EXTRA  ( kind -- extra )
    _GMAP-ENTRY-SZ * _GMP-TILE-TABLE + 24 + @ ;

\ Set the three layers at x y for a tile of the kind.
: _GMP-SET  ( x y kind -- )
    >R _GMP-MAP @ _GMAP-O-W + @ * +               ( offset  R: kind )
    R@ OVER _GMP-MAP @ _GMAP-O-KINDS + @ CMAP-DATA + C!
    R> _GMP-TILE-EXTRA DUP 255 AND 2 PICK
    _GMP-MAP @ _GMAP-O-CMAP + @ CMAP-DATA + C!    ( offset extra )
    8 RSHIFT 1 AND SWAP _GMP-MAP @ _GMAP-O-SIGHT + @ CMAP-DATA + C! ;

: _GMP-SPAWN!  ( x y mark -- )
    _GMP-MAP @ _GMAP-O-SPAWNS + @ _GMP-NS @ _GMAP-SPAWN-SZ * +
    TUCK 16 + !  TUCK 8 + !  !
    1 _GMP-NS +! ;

\ The tile at x y shows a glyph: count it, or fill the layers with it.
: _GMP-TILE!  ( x y char -- )
    DUP _GMP-TILE-TABLE _GMP-NT @ _GMP-FIND-GLYPH DUP 0< 0= IF
        NIP _GMP-FILL @ IF _GMP-SET ELSE DROP 2DROP THEN EXIT
    THEN
    DROP _GMP-MARK-TABLE _GMP-NM @ _GMP-FIND-GLYPH      ( x y mark )
    DUP 0< IF GMAP-S-GLYPH _GMP-FAIL THEN
    _GMP-FILL @ 0= IF DROP 2DROP 1 _GMP-NS +! EXIT THEN
    >R 2DUP R@ _GMP-SPAWN!
    R> _GMAP-ENTRY-SZ * _GMP-MARK-TABLE + 24 + @ _GMP-SET ;

\ Row y, the current line: exactly the width's glyphs
: _GMP-ROW  ( y -- )
    _GMP-LA @ _GMP-LU @                           ( y a u )
    _GMP-MAP @ _GMAP-O-W + @ 0 ?DO
        DUP 0= IF GMAP-S-ROW _GMP-FAIL THEN
        UTF8-DECODE ROT                           ( y a' u' char )
        3 PICK I SWAP ROT _GMP-TILE!
    LOOP
    NIP IF GMAP-S-ROW _GMP-FAIL THEN DROP ;

\ Read the rows, counting the spawn marks or filling the layers, and
\ nothing after them but blank lines.
: _GMP-ROWS-PASS  ( -- )
    _GMP-ROWS @ _GMP-P !  _GMP-ROWS-LINE @ _GMP-LINE !  0 _GMP-NS !
    _GMP-MAP @ _GMAP-O-H + @ 0 ?DO
        _GMP-NEXT-LINE 0= IF 1 _GMP-LINE +!  GMAP-S-ROW _GMP-FAIL THEN
        _GMP-FILL @ 0= IF
            _GMP-LA @ _GMP-LU @ UTF8-VALID? 0= IF GMAP-S-UTF8 _GMP-FAIL THEN
        THEN
        I _GMP-ROW
    LOOP
    BEGIN _GMP-NEXT-LINE WHILE
        _GMP-LA @ _GMP-LU @ _GMP-BLANK? 0= IF GMAP-S-ROW _GMP-FAIL THEN
    REPEAT ;

\ =====================================================================
\  §5 — Parsing
\ =====================================================================

\ An array of n entries of size bytes for the map's field at offset
: _GMP-TABLE  ( n size offset -- )
    >R * ?DUP IF
        ALLOCATE IF GMAP-S-NOMEM _GMP-FAIL THEN
    ELSE
        0
    THEN
    _GMP-MAP @ R> + ! ;

\ A layer of the map's size for its field at offset
: _GMP-LAYER  ( offset -- )
    _GMP-MAP @ DUP _GMAP-O-W + @ SWAP _GMAP-O-H + @ CMAP-NEW?
    IF GMAP-S-NOMEM _GMP-FAIL THEN
    _GMP-MAP @ ROT + ! ;

: _GMP-RESTART  ( -- )
    _GMP-MAP @ _GMAP-O-TEXT + @ _GMP-P !  0 _GMP-LINE ! ;

\ Read the map's text: count the legend and the values and fill them,
\ then count the spawns and fill the layers.
: _GMP-PARSE  ( -- )
    _GMP-MAP @ DUP _GMAP-O-TEXT + @ SWAP _GMAP-O-LEN + @ + _GMP-END !
    _GMP-RESTART  FALSE _GMP-FILL !  _GMP-HEADER
    _GMP-P @ _GMP-ROWS !  _GMP-LINE @ _GMP-ROWS-LINE !
    _GMP-NT @ DUP _GMP-MAP @ _GMAP-O-NTILES + !
        _GMAP-ENTRY-SZ _GMAP-O-TILES _GMP-TABLE
    _GMP-NM @ DUP _GMP-MAP @ _GMAP-O-NMARKS + !
        _GMAP-ENTRY-SZ _GMAP-O-MARKS _GMP-TABLE
    _GMP-NV @ DUP _GMP-MAP @ _GMAP-O-NVALUES + !
        _GMAP-ENTRY-SZ _GMAP-O-VALUES _GMP-TABLE
    _GMP-RESTART  TRUE _GMP-FILL !  _GMP-HEADER
    _GMP-MAP @ DUP _GMAP-O-W + @ 0= SWAP _GMAP-O-H + @ 0= OR IF
        GMAP-S-SIZE _GMP-FAIL
    THEN
    FALSE _GMP-FILL !  _GMP-ROWS-PASS
    _GMP-NS @ DUP _GMP-MAP @ _GMAP-O-NSPAWNS + !
        _GMAP-SPAWN-SZ _GMAP-O-SPAWNS _GMP-TABLE
    _GMAP-O-CMAP _GMP-LAYER  _GMAP-O-SIGHT _GMP-LAYER  _GMAP-O-KINDS _GMP-LAYER
    TRUE _GMP-FILL !  _GMP-ROWS-PASS ;

\ GMAP-FREE ( map -- )
\   Free the map in the reverse of the order a read allocates it, so
\   that reading the same map again takes back the same holes of the
\   heap, which never joins them.
: GMAP-FREE  ( map -- )
    DUP _GMAP-O-KINDS + @ ?DUP IF CMAP-FREE THEN
    DUP _GMAP-O-SIGHT + @ ?DUP IF CMAP-FREE THEN
    DUP _GMAP-O-CMAP + @ ?DUP IF CMAP-FREE THEN
    DUP _GMAP-O-SPAWNS + @ FREE
    DUP _GMAP-O-VALUES + @ FREE
    DUP _GMAP-O-MARKS + @ FREE
    DUP _GMAP-O-TILES + @ FREE
    DUP _GMAP-O-TEXT + @ SWAP FREE FREE ;

\ Parse the text in buf, which the map takes over.  A throw other than
\ a refusal goes on to the caller once the map is freed.
: _GMP-RUN  ( buf len -- map status )
    _GMAP-DESC-SZ ALLOCATE IF DROP DROP FREE 0 GMAP-S-NOMEM EXIT THEN
    DUP _GMAP-DESC-SZ 0 FILL
    TUCK _GMAP-O-LEN + !  TUCK _GMAP-O-TEXT + !    ( map )
    DUP _GMP-MAP !
    ['] _GMP-PARSE CATCH ?DUP IF
        SWAP GMAP-FREE
        DUP GMAP-S-NOMEM GMAP-S-GLYPH 1+ WITHIN 0= IF THROW THEN
        0 SWAP EXIT
    THEN
    GMAP-S-OK ;

\ GMAP-PARSE ( text-a text-u -- map status )
\   A map from text in memory, which the map copies.
: GMAP-PARSE  ( text-a text-u -- map status )
    0 _GMP-WHERE !
    DUP 0= IF 2DROP 1 _GMP-WHERE ! 0 GMAP-S-HEADER EXIT THEN
    DUP ALLOCATE IF DROP 2DROP 0 GMAP-S-NOMEM EXIT THEN    ( a u buf )
    DUP >R SWAP DUP >R CMOVE R> R> SWAP _GMP-RUN ;

\ =====================================================================
\  §6 — Loading through a Place
\ =====================================================================

VARIABLE _GML-FD

\ Close the map's file and answer a refusal.
: _GML-REFUSE  ( status -- 0 status )
    _GML-FD @ VFS-CLOSE? DROP  0 SWAP ;

\ GMAP-LOAD ( path-a path-u place -- map status )
\   A map from the file a path names in a place: the applet's origin for
\   the maps it ships, its home for a player's own.
: GMAP-LOAD  ( path-a path-u place -- map status )
    0 _GMP-WHERE !
    VFS-FF-READ SWAP PLACE-OPEN ?DUP IF
        NIP VFS-IOR-REASON VFS-R-NOENT = IF GMAP-S-MISSING ELSE GMAP-S-IO THEN
        0 SWAP EXIT
    THEN
    _GML-FD !
    _GML-FD @ VFA-FILE-SIZE? IF DROP GMAP-S-IO _GML-REFUSE EXIT THEN
    ?DUP 0= IF 1 _GMP-WHERE ! GMAP-S-HEADER _GML-REFUSE EXIT THEN
    DUP ALLOCATE IF 2DROP GMAP-S-NOMEM _GML-REFUSE EXIT THEN    ( size buf )
    DUP 2 PICK _GML-FD @ VFA-READ-FILE?                         ( size buf len ior )
    _GML-FD @ VFS-CLOSE? OR IF DROP FREE DROP 0 GMAP-S-IO EXIT THEN
    ROT OVER <> IF DROP FREE 0 GMAP-S-IO EXIT THEN              ( buf len )
    _GMP-RUN ;

\ =====================================================================
\  §7 — Queries
\ =====================================================================

\ GMAP-WHERE ( -- line )  The line the last refused map broke at.
: GMAP-WHERE  ( -- line )  _GMP-WHERE @ ;

: GMAP-W      ( map -- w )     _GMAP-O-W + @ ;
: GMAP-H      ( map -- h )     _GMAP-O-H + @ ;
: GMAP-CMAP   ( map -- cmap )  _GMAP-O-CMAP + @ ;
: GMAP-SIGHT  ( map -- cmap )  _GMAP-O-SIGHT + @ ;
: GMAP-KINDS  ( map -- cmap )  _GMAP-O-KINDS + @ ;

: GMAP-TILE@  ( map x y -- kind )  ROT GMAP-KINDS -ROT CMAP-GET ;

: GMAP-TILES  ( map -- n )  _GMAP-O-NTILES + @ ;
: GMAP-MARKS  ( map -- n )  _GMAP-O-NMARKS + @ ;

: _GMAP-TILE-ENTRY  ( map kind -- entry )
    _GMAP-ENTRY-SZ * SWAP _GMAP-O-TILES + @ + ;
: _GMAP-MARK-ENTRY  ( map mark -- entry )
    _GMAP-ENTRY-SZ * SWAP _GMAP-O-MARKS + @ + ;

: GMAP-TILE  ( map name-a name-u -- kind | -1 )
    ROT DUP _GMAP-O-TILES + @ SWAP GMAP-TILES 8 _GMP-FIND-AT ;
: GMAP-TILE-NAME   ( map kind -- a u )
    _GMAP-TILE-ENTRY DUP 8 + @ SWAP 16 + @ ;
: GMAP-TILE-GLYPH  ( map kind -- char )  _GMAP-TILE-ENTRY @ ;
: GMAP-TILE-COLLISION  ( map kind -- value )
    _GMAP-TILE-ENTRY 24 + @ 255 AND ;
: GMAP-TILE-OPAQUE?  ( map kind -- flag )
    _GMAP-TILE-ENTRY 24 + @ _GMAP-OPAQUE AND 0<> ;

: GMAP-MARK  ( map name-a name-u -- mark | -1 )
    ROT DUP _GMAP-O-MARKS + @ SWAP GMAP-MARKS 8 _GMP-FIND-AT ;
: GMAP-MARK-NAME   ( map mark -- a u )
    _GMAP-MARK-ENTRY DUP 8 + @ SWAP 16 + @ ;
: GMAP-MARK-GLYPH  ( map mark -- char )  _GMAP-MARK-ENTRY @ ;
: GMAP-MARK-TILE   ( map mark -- kind )  _GMAP-MARK-ENTRY 24 + @ ;

: GMAP-SPAWNS  ( map -- n )  _GMAP-O-NSPAWNS + @ ;
: GMAP-SPAWN@  ( map i -- x y mark )
    _GMAP-SPAWN-SZ * SWAP _GMAP-O-SPAWNS + @ +
    DUP @ OVER 8 + @ ROT 16 + @ ;

\ GMAP-VALUE ( map key-a key-u -- val-a val-u found? )
\   The value of a header key, `width` and `height` among them.
: GMAP-VALUE  ( map key-a key-u -- val-a val-u found? )
    ROT DUP _GMAP-O-VALUES + @ SWAP _GMAP-O-NVALUES + @   ( a u table n )
    OVER >R 0 _GMP-FIND-AT                        ( index  R: table )
    DUP 0< IF R> 2DROP 0 0 FALSE EXIT THEN
    _GMAP-ENTRY-SZ * R> + DUP 16 + @ SWAP 24 + @ TRUE ;

\ =====================================================================
\  §8 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _gmap-guard

' GMAP-PARSE  CONSTANT _gmap-parse-xt
' GMAP-LOAD   CONSTANT _gmap-load-xt
' GMAP-FREE   CONSTANT _gmap-free-xt

: GMAP-PARSE  _gmap-parse-xt  _gmap-guard WITH-GUARD ;
: GMAP-LOAD   _gmap-load-xt   _gmap-guard WITH-GUARD ;
: GMAP-FREE   _gmap-free-xt   _gmap-guard WITH-GUARD ;
[THEN] [THEN]
