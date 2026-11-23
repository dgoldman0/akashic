\ =====================================================================
\  akashic/game/save.f — Game Save / Load (CBOR through the VFS)
\ =====================================================================
\
\  A save is a CBOR map of text keys to integers, text and bytes, kept
\  in one file that a checked replacement writes.  A save context
\  gathers entries, GSAVE-WRITE encodes them and replaces the file the
\  replacement names, and GLOAD-OPEN reads the file back, checks every
\  byte of it and indexes its entries for lookup.
\
\  The file lives wherever the caller binds the replacement, as a game
\  binds it in its home:
\      S" /night.sav" home DUP PLACE-WRITABLE? repl PLACE-VREPL!
\  so a save lands on the volume that holds the home, ext4 in the
\  shipping form and MP64FS in the linked build, and a power cut during
\  a save leaves either the old file or the new one (vfs-replace.md).
\  A save of 2 to 16 KiB costs 1.25 to 1.35 s of processor time on the
\  user volume, so games save at explicit points.
\
\  The file is standard CBOR (RFC 8949), which any CBOR tool reads.  The
\  module writes and reads the part of CBOR a save uses, a definite map
\  of text keys to integers, text strings and byte strings, and holds
\  no state between calls.  Its reader checks every head and length
\  against the file's end, so a truncated, corrupt or foreign file is
\  refused before any lookup.
\
\  Buffers follow need: the entry buffer doubles as entries come, the
\  encoding's size is computed from the entries and written into a
\  buffer kept for the context's next save, and a load reads the file's
\  size first and allocates exactly that.  A context serves any number
\  of saves through GSAVE-RESET.  Keys are found through a hash table,
\  so a save's check for repeated keys and a load's lookups take time in
\  proportion to the entries.
\
\  Save Context (64 bytes):
\    +0   buf       Entry buffer
\    +8   cap       Its capacity
\    +16  used      Bytes of entries
\    +24  count     Entries
\    +32  enc       Encoding buffer, kept between saves
\    +40  enc-cap   Its capacity
\    +48  table     Key table for the check, kept between saves
\    +56  slots     Its slots
\
\  An entry in the buffer: a type byte, the key's length (a cell) and
\  its bytes, then an integer (a cell), or a length (a cell) and bytes.
\
\  Load Context (64 bytes + VFA-SCOPE-SIZE):
\    +0   data      The file's bytes
\    +8   len       Their count
\    +16  index     Entries of 40 bytes: key address, key length, type,
\                   then an integer, or an address and a length
\    +24  count     Entries
\    +32  status    The read's status, while the scope runs
\    +40  repl      The replacement read
\    +48  table     Key table over the entries
\    +56  mask      Its slots less one
\    +64  scope     Scoped VFS access for the read
\
\  Public API:
\    GSAVE-NEW    ( -- ctx )
\    GSAVE-RESET  ( ctx -- )
\    GSAVE-INT    ( ctx key-a key-u n -- )
\    GSAVE-STR    ( ctx key-a key-u str-a str-u -- )
\    GSAVE-BLOB   ( ctx key-a key-u addr len -- )
\    GSAVE-WRITE  ( ctx replacement -- status )
\    GSAVE-FREE   ( ctx -- )
\
\    GLOAD-OPEN   ( replacement -- ctx status )
\    GLOAD-INT    ( ctx key-a key-u -- n found? )
\    GLOAD-STR    ( ctx key-a key-u -- addr len found? )
\    GLOAD-BLOB   ( ctx key-a key-u -- addr len found? )
\    GLOAD-COUNT  ( ctx -- n )
\    GLOAD-CLOSE  ( ctx -- )
\
\  Statuses: GSAVE-S-OK, -MISSING, -CORRUPT, -IO, -READ-ONLY,
\  -RECOVERY, -INVALID, -NOMEM.
\
\  Prefix: GSAVE- / GLOAD- (public), _GSV- / _GLD- (internal)
\  Provider: akashic-game-save
\  Dependencies: utf8.f, vfs-replace.f, vfs-access.f

PROVIDED akashic-game-save

REQUIRE ../text/utf8.f
REQUIRE ../utils/fs/vfs-replace.f
REQUIRE ../utils/fs/vfs-access.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

0 CONSTANT GSAVE-S-OK
1 CONSTANT GSAVE-S-MISSING      \ no save file
2 CONSTANT GSAVE-S-CORRUPT      \ the file is no save, or a damaged one
3 CONSTANT GSAVE-S-IO           \ reading or writing failed; a save
                                \ left the old file
