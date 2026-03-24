\ =====================================================================
\  akashic/tui/game/map-loader.f — Map Loader (CBOR-based)
\ =====================================================================
\
\  Load tilemaps and collision maps from a CBOR file format.
\  Supports multiple layers, collision data, spawn points, and
\  trigger zones.
\
\  Map file format (CBOR map):
\    "w"         — uint, map width in tiles
\    "h"         — uint, map height in tiles
\    "layers"    — uint, number of tilemap layers (1-4)
\    "L0".."L3"  — bstr, raw tile data for each layer
\                   (w*h cells, each cell = 8 bytes LE, atlas tile IDs)
\    "cmap"      — bstr, collision map (w*h bytes, 0=passable)
\    "spawns"    — uint, number of spawn points
\    "SP0".."SP9"— array[3]: id, x, y
\    "triggers"  — uint, number of trigger zones
\    "TR0".."TR9"— array[6]: id, x, y, w, h, callback-tag
\
\  World Descriptor (88 bytes, 11 cells):
\    +0   width     Map width in tiles
\    +8   height    Map height in tiles
\    +16  n-layers  Number of tilemap layers
\    +24  layer-0   Tilemap for layer 0 (or 0)
\    +32  layer-1   Tilemap for layer 1 (or 0)
\    +40  layer-2   Tilemap for layer 2 (or 0)
\    +48  layer-3   Tilemap for layer 3 (or 0)
\    +56  cmap      Collision map (or 0)
\    +64  spawns    Spawn point table address (or 0)
\    +72  n-spawns  Number of spawn points
\    +80  triggers  Trigger table address (or 0)
\    +88  n-trigs   Number of trigger zones
\
\  Spawn entry (24 bytes, 3 cells): id, x, y
\  Trigger entry (48 bytes, 6 cells): id, x, y, w, h, tag
\
\  Public API:
\    MLOAD         ( path-a path-u atlas -- world )
\    MLOAD-LAYER   ( world n -- tmap )
\    MLOAD-CMAP    ( world -- cmap )
\    MLOAD-SPAWN   ( world id -- x y )
\    MLOAD-TRIGGER ( world id -- x y w h callback-tag )
\    MLOAD-FREE    ( world -- )
\    MLOAD-W       ( world -- w )
\    MLOAD-H       ( world -- h )
\
\  Prefix: MLOAD- (public), _ML- (internal)
\  Provider: akashic-tui-game-map-loader
\  Dependencies: cbor.f, tilemap.f, collide.f

PROVIDED akashic-tui-game-map-loader

REQUIRE ../../cbor/cbor.f
REQUIRE tilemap.f
REQUIRE ../../game/2d/collide.f
REQUIRE atlas.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

0  CONSTANT _ML-O-W
8  CONSTANT _ML-O-H
16 CONSTANT _ML-O-NLAYERS
24 CONSTANT _ML-O-L0
32 CONSTANT _ML-O-L1
40 CONSTANT _ML-O-L2
48 CONSTANT _ML-O-L3
56 CONSTANT _ML-O-CMAP
64 CONSTANT _ML-O-SPAWNS
72 CONSTANT _ML-O-NSPAWNS
80 CONSTANT _ML-O-TRIGS
88 CONSTANT _ML-O-NTRIGS
96 CONSTANT _ML-DESC-SZ

\ Spawn entry: 3 cells = 24 bytes (id, x, y)
24 CONSTANT _ML-SPAWN-SZ

\ Trigger entry: 6 cells = 48 bytes (id, x, y, w, h, tag)
48 CONSTANT _ML-TRIG-SZ

\ Max save file size for reading
16384 CONSTANT _ML-BUF-CAP

\ =====================================================================
\  §2 — File I/O (reuse save.f EVALUATE pattern)
\ =====================================================================

CREATE _ML-CMD 80 ALLOT
VARIABLE _ML-CMD-OFF

: _ML-CMD-RESET  ( -- )
    _ML-CMD 80 0 FILL  0 _ML-CMD-OFF ! ;

VARIABLE _ML-CS-LEN
: _ML-CMD-S  ( addr len -- )
    DUP _ML-CS-LEN !
    _ML-CMD _ML-CMD-OFF @ + SWAP CMOVE
    _ML-CS-LEN @ _ML-CMD-OFF +! ;

