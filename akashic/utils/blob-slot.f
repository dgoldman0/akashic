\ =====================================================================
\  blob-slot.f - Bytes of any length held by fixed-size records
\ =====================================================================
\  A blob slot is two cells of a record: the address of bytes the record
\  owns, and their length; an empty slot is zero and zero.  Slots let a
\  store of fixed-size records (record-table.f) hold bytes of any length.
\
\  In a file a slot holds the offset of its bytes in a blob region
\  instead.  The region holds the bytes of each nonempty slot, in the
\  order the store puts them, each zero-padded to a cell, and nothing
\  else.  A cursor walks the region.  Writing a file puts each slot's
\  bytes at the cursor and sets the slot to their offset.  Reading one
\  checks that each slot names exactly the next part, so a damaged file
\  cannot reach outside the region or hide bytes in it.  Taking a file's
\  records then gives each slot its own copy of its bytes.
\
\  Every word wipes the bytes it gives up.  Slots are caller-serialized,
\  and the module has no global state.
\
\  Public API:
\    BSLOT$              ( slot -- address length )
\    BSLOT-FREE          ( slot -- )
\    BSLOT!              ( address length slot -- status )
\    BSLOT-PADDED        ( length -- bytes )
\    BSLOT-CURSOR-INIT   ( region region-u cursor -- )
\    BSLOT-AT@           ( cursor -- offset )
\    BSLOT-NEXT          ( slot cursor -- address length )
\    BSLOT-PUT           ( slot cursor -- )
\    BSLOT-OWN           ( region slot -- status )
\  Over the slots at OFFSET of a record table's records:
\    BSLOT-TABLE-U       ( table element-u offset -- bytes )
\    BSLOT-PUT-RECORDS   ( records n element-u offset cursor -- )
\    BSLOT-TABLE-FREE    ( table element-u offset -- )
\    BSLOT-TABLE-FORGET  ( from table element-u offset -- )
\    BSLOT-TABLE-OWN     ( region table element-u offset -- status )
\ =====================================================================

PROVIDED akashic-blob-slot

REQUIRE record-table.f

0 CONSTANT BSLOT-S-OK
1 CONSTANT BSLOT-S-NOMEM

16 CONSTANT BSLOT-SIZE

: BSLOT$  ( slot -- address length ) DUP @ SWAP 8 + @ ;

\ Wipes and frees a slot's bytes; the slot is empty.
: BSLOT-FREE  ( slot -- )
    DUP @ ?DUP IF
        OVER 8 + @ OVER SWAP 0 FILL FREE
    THEN
    BSLOT-SIZE 0 FILL ;

\ Sets a slot to its own copy of LENGTH bytes at ADDRESS, which may be the
\ slot's own.  Zero bytes empty it.
: BSLOT!  ( address length slot -- status )
    OVER 0= IF NIP NIP BSLOT-FREE BSLOT-S-OK EXIT THEN
    OVER ALLOCATE IF DROP DROP 2DROP BSLOT-S-NOMEM EXIT THEN   ( a u slot new )
    3 PICK OVER 4 PICK MOVE
    OVER BSLOT-FREE
    OVER !
    8 + ! DROP BSLOT-S-OK ;

\ The bytes LENGTH bytes take in a region, padded to a cell.
: BSLOT-PADDED  ( length -- bytes ) 7 + -8 AND ;

\ ---------------------------------------------------------------------
\  The region
\ ---------------------------------------------------------------------

\ A cursor: the region's address and size, and the offset of its next
\ part, or -1 once a slot was out of place.
24 CONSTANT BSLOT-CURSOR-SIZE
: _BSC.BASE  ( cursor -- a ) ;
: _BSC.SIZE  ( cursor -- a ) 8 + ;
: _BSC.AT    ( cursor -- a ) 16 + ;

: BSLOT-CURSOR-INIT  ( region region-u cursor -- )
    TUCK _BSC.SIZE ! TUCK _BSC.BASE ! 0 SWAP _BSC.AT ! ;

\ The offset of the cursor's next part, or -1.
: BSLOT-AT@  ( cursor -- offset ) _BSC.AT @ ;