4 CONSTANT GSAVE-S-READ-ONLY    \ the replacement takes no writes
5 CONSTANT GSAVE-S-RECOVERY     \ an interrupted save awaits recovery
6 CONSTANT GSAVE-S-INVALID      \ a repeated key, or text not UTF-8
7 CONSTANT GSAVE-S-NOMEM        \ no memory for the encoding or file

0  CONSTANT _GSV-O-BUF
8  CONSTANT _GSV-O-CAP
16 CONSTANT _GSV-O-USED
24 CONSTANT _GSV-O-COUNT
32 CONSTANT _GSV-O-ENC
40 CONSTANT _GSV-O-ENCCAP
48 CONSTANT _GSV-O-TABLE
56 CONSTANT _GSV-O-TSLOTS
64 CONSTANT _GSV-DESC-SZ

0  CONSTANT _GLD-O-DATA
8  CONSTANT _GLD-O-LEN
16 CONSTANT _GLD-O-INDEX
24 CONSTANT _GLD-O-COUNT
32 CONSTANT _GLD-O-STATUS
40 CONSTANT _GLD-O-REPL
48 CONSTANT _GLD-O-TABLE
56 CONSTANT _GLD-O-MASK
64 CONSTANT _GLD-O-SCOPE
_GLD-O-SCOPE VFA-SCOPE-SIZE + CONSTANT _GLD-DESC-SZ

\ Entry types
0 CONSTANT _GSV-T-INT
1 CONSTANT _GSV-T-STR
2 CONSTANT _GSV-T-BLOB

\ An index entry: key address, key length, type, value, value length
40 CONSTANT _GLD-ENTRY-SZ

\ =====================================================================
\  §2 — Keys
\ =====================================================================
\
\  A save's check and a load's lookups find keys through a table of
\  slots with open addressing: a key's FNV-1a hash picks its first slot,
\  and a probe walks on through the next until it meets the key or an
\  empty slot.  A table has a power of two of slots, at least twice the
\  entries, so every probe meets an empty slot.  A slot holds a key's
\  address and length and the entry that owns it; entry 0 marks an
\  empty slot.

24 CONSTANT _GSV-SLOT-SZ

VARIABLE _GSV-TBL     \ the table a probe walks
VARIABLE _GSV-MASK    \ its slots less one

\ FNV-1a, 64-bit
: _GSV-HASH  ( a u -- h )
    0xCBF29CE484222325 -ROT 0 ?DO
        DUP I + C@ ROT XOR 0x100000001B3 * SWAP
    LOOP DROP ;

\ Slots for n entries: a power of two, at least 2n and at least 8
: _GSV-SLOTS  ( n -- slots )
    2* 8 BEGIN 2DUP > WHILE 2* REPEAT NIP ;

\ Make a table of slots current, and empty it.
: _GSV-TABLE!  ( table slots -- )
    DUP 1- _GSV-MASK !  _GSV-SLOT-SZ * OVER SWAP 0 FILL  _GSV-TBL ! ;

\ The slot that holds the key, or the empty slot where it goes
: _GSV-PROBE  ( key-a key-u -- slot )
    2DUP _GSV-HASH
    BEGIN
        _GSV-MASK @ AND DUP _GSV-SLOT-SZ * _GSV-TBL @ +   ( ka ku i slot )
        DUP 16 + @ 0= IF NIP NIP NIP EXIT THEN
        DUP @ OVER CELL+ @ 5 PICK 5 PICK COMPARE 0= IF NIP NIP NIP EXIT THEN
        DROP 1+
    AGAIN ;

\ Put a key and its entry in the current table; false when the key is
\ there already
: _GSV-INSERT  ( key-a key-u entry -- flag )
    >R 2DUP _GSV-PROBE                            ( ka ku slot  R: entry )
    DUP 16 + @ IF DROP 2DROP R> DROP FALSE EXIT THEN
    TUCK CELL+ !  TUCK !  R> SWAP 16 + !  TRUE ;

\ =====================================================================
\  §3 — Save Context
\ =====================================================================

: GSAVE-NEW  ( -- ctx )
    _GSV-DESC-SZ ALLOCATE
    0<> ABORT" GSAVE-NEW: desc alloc"
    DUP _GSV-DESC-SZ 0 FILL
    256 ALLOCATE 0<> ABORT" GSAVE-NEW: buf alloc"
    OVER _GSV-O-BUF + !
    256 OVER _GSV-O-CAP + ! ;