: _ML-CMD-EXEC  ( -- ... )
    _ML-CMD _ML-CMD-OFF @ EVALUATE ;

VARIABLE _ML-OPEN-A
VARIABLE _ML-OPEN-U
: _ML-FOPEN  ( path-a path-u -- fdesc | 0 )
    _ML-OPEN-U ! _ML-OPEN-A !
    _ML-CMD-RESET
    S" OPEN " _ML-CMD-S
    _ML-OPEN-A @ _ML-OPEN-U @ _ML-CMD-S
    _ML-CMD-EXEC ;

\ =====================================================================
\  §3 — CBOR Key Lookup Helper
\ =====================================================================
\
\  Scan a CBOR map for a text key matching the given string.
\  On success, leaves the parse cursor on the value; returns -1.
\  On failure, returns 0 with cursor exhausted.

VARIABLE _ML-MCOUNT    \ map pair count (set by caller)
VARIABLE _ML-SAVE-PTR  \ saved cursor for rewind

\ String comparison (same as save.f pattern)
VARIABLE _ML-CMP-A1 VARIABLE _ML-CMP-U1
VARIABLE _ML-CMP-A2 VARIABLE _ML-CMP-U2
: _ML-STREQ  ( a1 u1 a2 u2 -- flag )
    _ML-CMP-U2 ! _ML-CMP-A2 !
    _ML-CMP-U1 ! _ML-CMP-A1 !
    _ML-CMP-U1 @ _ML-CMP-U2 @ <> IF 0 EXIT THEN
    _ML-CMP-U1 @ 0 ?DO
        _ML-CMP-A1 @ I + C@
        _ML-CMP-A2 @ I + C@ <> IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

\ Reparse CBOR from buffer, consume map header, return pair count.
VARIABLE _ML-PARSE-A
VARIABLE _ML-PARSE-U
: _ML-REPARSE  ( addr len -- count )
    _ML-PARSE-U ! _ML-PARSE-A !
    _ML-PARSE-A @ _ML-PARSE-U @ CBOR-PARSE DROP
    CBOR-NEXT-MAP ;

VARIABLE _ML-FK-KA
VARIABLE _ML-FK-KU
: _ML-FIND-KEY  ( buf-a buf-u key-a key-u -- flag )
    _ML-FK-KU ! _ML-FK-KA !
    _ML-REPARSE _ML-MCOUNT !
    _ML-MCOUNT @ 0 ?DO
        CBOR-TYPE CBOR-MT-TSTR <> IF
            CBOR-SKIP CBOR-SKIP
        ELSE
            CBOR-NEXT-TSTR
            _ML-FK-KA @ _ML-FK-KU @ _ML-STREQ IF
                -1 UNLOOP EXIT
            THEN
            CBOR-SKIP
        THEN
    LOOP
    0 ;

\ =====================================================================
\  §4 — MLOAD: Main Map Loader
\ =====================================================================

CREATE _ML-RBUF _ML-BUF-CAP ALLOT     \ read buffer
VARIABLE _ML-RLEN                      \ bytes read
VARIABLE _ML-WORLD                     \ world descriptor
VARIABLE _ML-ATLAS                     \ atlas for resolving tiles
VARIABLE _ML-MW                        \ map width
VARIABLE _ML-MH                        \ map height

\ Load layer tile data from CBOR bstr into tilemap.
\ bstr contains w*h tile-ID cells (8 bytes each, LE).
\ We resolve each ID through the atlas to get a Cell value.
VARIABLE _ML-TMAP
VARIABLE _ML-BADDR
VARIABLE _ML-BLEN
VARIABLE _ML-COL
VARIABLE _ML-ROW
VARIABLE _ML-CELL                      \ resolved cell value
: _ML-LOAD-LAYER-DATA  ( tmap bstr-addr bstr-len -- )
    _ML-BLEN ! _ML-BADDR ! _ML-TMAP !
    0 _ML-ROW !
    BEGIN _ML-ROW @ _ML-MH @ < WHILE
        0 _ML-COL !
        BEGIN _ML-COL @ _ML-MW @ < WHILE
            \ Read 8-byte LE tile ID from blob
            _ML-ROW @ _ML-MW @ * _ML-COL @ + 8 *
            _ML-BADDR @ +             ( byte-addr )
            DUP C@                    ( byte-addr b0 )
            OVER 1+ C@ 8 LSHIFT OR
            OVER 2 + C@ 16 LSHIFT OR
            OVER 3 + C@ 24 LSHIFT OR
            OVER 4 + C@ 32 LSHIFT OR
            OVER 5 + C@ 40 LSHIFT OR
            OVER 6 + C@ 48 LSHIFT OR
            SWAP 7 + C@ 56 LSHIFT OR ( tile-id )
            \ Resolve through atlas to get Cell
            _ML-ATLAS @ SWAP ATLAS-GET _ML-CELL !
            \ Store in tilemap
            _ML-TMAP @ _ML-COL @ _ML-ROW @ _ML-CELL @ TMAP-SET
            1 _ML-COL +!
        REPEAT
        1 _ML-ROW +!
    REPEAT ;