: _BSLOT-ZERO?  ( address u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

\ The bytes the file slot at SLOT names in the cursor's region, when they
\ are its next part and their padding is zero; the cursor moves past
\ them.  Otherwise 0 0, and the cursor's offset becomes -1.
: BSLOT-NEXT  ( slot cursor -- address length )
    >R
    R@ _BSC.AT @ 0< IF DROP R> DROP 0 0 EXIT THEN
    DUP 8 + @ ?DUP 0= IF
        @ IF -1 R@ _BSC.AT ! THEN R> DROP 0 0 EXIT
    THEN                                     ( slot u )
    OVER @ R@ _BSC.AT @ <> OVER R@ _BSC.SIZE @ U> OR IF
        2DROP -1 R> _BSC.AT ! 0 0 EXIT
    THEN
    NIP                                      ( u )
    DUP BSLOT-PADDED R@ _BSC.AT @ + DUP R@ _BSC.SIZE @ U> IF
        2DROP -1 R> _BSC.AT ! 0 0 EXIT
    THEN                                     ( u end )
    R@ _BSC.BASE @ R@ _BSC.AT @ + 2 PICK +
    OVER R@ _BSC.AT @ - 3 PICK -
    _BSLOT-ZERO? 0= IF 2DROP -1 R> _BSC.AT ! 0 0 EXIT THEN
    R@ _BSC.BASE @ R@ _BSC.AT @ + ROT
    ROT R> _BSC.AT ! ;

\ Puts the bytes of SLOT, a written record's, at the cursor, zero-padded,
\ and sets the slot to their offset; the cursor moves past them.  An
\ empty slot stays empty.
: BSLOT-PUT  ( slot cursor -- )
    >R
    DUP 8 + @ 0= IF 0 SWAP ! R> DROP EXIT THEN
    DUP @ R@ _BSC.BASE @ R@ _BSC.AT @ + 2 PICK 8 + @ MOVE
    DUP 8 + @ R@ _BSC.BASE @ R@ _BSC.AT @ + OVER +        ( slot u pad-start )
    SWAP DUP BSLOT-PADDED SWAP - 0 FILL
    R@ _BSC.AT @ OVER !
    8 + @ BSLOT-PADDED R> _BSC.AT +! ;

\ Gives SLOT, which holds the offset of its bytes in REGION, its own copy
\ of them.  A slot that cannot get memory keeps its offset.
: BSLOT-OWN  ( region slot -- status )
    DUP 8 + @ 0= IF 2DROP BSLOT-S-OK EXIT THEN
    DUP 8 + @ ALLOCATE IF DROP 2DROP BSLOT-S-NOMEM EXIT THEN   ( region slot new )
    ROT 2 PICK @ +                           ( slot new source )
    OVER 3 PICK 8 + @ MOVE
    SWAP ! BSLOT-S-OK ;

\ ---------------------------------------------------------------------
\  A table's slots
\ ---------------------------------------------------------------------

\ The region bytes the slots at OFFSET of TABLE's records take.
: BSLOT-TABLE-U  ( table element-u offset -- bytes )
    0 3 PICK RTAB-COUNT@ 0 ?DO               ( table u off bytes )
        I 4 PICK 4 PICK RTAB-NTH 2 PICK + 8 + @ BSLOT-PADDED +
    LOOP
    NIP NIP NIP ;

\ Puts the slots at OFFSET of N written records at RECORDS.
: BSLOT-PUT-RECORDS  ( records n element-u offset cursor -- )
    3 ROLL 0 ?DO                             ( records u off cursor )
        3 PICK I 4 PICK * + 2 PICK + OVER BSLOT-PUT
    LOOP
    2DROP 2DROP ;

\ Frees the slots at OFFSET of TABLE's records; the table stays.
: BSLOT-TABLE-FREE  ( table element-u offset -- )
    2 PICK RTAB-COUNT@ 0 ?DO
        I 3 PICK 3 PICK RTAB-NTH OVER + BSLOT-FREE
    LOOP
    2DROP DROP ;

\ Empties the slots at OFFSET of TABLE's records from index FROM on: they
\ hold offsets that no record owns.
: BSLOT-TABLE-FORGET  ( from table element-u offset -- )
    2 PICK RTAB-COUNT@ 4 ROLL ?DO            ( table u off )
        I 3 PICK 3 PICK RTAB-NTH OVER + BSLOT-SIZE 0 FILL
    LOOP
    2DROP DROP ;

\ Gives the slots at OFFSET of TABLE's records, which hold offsets in
\ REGION, their own copies.  On failure no slot of TABLE holds an offset.
: BSLOT-TABLE-OWN  ( region table element-u offset -- status )
    2 PICK RTAB-COUNT@ 0 ?DO                 ( region table u off )
        I 3 PICK 3 PICK RTAB-NTH OVER +      ( region table u off slot )
        4 PICK SWAP BSLOT-OWN IF
            I 3 PICK 3 PICK 3 PICK BSLOT-TABLE-FORGET
            2DROP 2DROP BSLOT-S-NOMEM UNLOOP EXIT
        THEN
    LOOP
    2DROP 2DROP BSLOT-S-OK ;