\ GSAVE-RESET ( ctx -- )  Forget the entries; keep the buffers.
: GSAVE-RESET  ( ctx -- )
    0 OVER _GSV-O-USED + !  0 SWAP _GSV-O-COUNT + ! ;

: GSAVE-FREE  ( ctx -- )
    DUP _GSV-O-BUF + @ FREE
    DUP _GSV-O-ENC + @ FREE
    DUP _GSV-O-TABLE + @ FREE
    FREE ;

\ Room for n more bytes of entries, doubling the buffer as needed.
: _GSV-ROOM  ( ctx n -- )
    OVER _GSV-O-USED + @ +                        ( ctx need )
    OVER _GSV-O-CAP + @ 2DUP <= IF 2DROP DROP EXIT THEN
    BEGIN 2* 2DUP > 0= UNTIL NIP                  ( ctx cap )
    OVER _GSV-O-BUF + @ OVER RESIZE
    0<> ABORT" GSAVE: entry buffer alloc"         ( ctx cap buf )
    2 PICK _GSV-O-BUF + !
    SWAP _GSV-O-CAP + ! ;

\ The address the next entry's bytes go to
: _GSV-HERE  ( ctx -- addr )
    DUP _GSV-O-BUF + @ SWAP _GSV-O-USED + @ + ;

\ Append a byte, a cell, or bytes.
: _GSV-C,  ( ctx byte -- )
    OVER _GSV-HERE C!  1 SWAP _GSV-O-USED + +! ;

: _GSV-CELL,  ( ctx n -- )
    OVER _GSV-HERE !  8 SWAP _GSV-O-USED + +! ;

: _GSV-BYTES,  ( ctx addr len -- )
    >R OVER _GSV-HERE R@ CMOVE  R> SWAP _GSV-O-USED + +! ;

\ =====================================================================
\  §4 — Save: Entries
\ =====================================================================

\ Make room for an entry whose value takes extra bytes, and write its
\ type and key.
: _GSV-KEY,  ( ctx key-a key-u type extra -- ctx )
    2 PICK + 9 +                                  ( ctx ka ku type need )
    4 PICK SWAP _GSV-ROOM                         ( ctx ka ku type )
    3 PICK SWAP _GSV-C,
    2 PICK OVER _GSV-CELL,
    2 PICK -ROT _GSV-BYTES,
    1 OVER _GSV-O-COUNT + +! ;

: GSAVE-INT  ( ctx key-a key-u n -- )
    >R _GSV-T-INT 8 _GSV-KEY, R> _GSV-CELL, ;

: GSAVE-STR  ( ctx key-a key-u str-a str-u -- )
    2>R _GSV-T-STR R@ 8 + _GSV-KEY, DUP R@ _GSV-CELL, 2R> _GSV-BYTES, ;

: GSAVE-BLOB  ( ctx key-a key-u addr len -- )
    2>R _GSV-T-BLOB R@ 8 + _GSV-KEY, DUP R@ _GSV-CELL, 2R> _GSV-BYTES, ;

\ =====================================================================
\  §5 — Save: Checking, Encoding & Writing
\ =====================================================================

: _GSV-ENTRY-KEY  ( entry -- key-a key-u )
    1+ DUP CELL+ SWAP @ ;

\ The entry's value, after its key
: _GSV-ENTRY-VALUE  ( entry -- addr )
    _GSV-ENTRY-KEY + ;