\ Load collision data from CBOR bstr into cmap.
\ bstr contains w*h bytes (1 byte per tile).
VARIABLE _ML-CMAP-P
VARIABLE _ML-CADDR
VARIABLE _ML-CVAL                      \ collision tile value
: _ML-LOAD-CMAP-DATA  ( cmap bstr-addr bstr-len -- )
    DROP _ML-CADDR ! _ML-CMAP-P !
    0 _ML-ROW !
    BEGIN _ML-ROW @ _ML-MH @ < WHILE
        0 _ML-COL !
        BEGIN _ML-COL @ _ML-MW @ < WHILE
            _ML-ROW @ _ML-MW @ * _ML-COL @ +
            _ML-CADDR @ + C@ _ML-CVAL !
            _ML-CMAP-P @ _ML-COL @ _ML-ROW @ _ML-CVAL @ CMAP-SET
            1 _ML-COL +!
        REPEAT
        1 _ML-ROW +!
    REPEAT ;

\ Key name buffers for "L0".."L3"
CREATE _ML-LKEY 4 ALLOT

\ MLOAD ( path-a path-u atlas -- world )
\   Load a map file.  Returns world descriptor or 0 on failure.
VARIABLE _ML-FD
VARIABLE _ML-NLAYERS
VARIABLE _ML-I
VARIABLE _ML-TR-ENTRY                 \ shared between MLOAD and MLOAD-TRIGGER
: MLOAD  ( path-a path-u atlas -- world )
    _ML-ATLAS !
    \ Ensure filesystem
    FS-OK @ 0= IF FS-ENSURE THEN
    \ Open file
    _ML-FOPEN                         ( fdesc | 0 )
    DUP 0= IF EXIT THEN
    _ML-FD !
    _ML-FD @ FREWIND
    _ML-RBUF _ML-BUF-CAP _ML-FD @ FREAD
    _ML-RLEN !
    _ML-FD @ FCLOSE
    0 _ML-FD !
    _ML-RLEN @ 0= IF 0 EXIT THEN
    \ Read width
    _ML-RBUF _ML-RLEN @ S" w" _ML-FIND-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT _ML-MW !
    \ Read height
    _ML-RBUF _ML-RLEN @ S" h" _ML-FIND-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT _ML-MH !
    \ Read layer count
    _ML-RBUF _ML-RLEN @ S" layers" _ML-FIND-KEY 0= IF 0 EXIT THEN
    CBOR-NEXT-UINT _ML-NLAYERS !
    _ML-NLAYERS @ 4 MIN _ML-NLAYERS !
    \ Allocate world descriptor
    _ML-DESC-SZ ALLOCATE
    0<> IF 0 EXIT THEN
    _ML-WORLD !
    _ML-WORLD @ _ML-DESC-SZ 0 FILL
    _ML-MW @ _ML-WORLD @ _ML-O-W + !
    _ML-MH @ _ML-WORLD @ _ML-O-H + !
    _ML-NLAYERS @ _ML-WORLD @ _ML-O-NLAYERS + !
    \ Load each layer
    0 _ML-I !
    BEGIN _ML-I @ _ML-NLAYERS @ < WHILE
        \ Build key "L0", "L1", etc.
        76 _ML-LKEY C!                \ 'L'
        _ML-I @ 48 + _ML-LKEY 1+ C!  \ '0'+i
        _ML-RBUF _ML-RLEN @ _ML-LKEY 2 _ML-FIND-KEY IF
            CBOR-TYPE CBOR-MT-BSTR = IF
                CBOR-NEXT-BSTR        ( addr len )
                \ Create tilemap for this layer
                _ML-MW @ _ML-MH @ TMAP-NEW ( addr len tmap )
                DUP _ML-WORLD @ _ML-O-L0 _ML-I @ 8 * + + !
                -ROT                  ( tmap addr len )
                _ML-LOAD-LAYER-DATA
            ELSE
                CBOR-SKIP
            THEN
        THEN
        1 _ML-I +!
    REPEAT
    \ Load collision map
    _ML-RBUF _ML-RLEN @ S" cmap" _ML-FIND-KEY IF
        CBOR-TYPE CBOR-MT-BSTR = IF
            CBOR-NEXT-BSTR            ( addr len )
            _ML-MW @ _ML-MH @ CMAP-NEW ( addr len cmap )
            DUP _ML-WORLD @ _ML-O-CMAP + !
            -ROT                      ( cmap addr len )
            _ML-LOAD-CMAP-DATA
        ELSE
            CBOR-SKIP
        THEN
    THEN
    \ Load spawn points
    _ML-RBUF _ML-RLEN @ S" spawns" _ML-FIND-KEY IF
        CBOR-NEXT-UINT               ( n-spawns )
        DUP _ML-WORLD @ _ML-O-NSPAWNS + !
        DUP 0> IF
            DUP _ML-SPAWN-SZ * ALLOCATE
            0<> IF DROP ELSE
                _ML-WORLD @ _ML-O-SPAWNS + !
                _ML-WORLD @ _ML-O-NSPAWNS + @ 0 ?DO
                    \ Build key "SP0".."SP9"
                    83 _ML-LKEY C!        \ 'S'
                    80 _ML-LKEY 1+ C!     \ 'P'
                    I 48 + _ML-LKEY 2 + C!  \ '0'+i
                    _ML-RBUF _ML-RLEN @ _ML-LKEY 3 _ML-FIND-KEY IF
                        CBOR-TYPE CBOR-MT-ARRAY = IF
                            CBOR-NEXT-ARRAY DROP
                            \ Read id, x, y
                            CBOR-NEXT-UINT  \ id
                            _ML-WORLD @ _ML-O-SPAWNS + @
                            I _ML-SPAWN-SZ * + !
                            CBOR-NEXT-UINT  \ x
                            _ML-WORLD @ _ML-O-SPAWNS + @
                            I _ML-SPAWN-SZ * + 8 + !
                            CBOR-NEXT-UINT  \ y
                            _ML-WORLD @ _ML-O-SPAWNS + @
                            I _ML-SPAWN-SZ * + 16 + !
                        ELSE
                            CBOR-SKIP
                        THEN
                    THEN
                LOOP
            THEN
        ELSE
            DROP
        THEN
    THEN
    \ Load trigger zones
    _ML-RBUF _ML-RLEN @ S" triggers" _ML-FIND-KEY IF
        CBOR-NEXT-UINT               ( n-trigs )
        DUP _ML-WORLD @ _ML-O-NTRIGS + !
        DUP 0> IF
            DUP _ML-TRIG-SZ * ALLOCATE
            0<> IF DROP ELSE
                _ML-WORLD @ _ML-O-TRIGS + !
                _ML-WORLD @ _ML-O-NTRIGS + @ 0 ?DO
                    \ Build key "TR0".."TR9"
                    84 _ML-LKEY C!        \ 'T'
                    82 _ML-LKEY 1+ C!     \ 'R'
                    I 48 + _ML-LKEY 2 + C!  \ '0'+i
                    _ML-RBUF _ML-RLEN @ _ML-LKEY 3 _ML-FIND-KEY IF
                        CBOR-TYPE CBOR-MT-ARRAY = IF
                            CBOR-NEXT-ARRAY DROP
                            _ML-WORLD @ _ML-O-TRIGS + @
                            I _ML-TRIG-SZ * +
                            _ML-TR-ENTRY !
                            \ Read: id x y w h tag
                            CBOR-NEXT-UINT _ML-TR-ENTRY @ !
                            CBOR-NEXT-UINT _ML-TR-ENTRY @ 8 + !
                            CBOR-NEXT-UINT _ML-TR-ENTRY @ 16 + !
                            CBOR-NEXT-UINT _ML-TR-ENTRY @ 24 + !
                            CBOR-NEXT-UINT _ML-TR-ENTRY @ 32 + !
                            CBOR-NEXT-UINT _ML-TR-ENTRY @ 40 + !
                        ELSE
                            CBOR-SKIP
                        THEN
                    THEN
                LOOP
            THEN
        ELSE
            DROP
        THEN
    THEN
    _ML-WORLD @ ;

