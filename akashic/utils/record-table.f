\ =====================================================================
\  record-table.f - Growing tables of fixed-size records
\ =====================================================================
\  A table is three cells the caller owns: the address of its records,
\  how many there are, and how many fit.  Records are contiguous and all
\  the same size, which the caller passes to every word.  A table grows
\  by doubling, so memory bounds it, not a count.  The caller keeps the
\  order; the search words find a record in a table kept sorted by a
\  leading 32-byte key or a leading u64 id.
\
\  Unlike table.f's fixed slot arrays, these tables live on the heap and
\  are written out and read back whole, so stores can keep them in their
\  files.  Every word wipes the bytes it gives up: growing wipes the old
\  array, deleting wipes the freed last slot, and freeing wipes the whole
\  array, so a table that held secrets leaves nothing behind.
\
\  Tables are caller-serialized.  The module has no global state.
\ =====================================================================

PROVIDED akashic-record-table

24 CONSTANT RTAB-SIZE

0 CONSTANT RTAB-S-OK
1 CONSTANT RTAB-S-NOMEM

: RTAB.ARRAY  ( table -- a ) ;
: RTAB.COUNT  ( table -- a ) 8 + ;
: RTAB.ROOM   ( table -- a ) 16 + ;

: RTAB-COUNT@  ( table -- n ) RTAB.COUNT @ ;

\ Record INDEX of a table of ELEMENT-U-byte records.
: RTAB-NTH  ( index table element-u -- record ) ROT * SWAP @ + ;

\ Room for one more record of ELEMENT-U bytes.  Growing doubles the room,
\ copies the records and wipes the old array.
: RTAB-RESERVE  ( table element-u -- status )
    OVER RTAB.COUNT @ 2 PICK RTAB.ROOM @ < IF 2DROP RTAB-S-OK EXIT THEN
    OVER RTAB.ROOM @ 2 * 8 MAX               ( table u room' )
    2DUP * DUP ALLOCATE IF
        2DROP 2DROP DROP RTAB-S-NOMEM EXIT
    THEN                                     ( table u room' bytes new )
    TUCK SWAP 0 FILL                         ( table u room' new )
    3 PICK @ ?DUP IF
        DUP 2 PICK 6 PICK RTAB.COUNT @ 6 PICK * MOVE
        DUP 5 PICK RTAB.ROOM @ 5 PICK * 0 FILL
        FREE
    THEN
    3 PICK !
    ROT RTAB.ROOM ! DROP
    RTAB-S-OK ;

\ Opens a zeroed slot at INDEX, moving later records up; the table has
\ room.
: RTAB-INSERT  ( index table element-u -- slot )
    >R
    DUP @ 2 PICK R@ * +
    DUP DUP R@ +
    3 PICK RTAB.COUNT @ 5 PICK - R@ *
    MOVE
    DUP R> 0 FILL
    SWAP RTAB.COUNT 1 SWAP +!
    NIP ;

\ Removes record INDEX, moving later records down and wiping the freed
\ last slot.
: RTAB-DELETE  ( index table element-u -- )
    >R
    DUP @ 2 PICK R@ * +
    DUP R@ + SWAP
    2 PICK RTAB.COUNT @ 4 PICK - 1- R@ *
    MOVE
    NIP
    DUP RTAB.COUNT -1 SWAP +!
    DUP @ SWAP RTAB.COUNT @ R@ * + R> 0 FILL ;

\ Wipes and frees the records; the table is empty.
: RTAB-FREE  ( table element-u -- )
    OVER RTAB.ROOM @ * OVER @                ( table bytes array )
    ?DUP IF TUCK SWAP 0 FILL FREE ELSE DROP THEN
    RTAB-SIZE 0 FILL ;

\ Fills an empty table with copies of N records of ELEMENT-U bytes.
: RTAB-TAKE  ( records n table element-u -- status )
    2 PICK 0= IF 2DROP 2DROP RTAB-S-OK EXIT THEN
    >R
    OVER R@ * ALLOCATE IF
        DROP 2DROP DROP R> DROP RTAB-S-NOMEM EXIT
    THEN                                     ( records n table array )
    OVER !
    2DUP RTAB.COUNT ! 2DUP RTAB.ROOM !
    @ SWAP R> * MOVE
    RTAB-S-OK ;

\ Copies the records to AT; the address after them.
: RTAB-PUT  ( at table element-u -- at' )
    OVER RTAB.COUNT @ *
    >R @ OVER R@ MOVE R> + ;

\ =====================================================================
\  Sorted tables
\ =====================================================================

\ Where a 32-byte KEY is or belongs among N records of ELEMENT-U bytes,
\ each starting with its key, in ascending byte order.
: RTAB-SEARCH  ( key records n element-u -- index found? )
    >R 0 SWAP                                ( key records lo hi ; R: u )
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT                      ( key records lo hi mid )
        4 PICK 32 2 PICK R@ * 6 PICK + 32 COMPARE
        DUP 0= IF DROP NIP NIP NIP NIP R> DROP -1 EXIT THEN
        0< IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP NIP R> DROP 0 ;

\ The record holding KEY, or 0.
: RTAB-RECORD  ( key records n element-u -- record|0 )
    2 PICK >R DUP >R RTAB-SEARCH
    IF R> * R> + ELSE DROP R> R> 2DROP 0 THEN ;

\ Where ID is or belongs among N records of ELEMENT-U bytes, each
\ starting with its id (a cell below 2^63), in ascending order.
: RTAB-SEARCH-ID  ( id records n element-u -- index found? )
    >R 0 SWAP                                ( id records lo hi ; R: u )
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT                      ( id records lo hi mid )
        DUP R@ * 4 PICK + @ 5 PICK           ( id records lo hi mid id' id )
        2DUP = IF 2DROP NIP NIP NIP NIP R> DROP -1 EXIT THEN
        > IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP NIP R> DROP 0 ;

\ Whether N records' leading 32-byte keys strictly ascend.
: RTAB-ASCENDING?  ( records n element-u -- flag )
    OVER 2 < IF 2DROP DROP -1 EXIT THEN
    ROT ROT 1 DO                             ( u record )
        DUP 32 2 PICK 4 PICK + 32 COMPARE 0< 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        OVER +
    LOOP
    2DROP -1 ;

\ Whether N records' leading ids strictly ascend.
: RTAB-IDS-ASCENDING?  ( records n element-u -- flag )
    OVER 2 < IF 2DROP DROP -1 EXIT THEN
    ROT ROT 1 DO                             ( u record )
        DUP @ OVER 3 PICK + @ < 0= IF 2DROP 0 UNLOOP EXIT THEN
        OVER +
    LOOP
    2DROP -1 ;