: _GSV-ENTRY-NEXT  ( entry -- entry' )
    DUP _GSV-ENTRY-VALUE SWAP C@ _GSV-T-INT = IF CELL+ EXIT THEN
    DUP @ + CELL+ ;

\ A key table for n entries, kept in the context and made current
: _GSV-TABLE-ROOM  ( ctx n -- ior )
    _GSV-SLOTS                                    ( ctx slots )
    OVER _GSV-O-TSLOTS + @ OVER >= IF
        DROP DUP _GSV-O-TABLE + @ SWAP _GSV-O-TSLOTS + @ _GSV-TABLE! 0 EXIT
    THEN
    OVER _GSV-O-TABLE + @ FREE
    0 2 PICK _GSV-O-TABLE + !  0 2 PICK _GSV-O-TSLOTS + !
    DUP _GSV-SLOT-SZ * ALLOCATE IF DROP 2DROP -1 EXIT THEN   ( ctx slots table )
    2DUP SWAP _GSV-TABLE!
    2 PICK _GSV-O-TABLE + !  SWAP _GSV-O-TSLOTS + ! 0 ;

\ Is any key repeated, or any key or text not UTF-8?
: _GSV-CHECK  ( ctx -- status )
    DUP DUP _GSV-O-COUNT + @ _GSV-TABLE-ROOM IF DROP GSAVE-S-NOMEM EXIT THEN
    DUP _GSV-O-BUF + @ SWAP _GSV-O-COUNT + @      ( entry n )
    0 ?DO
        DUP _GSV-ENTRY-KEY 2DUP UTF8-VALID? 0= IF
            2DROP DROP UNLOOP GSAVE-S-INVALID EXIT
        THEN
        2 PICK _GSV-INSERT 0= IF DROP UNLOOP GSAVE-S-INVALID EXIT THEN
        DUP C@ _GSV-T-STR = IF
            DUP _GSV-ENTRY-VALUE DUP CELL+ SWAP @ UTF8-VALID? 0= IF
                DROP UNLOOP GSAVE-S-INVALID EXIT
            THEN
        THEN
        _GSV-ENTRY-NEXT
    LOOP
    DROP GSAVE-S-OK ;

\ ---------------------------------------------------------------------
\  Writing CBOR.  A head is a byte of major type and additional
\  information, then 0, 1, 2, 4 or 8 bytes of argument, big-endian, the
\  fewest that hold it.  Arguments here lie in 0 .. 2^63-1: a negative
\  integer n goes out as CBOR's negative form, whose argument is -1-n.
\ ---------------------------------------------------------------------

\ Bytes a head takes for argument n
: _GSV-HEAD-SIZE  ( n -- bytes )
    DUP 24 < IF DROP 1 EXIT THEN
    DUP 256 < IF DROP 2 EXIT THEN
    DUP 65536 < IF DROP 3 EXIT THEN
    4294967296 < IF 5 ELSE 9 THEN ;

\ k bytes of n at addr, big-endian
: _GSV-BE!  ( n addr k -- )
    BEGIN DUP 0> WHILE
        1-  2 PICK 255 AND  2 PICK 2 PICK + C!
        ROT 8 RSHIFT -ROT
    REPEAT
    DROP 2DROP ;

\ A head at p; the address after it
: _GSV-HEAD!  ( p major n -- p' )
    SWAP 5 LSHIFT OVER _GSV-HEAD-SIZE             ( p n mt size )
    DUP 1 = IF DROP OR OVER C! 1+ EXIT THEN
    DUP CASE 2 OF 24 ENDOF 3 OF 25 ENDOF 5 OF 26 ENDOF >R 27 R> ENDCASE
    ROT OR 3 PICK C!                              ( p n size )
    ROT 2DUP + >R                                 ( n size p  R: p' )
    1+ SWAP 1- _GSV-BE! R> ;

\ A text (major 3) or byte (major 2) string at p
: _GSV-STR!  ( p major addr len -- p' )
    2>R R@ _GSV-HEAD!
    2R> >R OVER R@ CMOVE R> + ;

\ An integer at p
: _GSV-INT!  ( p n -- p' )
    DUP 0< IF INVERT 1 ELSE 0 THEN SWAP _GSV-HEAD! ;

\ Bytes an entry takes in the file
: _GSV-ENTRY-SIZE  ( entry -- n )
    DUP _GSV-ENTRY-KEY NIP DUP _GSV-HEAD-SIZE +   ( entry n )
    OVER _GSV-ENTRY-VALUE ROT C@ _GSV-T-INT = IF
        @ DUP 0< IF INVERT THEN _GSV-HEAD-SIZE +
    ELSE
        @ DUP _GSV-HEAD-SIZE + +
    THEN ;

\ An entry at p: its key, then its value
: _GSV-ENTRY!  ( p entry -- p' )
    TUCK _GSV-ENTRY-KEY 3 -ROT _GSV-STR!          ( entry p' )
    OVER _GSV-ENTRY-VALUE ROT C@ CASE             ( p v )
        _GSV-T-INT OF @ _GSV-INT! ENDOF
        _GSV-T-STR OF 3 SWAP DUP CELL+ SWAP @ _GSV-STR! ENDOF
        >R 2 SWAP DUP CELL+ SWAP @ _GSV-STR! R>
    ENDCASE ;

\ The size of the file the entries make
: _GSV-SIZE  ( ctx -- n )
    DUP _GSV-O-COUNT + @ DUP _GSV-HEAD-SIZE SWAP  ( ctx size n )
    ROT _GSV-O-BUF + @ SWAP                       ( size entry n )
    0 ?DO DUP _GSV-ENTRY-SIZE ROT + SWAP _GSV-ENTRY-NEXT LOOP
    DROP ;

\ The entries as a CBOR map at p
: _GSV-ENCODE  ( ctx p -- p' )
    5 2 PICK _GSV-O-COUNT + @ _GSV-HEAD!          ( ctx p )
    SWAP DUP _GSV-O-BUF + @ SWAP _GSV-O-COUNT + @ ( p entry n )
    0 ?DO TUCK _GSV-ENTRY! SWAP _GSV-ENTRY-NEXT LOOP
    DROP ;

\ An encoding buffer of at least n bytes, kept in the context.  Its
\ capacity is a power of two from 256, so a save that grows a little
\ at a time leaves few holes of different sizes in the heap.
: _GSV-ENC-ROOM  ( ctx n -- ior )
    OVER _GSV-O-ENCCAP + @ OVER >= IF 2DROP 0 EXIT THEN
    256 BEGIN 2DUP > WHILE 2* REPEAT NIP          ( ctx cap )
    OVER _GSV-O-ENC + @ FREE
    0 2 PICK _GSV-O-ENC + !  0 2 PICK _GSV-O-ENCCAP + !
    DUP ALLOCATE IF DROP 2DROP -1 EXIT THEN       ( ctx cap buf )
    2 PICK _GSV-O-ENC + !  SWAP _GSV-O-ENCCAP + ! 0 ;

\ A replacement's answer as a save's status.  A committed save whose
\ backup remains is a save; GSAVE-WRITE recovers to remove the backup.
: _GSV-WRITE-STATUS  ( vrepl-status -- status )
    CASE
        VREPL-S-OK                OF GSAVE-S-OK ENDOF
        VREPL-S-COMMITTED-CLEANUP OF GSAVE-S-OK ENDOF
        VREPL-S-ROLLED-BACK       OF GSAVE-S-IO ENDOF
        VREPL-S-IO                OF GSAVE-S-IO ENDOF
        VREPL-S-CONFLICT          OF GSAVE-S-IO ENDOF
        VREPL-S-BUSY              OF GSAVE-S-IO ENDOF
        VREPL-S-READ-ONLY         OF GSAVE-S-READ-ONLY ENDOF
        VREPL-S-INVALID           OF GSAVE-S-INVALID ENDOF
        VREPL-S-NOMEM             OF GSAVE-S-NOMEM ENDOF
        >R GSAVE-S-RECOVERY R>
    ENDCASE ;

\ GSAVE-WRITE ( ctx replacement -- status )
\   Encode the entries and replace the file the replacement names.
: GSAVE-WRITE  ( ctx replacement -- status )
    OVER _GSV-CHECK ?DUP IF NIP NIP EXIT THEN
    OVER _GSV-SIZE                                ( ctx repl size )
    2 PICK OVER _GSV-ENC-ROOM IF DROP 2DROP GSAVE-S-NOMEM EXIT THEN
    2 PICK DUP _GSV-O-ENC + @ _GSV-ENCODE DROP
    2 PICK _GSV-O-ENC + @ SWAP ROT                ( ctx enc size repl )
    DUP >R VREPL-REPLACE                          ( ctx vstatus  R: repl )
    DUP VREPL-S-COMMITTED-CLEANUP = IF R@ VREPL-RECOVER DROP THEN
    R> DROP _GSV-WRITE-STATUS NIP ;

\ =====================================================================
\  §6 — Load: A Checked Cursor
\ =====================================================================
\
\  The reader takes only the forms a save writes: heads of one to nine
\  bytes, a map, text and byte strings, and integers that fit a signed
\  cell.  Every head and string is checked against the file's end
\  before it is read.

\ The bytes of a head's argument after its first byte, or -1
: _GLD-ARG-BYTES  ( info -- n|-1 )
    DUP 24 < IF DROP 0 EXIT THEN
    CASE
        24 OF 1 ENDOF
        25 OF 2 ENDOF
        26 OF 4 ENDOF
        27 OF 8 ENDOF
        -1 SWAP
    ENDCASE ;

\ n bytes at addr as a big-endian number
: _GLD-BE  ( addr n -- value )
    0 -ROT 0 ?DO DUP I + C@ ROT 8 LSHIFT OR SWAP LOOP DROP ;

\ The head at p: its major type, its argument and the address after it
: _GLD-HEAD  ( p end -- major arg p' true | false )
    2DUP U< 0= IF 2DROP FALSE EXIT THEN
    OVER C@ 31 AND _GLD-ARG-BYTES                 ( p end n )
    DUP 0< IF DROP 2DROP FALSE EXIT THEN
    ROT 2DUP + 1+ 3 PICK SWAP U< IF DROP 2DROP FALSE EXIT THEN
    DUP C@ 5 RSHIFT >R                            ( end n p  R: major )
    OVER 0= IF DUP C@ 31 AND ELSE DUP 1+ 2 PICK _GLD-BE THEN
    -ROT + 1+                                     ( end arg p' )
    ROT DROP R> -ROT TRUE ;

\ A string of major type want at p: its bytes and the address after it
: _GLD-STRING  ( p end want -- addr len p' true | false )
    >R DUP >R _GLD-HEAD 0= IF R> R> 2DROP FALSE EXIT THEN
    ROT R> SWAP R> <> IF DROP 2DROP FALSE EXIT THEN   ( arg p' end )
    OVER - 2 PICK U< IF 2DROP FALSE EXIT THEN
    SWAP 2DUP + TRUE ;

\ A value at p: its type, an integer and 0, or an address and a length
: _GLD-VALUE  ( p end -- type v1 v2 p' true | false )
    2DUP U< 0= IF 2DROP FALSE EXIT THEN
    OVER C@ 5 RSHIFT CASE
        0 OF
            _GLD-HEAD 0= IF FALSE EXIT THEN
            OVER 0< IF DROP 2DROP FALSE EXIT THEN
            ROT DROP >R _GSV-T-INT SWAP 0 R> TRUE
        ENDOF
        1 OF
            _GLD-HEAD 0= IF FALSE EXIT THEN
            OVER 0< IF DROP 2DROP FALSE EXIT THEN
            ROT DROP >R INVERT _GSV-T-INT SWAP 0 R> TRUE
        ENDOF
        2 OF
            2 _GLD-STRING 0= IF FALSE EXIT THEN
            >R _GSV-T-BLOB -ROT R> TRUE
        ENDOF
        3 OF
            3 _GLD-STRING 0= IF FALSE EXIT THEN
            >R 2DUP UTF8-VALID? 0= IF R> DROP 2DROP FALSE EXIT THEN
            _GSV-T-STR -ROT R> TRUE
        ENDOF
        >R 2DROP FALSE R>
    ENDCASE ;

\ One key and its value at p, written into an index entry
: _GLD-PAIR  ( entry p end -- p' true | false )
    TUCK 3 _GLD-STRING 0= IF 2DROP FALSE EXIT THEN    ( entry end ka ku p' )
    2 PICK 2 PICK UTF8-VALID? 0= IF 2DROP 2DROP DROP FALSE EXIT THEN
    -ROT 4 PICK CELL+ !  3 PICK !                 ( entry end p' )
    SWAP _GLD-VALUE 0= IF DROP FALSE EXIT THEN    ( entry type v1 v2 p' )
    >R  3 PICK 4 CELLS + !  2 PICK 3 CELLS + !  SWAP 2 CELLS + !
    R> TRUE ;

\ The load's key table over its entries; corrupt when a key repeats
: _GLD-TABLE  ( ctx -- status )
    DUP _GLD-O-COUNT + @ _GSV-SLOTS               ( ctx slots )
    DUP _GSV-SLOT-SZ * ALLOCATE IF 2DROP DROP GSAVE-S-NOMEM EXIT THEN
    2 PICK _GLD-O-TABLE + !                       ( ctx slots )
    DUP 1- 2 PICK _GLD-O-MASK + !
    OVER _GLD-O-TABLE + @ SWAP _GSV-TABLE!        ( ctx )
    DUP _GLD-O-INDEX + @ SWAP _GLD-O-COUNT + @ 0 ?DO   ( index )
        DUP I _GLD-ENTRY-SZ * +                   ( index entry )
        DUP @ OVER CELL+ @ ROT _GSV-INSERT 0= IF
            DROP UNLOOP GSAVE-S-CORRUPT EXIT
        THEN
    LOOP
    DROP GSAVE-S-OK ;

\ Check the whole file and index its entries.
: _GLD-PARSE  ( ctx -- status )
    DUP _GLD-O-DATA + @ DUP 2 PICK _GLD-O-LEN + @ +   ( ctx p end )
    TUCK _GLD-HEAD 0= IF 2DROP GSAVE-S-CORRUPT EXIT THEN   ( ctx end major n p )
    ROT 5 <> IF 2DROP 2DROP GSAVE-S-CORRUPT EXIT THEN      ( ctx end n p )
    \ every pair takes two bytes at least
    2 PICK OVER - 2/ 2 PICK U< IF 2DROP 2DROP GSAVE-S-CORRUPT EXIT THEN
    OVER ?DUP IF
        _GLD-ENTRY-SZ * ALLOCATE IF DROP 2DROP 2DROP GSAVE-S-NOMEM EXIT THEN
    ELSE
        0
    THEN
    4 PICK _GLD-O-INDEX + !
    OVER 4 PICK _GLD-O-COUNT + !                  ( ctx end n p )
    SWAP 0 ?DO                                    ( ctx end p )
        2 PICK _GLD-O-INDEX + @ I _GLD-ENTRY-SZ * +
        SWAP 2 PICK _GLD-PAIR 0= IF 2DROP UNLOOP GSAVE-S-CORRUPT EXIT THEN
    LOOP
    <> IF DROP GSAVE-S-CORRUPT EXIT THEN          ( ctx )
    _GLD-TABLE ;

\ =====================================================================
\  §7 — Load: Reading the File
\ =====================================================================

\ A recovery's answer as a load's status: 0 to read on.  On a place
\ bound for reading, an interrupted save that only a writable place can
\ settle answers GSAVE-S-READ-ONLY.
: _GLD-RECOVER-STATUS  ( vrepl-status -- status )
    CASE
        VREPL-S-OK                OF GSAVE-S-OK ENDOF
        VREPL-S-ROLLED-BACK       OF GSAVE-S-OK ENDOF
        VREPL-S-COMMITTED-CLEANUP OF GSAVE-S-OK ENDOF
        VREPL-S-INVALID           OF GSAVE-S-INVALID ENDOF
        VREPL-S-IO                OF GSAVE-S-IO ENDOF
        VREPL-S-BUSY              OF GSAVE-S-IO ENDOF
        VREPL-S-READ-ONLY         OF GSAVE-S-READ-ONLY ENDOF
        VREPL-S-NOMEM             OF GSAVE-S-NOMEM ENDOF
        >R GSAVE-S-RECOVERY R>
    ENDCASE ;

\ The load the scoped read below fills, for the read's duration
VARIABLE _GLD-READING

\ Read the replacement's target: its size, then exactly that.
: _GLD-READ-BODY  ( -- )
    _GLD-READING @                                ( ctx )
    DUP _GLD-O-REPL + @ VREPL-TARGET$ VFS-FF-READ
    3 PICK _GLD-O-SCOPE + VFA-SCOPE-OPEN?         ( ctx fd ior )
    ?DUP IF
        NIP VFS-IOR-REASON VFS-R-NOENT = IF GSAVE-S-MISSING ELSE GSAVE-S-IO THEN
        SWAP _GLD-O-STATUS + ! EXIT
    THEN
    DUP VFA-FILE-SIZE? IF 2DROP GSAVE-S-IO SWAP _GLD-O-STATUS + ! EXIT THEN
    ?DUP 0= IF DROP GSAVE-S-CORRUPT SWAP _GLD-O-STATUS + ! EXIT THEN
    DUP ALLOCATE IF
        2DROP DROP GSAVE-S-NOMEM SWAP _GLD-O-STATUS + ! EXIT
    THEN                                          ( ctx fd size buf )
    3 PICK _GLD-O-DATA + !
    DUP 3 PICK _GLD-O-LEN + !                     ( ctx fd size )
    2 PICK _GLD-O-DATA + @ SWAP ROT VFA-READ-FILE?   ( ctx len ior )
    IF DROP GSAVE-S-IO SWAP _GLD-O-STATUS + ! EXIT THEN
    OVER _GLD-O-LEN + @ <> IF GSAVE-S-IO SWAP _GLD-O-STATUS + ! EXIT THEN
    GSAVE-S-OK SWAP _GLD-O-STATUS + ! ;

: GLOAD-CLOSE  ( ctx -- )
    DUP _GLD-O-TABLE + @ FREE
    DUP _GLD-O-INDEX + @ FREE
    DUP _GLD-O-DATA + @ FREE
    FREE ;

\ GLOAD-OPEN ( replacement -- ctx status )
\   Recover any interrupted save, read the file the replacement names
\   and check it whole; the context is 0 unless the status is OK.
: GLOAD-OPEN  ( replacement -- ctx status )
    DUP VREPL-RECOVER _GLD-RECOVER-STATUS ?DUP IF NIP 0 SWAP EXIT THEN
    _GLD-DESC-SZ ALLOCATE IF 2DROP 0 GSAVE-S-NOMEM EXIT THEN   ( repl ctx )
    DUP _GLD-DESC-SZ 0 FILL
    TUCK _GLD-O-REPL + !                          ( ctx )
    DUP _GLD-O-REPL + @ VREPL.VFS @ OVER _GLD-O-SCOPE + VFA-SCOPE-INIT IF
        GLOAD-CLOSE 0 GSAVE-S-IO EXIT
    THEN
    DUP _GLD-READING !
    ['] _GLD-READ-BODY OVER _GLD-O-SCOPE + VFA-SCOPE-CALL OR
    IF GSAVE-S-IO ELSE DUP _GLD-O-STATUS + @ THEN     ( ctx status )
    ?DUP IF SWAP GLOAD-CLOSE 0 SWAP EXIT THEN
    DUP _GLD-PARSE ?DUP IF SWAP GLOAD-CLOSE 0 SWAP EXIT THEN
    GSAVE-S-OK ;

\ =====================================================================
\  §8 — Load: Lookup
\ =====================================================================

\ The index entry for a key, or 0
: _GLD-FIND  ( ctx key-a key-u -- entry|0 )
    ROT DUP _GLD-O-TABLE + @ _GSV-TBL !  _GLD-O-MASK + @ _GSV-MASK !
    _GSV-PROBE 16 + @ ;

\ The entry for a key when it holds a value of this type, or 0
: _GLD-TYPED  ( ctx key-a key-u type -- entry|0 )
    >R _GLD-FIND DUP IF DUP 2 CELLS + @ R@ <> IF DROP 0 THEN THEN R> DROP ;

: GLOAD-INT  ( ctx key-a key-u -- n found? )
    _GSV-T-INT _GLD-TYPED ?DUP IF 3 CELLS + @ TRUE ELSE 0 FALSE THEN ;

: GLOAD-STR  ( ctx key-a key-u -- addr len found? )
    _GSV-T-STR _GLD-TYPED ?DUP IF
        DUP 3 CELLS + @ SWAP 4 CELLS + @ TRUE
    ELSE
        0 0 FALSE
    THEN ;

: GLOAD-BLOB  ( ctx key-a key-u -- addr len found? )
    _GSV-T-BLOB _GLD-TYPED ?DUP IF
        DUP 3 CELLS + @ SWAP 4 CELLS + @ TRUE
    ELSE
        0 0 FALSE
    THEN ;

: GLOAD-COUNT  ( ctx -- n )  _GLD-O-COUNT + @ ;

\ =====================================================================
\  §9 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _gsv-guard

' GSAVE-NEW   CONSTANT _gsave-new-xt
' GSAVE-RESET CONSTANT _gsave-reset-xt
' GSAVE-INT   CONSTANT _gsave-int-xt
' GSAVE-STR   CONSTANT _gsave-str-xt
' GSAVE-BLOB  CONSTANT _gsave-blob-xt
' GSAVE-WRITE CONSTANT _gsave-write-xt
' GSAVE-FREE  CONSTANT _gsave-free-xt
' GLOAD-OPEN  CONSTANT _gload-open-xt
' GLOAD-INT   CONSTANT _gload-int-xt
' GLOAD-STR   CONSTANT _gload-str-xt
' GLOAD-BLOB  CONSTANT _gload-blob-xt
' GLOAD-CLOSE CONSTANT _gload-close-xt

: GSAVE-NEW   _gsave-new-xt   _gsv-guard WITH-GUARD ;
: GSAVE-RESET _gsave-reset-xt _gsv-guard WITH-GUARD ;
: GSAVE-INT   _gsave-int-xt   _gsv-guard WITH-GUARD ;
: GSAVE-STR   _gsave-str-xt   _gsv-guard WITH-GUARD ;
: GSAVE-BLOB  _gsave-blob-xt  _gsv-guard WITH-GUARD ;
: GSAVE-WRITE _gsave-write-xt _gsv-guard WITH-GUARD ;
: GSAVE-FREE  _gsave-free-xt  _gsv-guard WITH-GUARD ;
: GLOAD-OPEN  _gload-open-xt  _gsv-guard WITH-GUARD ;
: GLOAD-INT   _gload-int-xt   _gsv-guard WITH-GUARD ;
: GLOAD-STR   _gload-str-xt   _gsv-guard WITH-GUARD ;
: GLOAD-BLOB  _gload-blob-xt  _gsv-guard WITH-GUARD ;
: GLOAD-CLOSE _gload-close-xt _gsv-guard WITH-GUARD ;
[THEN] [THEN]