\ =====================================================================
\  §5 — Accessors
\ =====================================================================

: MLOAD-W  ( world -- w )  _ML-O-W + @ ;
: MLOAD-H  ( world -- h )  _ML-O-H + @ ;

: MLOAD-LAYER  ( world n -- tmap )
    8 * _ML-O-L0 + + @ ;

: MLOAD-CMAP  ( world -- cmap )
    _ML-O-CMAP + @ ;

\ MLOAD-SPAWN ( world id -- x y )
\   Find spawn point by id.  Returns 0 0 if not found.
VARIABLE _ML-SP-WORLD
VARIABLE _ML-SP-ID
: MLOAD-SPAWN  ( world id -- x y )
    _ML-SP-ID ! _ML-SP-WORLD !
    _ML-SP-WORLD @ _ML-O-NSPAWNS + @ 0 ?DO
        _ML-SP-WORLD @ _ML-O-SPAWNS + @
        I _ML-SPAWN-SZ * +           ( entry-addr )
        DUP @ _ML-SP-ID @ = IF
            DUP 8 + @ SWAP 16 + @    ( x y )
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 0 ;

\ MLOAD-TRIGGER ( world id -- x y w h callback-tag )
\   Find trigger zone by id.  Returns 0 0 0 0 0 if not found.
VARIABLE _ML-TR-WORLD
VARIABLE _ML-TR-ID
: MLOAD-TRIGGER  ( world id -- x y w h callback-tag )
    _ML-TR-ID ! _ML-TR-WORLD !
    _ML-TR-WORLD @ _ML-O-NTRIGS + @ 0 ?DO
        _ML-TR-WORLD @ _ML-O-TRIGS + @
        I _ML-TRIG-SZ * +            ( entry-addr )
        DUP @ _ML-TR-ID @ = IF
            _ML-TR-ENTRY !
            _ML-TR-ENTRY @  8 + @
            _ML-TR-ENTRY @ 16 + @
            _ML-TR-ENTRY @ 24 + @
            _ML-TR-ENTRY @ 32 + @
            _ML-TR-ENTRY @ 40 + @
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 0 0 0 0 ;

\ =====================================================================
\  §6 — Destructor
\ =====================================================================

: MLOAD-FREE  ( world -- )
    DUP _ML-O-L0 + @ DUP IF TMAP-FREE ELSE DROP THEN
    DUP _ML-O-L1 + @ DUP IF TMAP-FREE ELSE DROP THEN
    DUP _ML-O-L2 + @ DUP IF TMAP-FREE ELSE DROP THEN
    DUP _ML-O-L3 + @ DUP IF TMAP-FREE ELSE DROP THEN
    DUP _ML-O-CMAP + @ DUP IF CMAP-FREE ELSE DROP THEN
    DUP _ML-O-SPAWNS + @ DUP IF FREE ELSE DROP THEN
    DUP _ML-O-TRIGS + @ DUP IF FREE ELSE DROP THEN
    FREE ;

\ =====================================================================
\  §7 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _ml-guard

' MLOAD         CONSTANT _mload-xt
' MLOAD-LAYER   CONSTANT _mload-layer-xt
' MLOAD-CMAP    CONSTANT _mload-cmap-xt
' MLOAD-SPAWN   CONSTANT _mload-spawn-xt
' MLOAD-TRIGGER CONSTANT _mload-trigger-xt
' MLOAD-FREE    CONSTANT _mload-free-xt

: MLOAD         _mload-xt         _ml-guard WITH-GUARD ;
: MLOAD-LAYER   _mload-layer-xt   _ml-guard WITH-GUARD ;
: MLOAD-CMAP    _mload-cmap-xt    _ml-guard WITH-GUARD ;
: MLOAD-SPAWN   _mload-spawn-xt   _ml-guard WITH-GUARD ;
: MLOAD-TRIGGER _mload-trigger-xt _ml-guard WITH-GUARD ;
: MLOAD-FREE    _mload-free-xt    _ml-guard WITH-GUARD ;
[THEN] [THEN]
