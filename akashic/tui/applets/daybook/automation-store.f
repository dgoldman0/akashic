\ =====================================================================
\  automation-store.f - Daybook's durable automation store
\ =====================================================================
\  Daybook keeps its schedules in one file, replaced whole and atomically
\  through vfs-replace.f.  The file is a CRC-checked record
\  (utils/checked-record.f, magic AKDBAUTO, format 1) whose tag is its
\  generation.  Its payload is a header, then three tables kept sorted:
\
\    schedules    a 512-byte record per schedule ever created, by RID; a
\                 deleted schedule stays as a tombstone, so its RID is
\                 never reused
\    occurrences  a 128-byte record per firing awaiting or past review,
\                 by id
\    keys         a 96-byte create key per create, by key bytes, so a
\                 repeated create finds the schedule it already made
\
\  The tables live in memory and grow as needed: memory and the file bound
\  them, not a count.  The owner edits them and commits the whole file.
\  COMMIT checks the file it is about to write as OPEN would, so the store
\  never writes a file it would refuse to read.  A commit that fails
\  reloads the last committed file, so memory never runs ahead of the
\  disk.
\
\  OPEN finishes or undoes an interrupted replacement, then reads the file.
\  A missing file is an empty store.  A file the store cannot trust (a bad
\  CRC, truncation, tables that break their rules), one written in a newer
\  format, or one that cannot be read blocks the store with that reason:
\  nothing loads and nothing is written, so a damaged schedule list never
\  becomes an empty one.  A replacement whose outcome is unknown blocks it
\  the same way until the next OPEN recovers the file.
\
\  The store is caller-serialized.
\
\  Public API:
\    DBAS-INIT         ( vfs path path-u store -- status )
\    DBAS-OPEN         ( store -- status )
\    DBAS-CLOSE        ( store -- status )
\    DBAS-COMMIT       ( store -- status )
\    DBAS-STATE@       ( store -- state )
\    DBAS-REASON@      ( store -- reason )
\    DBAS-GENERATION@  ( store -- n )
\    DBAS-IDENTITY     ( store -- id status )
\    DBAS-HEADER       ( store -- header )
\    DBAS-SCHEDULE-COUNT@ DBAS-OCCURRENCE-COUNT@ DBAS-KEY-COUNT@
\                      ( store -- n )
\    DBAS-SCHEDULE DBAS-OCCURRENCE DBAS-KEY  ( index store -- record )
\    DBAS-FIND-SCHEDULE    ( rid store -- index found? )
\    DBAS-FIND-KEY         ( key store -- index found? )
\    DBAS-FIND-OCCURRENCE  ( id store -- index found? )
\    DBAS-INSERT-SCHEDULE  ( index store -- schedule status )
\    DBAS-INSERT-KEY       ( index store -- key-record status )
\    DBAS-APPEND-OCCURRENCE  ( store -- occurrence status )
\    DBAS-DELETE-OCCURRENCE  ( index store -- )
\    DBAS-TITLE-OK?    ( address length -- flag )
\    DBAS-FIELD$       ( field -- address length )
\    DBAS-FIELD!       ( address length field capacity -- )
\ =====================================================================

PROVIDED akashic-daybook-automation-store

REQUIRE recurrence.f
REQUIRE ../../../runtime/identity.f
REQUIRE ../../../math/entropy.f
REQUIRE ../../../utils/checked-record.f
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/fs/vfs-replace.f
REQUIRE ../../../text/utf8.f

0 CONSTANT DBAS-S-OK
1 CONSTANT DBAS-S-INVALID
2 CONSTANT DBAS-S-NOMEM
3 CONSTANT DBAS-S-IO
4 CONSTANT DBAS-S-BLOCKED
5 CONSTANT DBAS-S-STATE
6 CONSTANT DBAS-S-ENTROPY

\ Store states.
0 CONSTANT DBAS-CLOSED
1 CONSTANT DBAS-READY
2 CONSTANT DBAS-BLOCKED

\ Why a store is blocked.
1 CONSTANT DBAS-R-CORRUPT      \ the file failed its checks
2 CONSTANT DBAS-R-FUTURE       \ a newer format than this code reads
3 CONSTANT DBAS-R-UNCERTAIN    \ a replacement's outcome is unknown
4 CONSTANT DBAS-R-IO           \ the file could not be read into memory

\ Schedule states.
1 CONSTANT DBAS-ENABLED
2 CONSTANT DBAS-PAUSED
3 CONSTANT DBAS-COMPLETED      \ the series has no further occurrence
4 CONSTANT DBAS-TOMBSTONE      \ deleted; only identity remains

1 CONSTANT DBAS-ACTION-REMINDER

\ Occurrence kinds, states and the clock evidence behind a firing.
1 CONSTANT DBAS-ON-TIME
2 CONSTANT DBAS-MISSED
1 CONSTANT DBAS-DUE            \ awaiting review
2 CONSTANT DBAS-REVIEWED
1 CONSTANT DBAS-CONTINUOUS     \ seen while the clock ran continuously
2 CONSTANT DBAS-ACTIVATION     \ caught up when the runner started
3 CONSTANT DBAS-JUMP           \ caught up after the wall clock jumped

\ An interface rule: a title is one line, as a Daybook entry is.
120 CONSTANT DBAS-TITLE-MAX
\ Reviewed occurrences a new store keeps per schedule.
32 CONSTANT DBAS-DEFAULT-RETAIN

\ =====================================================================
\  Records
\ =====================================================================

\ A schedule:
\    +0 RID   +32 revision   +40 serial   +48 state   +56 archived
\   +64 action   +72 recurrence rule (DBREC-SIZE)
\  +144 next ordinal (0 none)   +152 next instant (UTC seconds)
\  +160 last occurrence id   +168 last result kind
\  +176 reviewed occurrences pruned
\  +184 title: length cell, DBAS-TITLE-MAX bytes
\  +312 zone: length cell, TZ-STRING-MAX bytes
\  +448 created (wall ms)   +456 modified (wall ms)   +464 zero to 512
512 CONSTANT DBAS-SCHEDULE-SIZE
: DBAS-S.RID       ( s -- addr ) ;
: DBAS-S.REVISION  ( s -- addr ) 32 + ;
: DBAS-S.SERIAL    ( s -- addr ) 40 + ;
: DBAS-S.STATE     ( s -- addr ) 48 + ;
: DBAS-S.ARCHIVED  ( s -- addr ) 56 + ;
: DBAS-S.ACTION    ( s -- addr ) 64 + ;
: DBAS-S.RULE      ( s -- rule ) 72 + ;
: DBAS-S.NEXT      ( s -- addr ) 144 + ;
: DBAS-S.NEXT-UTC  ( s -- addr ) 152 + ;
: DBAS-S.LAST      ( s -- addr ) 160 + ;
: DBAS-S.RESULT    ( s -- addr ) 168 + ;
: DBAS-S.PRUNED    ( s -- addr ) 176 + ;
: DBAS-S.TITLE     ( s -- field ) 184 + ;
: DBAS-S.ZONE      ( s -- field ) 312 + ;
: DBAS-S.CREATED   ( s -- addr ) 448 + ;
: DBAS-S.MODIFIED  ( s -- addr ) 456 + ;
: _DBAS-S.RESERVED ( s -- addr ) 464 + ;

\ An occurrence:
\    +0 id   +8 schedule RID   +40 schedule revision
\   +48 first ordinal   +56 last ordinal
\   +64 first instant   +72 last instant (UTC seconds)
\   +80 occurrences merged   +88 kind   +96 state   +104 basis
\  +112 accepted (wall ms)   +120 reviewed (wall ms)
128 CONSTANT DBAS-OCCURRENCE-SIZE
: DBAS-O.ID         ( o -- addr ) ;
: DBAS-O.RID        ( o -- addr ) 8 + ;
: DBAS-O.REVISION   ( o -- addr ) 40 + ;
: DBAS-O.FIRST      ( o -- addr ) 48 + ;
: DBAS-O.LAST       ( o -- addr ) 56 + ;
: DBAS-O.FIRST-UTC  ( o -- addr ) 64 + ;
: DBAS-O.LAST-UTC   ( o -- addr ) 72 + ;
: DBAS-O.COUNT      ( o -- addr ) 80 + ;
: DBAS-O.KIND       ( o -- addr ) 88 + ;
: DBAS-O.STATE      ( o -- addr ) 96 + ;
: DBAS-O.BASIS      ( o -- addr ) 104 + ;
: DBAS-O.ACCEPTED   ( o -- addr ) 112 + ;
: DBAS-O.REVIEWED   ( o -- addr ) 120 + ;

\ A create key: +0 key   +32 schedule RID   +64 request digest
96 CONSTANT DBAS-KEY-SIZE
: DBAS-K.KEY      ( k -- addr ) ;
: DBAS-K.RID      ( k -- addr ) 32 + ;
: DBAS-K.DIGEST   ( k -- addr ) 64 + ;

\ The header:
\    +0 store id (32 bytes)   +32 next serial   +40 next occurrence id
\   +48 schedule count   +56 occurrence count   +64 key count
\   +72 reviewed occurrences kept per schedule
\   +80 default zone: length cell, TZ-STRING-MAX bytes   +216 zero
224 CONSTANT DBAS-HEADER-SIZE
: DBAS-H.STORE-ID     ( h -- addr ) ;
: DBAS-H.SERIAL       ( h -- addr ) 32 + ;
: DBAS-H.OCCURRENCE   ( h -- addr ) 40 + ;
: _DBAS-H.SCHEDULES   ( h -- addr ) 48 + ;
: _DBAS-H.OCCURRENCES ( h -- addr ) 56 + ;
: _DBAS-H.KEYS        ( h -- addr ) 64 + ;
: DBAS-H.RETAIN       ( h -- addr ) 72 + ;
: DBAS-H.ZONE         ( h -- field ) 80 + ;
: _DBAS-H.RESERVED    ( h -- addr ) 216 + ;

: _DBAS-MAGIC$  ( -- address length ) S" AKDBAUTO" ;

\ Text in a field: a length cell, then capacity bytes, zero after the text.
: DBAS-FIELD$  ( field -- address length ) DUP 8 + SWAP @ ;

\ The caller keeps LENGTH within CAPACITY.
: DBAS-FIELD!  ( address length field capacity -- )
    OVER SWAP 8 + 0 FILL
    2DUP ! 8 + SWAP MOVE ;

\ A title: 1 to DBAS-TITLE-MAX bytes of UTF-8 with no control characters.
: DBAS-TITLE-OK?  ( address length -- flag )
    DUP 1 < OVER DBAS-TITLE-MAX > OR IF 2DROP 0 EXIT THEN
    2DUP UTF8-VALID? 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ DUP 32 < SWAP 127 = OR IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

\ =====================================================================
\  The store descriptor
\ =====================================================================

0x5341424144424B44 CONSTANT _DBAS-MAGIC  \ "DKBDABAS"

  0 CONSTANT _DBAS-MAGIC-OFF
  8 CONSTANT _DBAS-SELF
 16 CONSTANT _DBAS-VFS
 24 CONSTANT _DBAS-STATE
 32 CONSTANT _DBAS-REASON
 40 CONSTANT _DBAS-GENERATION
\ Three growing tables, each [array, count, room].
 48 CONSTANT _DBAS-SCHEDULES
 72 CONSTANT _DBAS-OCCURRENCES
 96 CONSTANT _DBAS-KEYS
120 CONSTANT _DBAS-HEADER
\ Validation scratch: the zone each stored zone string compiles to.
_DBAS-HEADER DBAS-HEADER-SIZE + CONSTANT _DBAS-ZONE
\ The checked-record callbacks see the store up to here.
_DBAS-ZONE TZ-SIZE + 7 + -8 AND CONSTANT _DBAS-CONTEXT-U
_DBAS-CONTEXT-U CONSTANT _DBAS-REPL
_DBAS-REPL VREPL-SIZE + 7 + -8 AND CONSTANT _DBAS-SPEC
_DBAS-SPEC CREC-SPEC-SIZE + 7 + -8 AND CONSTANT _DBAS-WORK
_DBAS-WORK CREC-WORK-SIZE + 7 + -8 AND CONSTANT DBAS-SIZE

: _DBAS.MAGIC       ( store -- a ) _DBAS-MAGIC-OFF + ;
: _DBAS.SELF        ( store -- a ) _DBAS-SELF + ;
: _DBAS.VFS         ( store -- a ) _DBAS-VFS + ;
: _DBAS.STATE       ( store -- a ) _DBAS-STATE + ;
: _DBAS.REASON      ( store -- a ) _DBAS-REASON + ;
: _DBAS.GENERATION  ( store -- a ) _DBAS-GENERATION + ;
: _DBAS.SCHEDULES   ( store -- table ) _DBAS-SCHEDULES + ;
: _DBAS.OCCURRENCES ( store -- table ) _DBAS-OCCURRENCES + ;
: _DBAS.KEYS        ( store -- table ) _DBAS-KEYS + ;
: DBAS-HEADER       ( store -- header ) _DBAS-HEADER + ;
: _DBAS.ZONE        ( store -- zone ) _DBAS-ZONE + ;
: _DBAS.REPL        ( store -- replacement ) _DBAS-REPL + ;
: _DBAS.SPEC        ( store -- spec ) _DBAS-SPEC + ;
: _DBAS.WORK        ( store -- work ) _DBAS-WORK + ;

: DBAS-VALID?  ( store -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _DBAS.MAGIC @ _DBAS-MAGIC <> IF DROP 0 EXIT THEN
    DUP _DBAS.SELF @ = ;

: DBAS-STATE@  ( store -- state ) _DBAS.STATE @ ;
\ Why a blocked store is blocked; 0 otherwise.
: DBAS-REASON@  ( store -- reason ) _DBAS.REASON @ ;
\ The generation of the file the tables came from; 0 before the first.
: DBAS-GENERATION@  ( store -- n ) _DBAS.GENERATION @ ;

\ =====================================================================
\  Growing tables
\ =====================================================================

\ Room for one more element of ELEMENT-U bytes in TABLE.
: _DBAS-ROOM  ( table element-u -- status )
    OVER 8 + @ 2 PICK 16 + @ < IF 2DROP DBAS-S-OK EXIT THEN
    OVER 16 + @ 2 * 8 MAX                    ( table u room' )
    2DUP * DUP ALLOCATE IF
        2DROP 2DROP DROP DBAS-S-NOMEM EXIT
    THEN                                     ( table u room' bytes new )
    TUCK SWAP 0 FILL                         ( table u room' new )
    3 PICK @ ?DUP IF
        DUP 2 PICK 6 PICK 8 + @ 6 PICK * MOVE
        DUP 5 PICK 16 + @ 5 PICK * 0 FILL
        FREE
    THEN
    3 PICK !
    ROT 16 + ! DROP
    DBAS-S-OK ;

\ Opens a zeroed slot at INDEX; the table has room.
: _DBAS-INSERT  ( index table element-u -- slot )
    >R
    DUP @ 2 PICK R@ * +
    DUP DUP R@ +
    3 PICK 8 + @ 5 PICK - R@ *
    MOVE
    DUP R> 0 FILL
    SWAP 8 + 1 SWAP +!
    NIP ;

: _DBAS-DELETE  ( index table element-u -- )
    >R
    DUP @ 2 PICK R@ * +
    DUP R@ + SWAP
    2 PICK 8 + @ 4 PICK - 1- R@ *
    MOVE
    NIP
    DUP 8 + -1 SWAP +!
    DUP @ SWAP 8 + @ R@ * + R> 0 FILL ;

: _DBAS-TABLE-FREE  ( table element-u -- )
    OVER 16 + @ * OVER @                     ( table bytes array )
    ?DUP IF TUCK SWAP 0 FILL FREE ELSE DROP THEN
    24 0 FILL ;

\ A table filled from N records of ELEMENT-U bytes; the table is empty.
: _DBAS-TAKE  ( records n table element-u -- status )
    2 PICK 0= IF 2DROP 2DROP DBAS-S-OK EXIT THEN
    >R
    OVER R@ * ALLOCATE IF
        DROP 2DROP DROP R> DROP DBAS-S-NOMEM EXIT
    THEN                                     ( records n table array )
    OVER !
    2DUP 8 + ! 2DUP 16 + !
    @ SWAP R> * MOVE
    DBAS-S-OK ;

\ A table's records written at AT; the address after them.
: _DBAS-PUT  ( at table element-u -- at' )
    OVER 8 + @ *
    >R @ OVER R@ MOVE R> + ;

: _DBAS-FREE-TABLES  ( store -- )
    DUP _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE _DBAS-TABLE-FREE
    DUP _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-TABLE-FREE
    _DBAS.KEYS DBAS-KEY-SIZE _DBAS-TABLE-FREE ;

: DBAS-SCHEDULE-COUNT@  ( store -- n ) _DBAS.SCHEDULES 8 + @ ;
: DBAS-OCCURRENCE-COUNT@  ( store -- n ) _DBAS.OCCURRENCES 8 + @ ;
: DBAS-KEY-COUNT@  ( store -- n ) _DBAS.KEYS 8 + @ ;

: DBAS-SCHEDULE  ( index store -- schedule )
    _DBAS.SCHEDULES @ SWAP DBAS-SCHEDULE-SIZE * + ;
: DBAS-OCCURRENCE  ( index store -- occurrence )
    _DBAS.OCCURRENCES @ SWAP DBAS-OCCURRENCE-SIZE * + ;
: DBAS-KEY  ( index store -- key-record )
    _DBAS.KEYS @ SWAP DBAS-KEY-SIZE * + ;

\ Blocking frees the tables: a blocked store holds nothing to trust.
: _DBAS-BLOCK!  ( reason store -- )
    DUP _DBAS-FREE-TABLES
    DUP DBAS-HEADER DBAS-HEADER-SIZE 0 FILL
    DBAS-BLOCKED OVER _DBAS.STATE !
    _DBAS.REASON ! ;

\ =====================================================================
\  Searching
\ =====================================================================

\ Where a 32-byte key is or belongs among N records of ELEMENT-U bytes,
\ each starting with its key, in ascending byte order.
: _DBAS-SEARCH  ( key records n element-u -- index found? )
    >R 0 SWAP                                ( key records lo hi ; R: u )
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT                      ( key records lo hi mid )
        4 PICK 32 2 PICK R@ * 6 PICK + 32 COMPARE
        DUP 0= IF DROP NIP NIP NIP NIP R> DROP -1 EXIT THEN
        0< IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP NIP R> DROP 0 ;

\ The record holding KEY, or 0.
: _DBAS-RECORD  ( key records n element-u -- record|0 )
    2 PICK >R DUP >R _DBAS-SEARCH
    IF R> * R> + ELSE DROP R> R> 2DROP 0 THEN ;

: DBAS-FIND-SCHEDULE  ( rid store -- index found? )
    DUP _DBAS.SCHEDULES @ SWAP DBAS-SCHEDULE-COUNT@
    DBAS-SCHEDULE-SIZE _DBAS-SEARCH ;

: DBAS-FIND-KEY  ( key store -- index found? )
    DUP _DBAS.KEYS @ SWAP DBAS-KEY-COUNT@ DBAS-KEY-SIZE _DBAS-SEARCH ;

\ Where occurrence ID is or belongs.
: DBAS-FIND-OCCURRENCE  ( id store -- index found? )
    >R 0 R@ DBAS-OCCURRENCE-COUNT@
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT
        DUP R@ DBAS-OCCURRENCE DBAS-O.ID @ 4 PICK
        2DUP = IF 2DROP NIP NIP NIP R> DROP -1 EXIT THEN
        > IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP R> DROP 0 ;

\ =====================================================================
\  Editing the tables
\ =====================================================================
\  The owner edits only a READY store, keeps every table sorted, and
\  commits.  A failed commit reloads the file and undoes the edits.

\ A zeroed schedule slot at INDEX.
: DBAS-INSERT-SCHEDULE  ( index store -- schedule status )
    DUP _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE _DBAS-ROOM ?DUP IF
        NIP NIP 0 SWAP EXIT
    THEN
    _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE _DBAS-INSERT DBAS-S-OK ;

\ A zeroed create-key slot at INDEX.
: DBAS-INSERT-KEY  ( index store -- key-record status )
    DUP _DBAS.KEYS DBAS-KEY-SIZE _DBAS-ROOM ?DUP IF NIP NIP 0 SWAP EXIT THEN
    _DBAS.KEYS DBAS-KEY-SIZE _DBAS-INSERT DBAS-S-OK ;

\ A zeroed occurrence slot after every other: ids only increase.
: DBAS-APPEND-OCCURRENCE  ( store -- occurrence status )
    DUP _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-ROOM ?DUP IF
        NIP 0 SWAP EXIT
    THEN
    DUP DBAS-OCCURRENCE-COUNT@ SWAP _DBAS.OCCURRENCES
        DBAS-OCCURRENCE-SIZE _DBAS-INSERT DBAS-S-OK ;

: DBAS-DELETE-OCCURRENCE  ( index store -- )
    _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-DELETE ;

\ The store's 32-byte identity, drawn from the entropy source the first
\ time it is needed.  The next commit saves it.
: DBAS-IDENTITY  ( store -- id status )
    DUP DBAS-STATE@ DBAS-READY <> IF DROP 0 DBAS-S-STATE EXIT THEN
    DBAS-HEADER DBAS-H.STORE-ID
    DUP RID-ZERO? 0= IF DBAS-S-OK EXIT THEN
    DUP RID-SIZE ENTROPY-FILL ENTROPY-S-OK <> IF
        DUP RID-CLEAR DBAS-S-ENTROPY EXIT
    THEN
    DUP RID-ZERO? IF DBAS-S-ENTROPY EXIT THEN
    DBAS-S-OK ;

\ =====================================================================
\  Validation
\ =====================================================================
\  OPEN checks every file it reads and COMMIT every file it writes.  The
\  checks read only the payload; ZONE is scratch in the store.

: _DBAS-ZERO?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _DBAS-WITHIN?  ( n lo hi -- flag ) 1+ WITHIN ;

\ The bytes after a field's text, up to CAPACITY, are zero.
: _DBAS-PAD-OK?  ( field capacity -- flag )
    OVER @ - SWAP DBAS-FIELD$ + SWAP _DBAS-ZERO? ;

: _DBAS-TITLE-FIELD-OK?  ( field -- flag )
    DUP DBAS-FIELD$ DBAS-TITLE-OK? 0= IF DROP 0 EXIT THEN
    DBAS-TITLE-MAX _DBAS-PAD-OK? ;

\ A zone string that parses into ZONE.
: _DBAS-ZONE-OK?  ( field zone -- flag )
    OVER @ 1 TZ-STRING-MAX _DBAS-WITHIN? 0= IF 2DROP 0 EXIT THEN
    OVER DBAS-FIELD$ ROT TZ-PARSE IF DROP 0 EXIT THEN
    TZ-STRING-MAX _DBAS-PAD-OK? ;

\ The payload's tables.
: _DBAS-P-SCHEDULES  ( payload -- schedules ) DBAS-HEADER-SIZE + ;
: _DBAS-P-OCCURRENCES  ( payload -- occurrences )
    DUP _DBAS-P-SCHEDULES SWAP _DBAS-H.SCHEDULES @ DBAS-SCHEDULE-SIZE * + ;
: _DBAS-P-KEYS  ( payload -- keys )
    DUP _DBAS-P-OCCURRENCES SWAP _DBAS-H.OCCURRENCES @
    DBAS-OCCURRENCE-SIZE * + ;

\ The schedule with RID among the payload's, or 0.
: _DBAS-P-SCHEDULE  ( rid payload -- schedule|0 )
    DUP _DBAS-P-SCHEDULES SWAP _DBAS-H.SCHEDULES @
    DBAS-SCHEDULE-SIZE _DBAS-RECORD ;

: _DBAS-COUNT-OK?  ( n room element-u -- flag ) / 0 SWAP _DBAS-WITHIN? ;

\ The counts describe the payload exactly.
: _DBAS-GEOMETRY-OK?  ( payload payload-u -- flag )
    DUP DBAS-HEADER-SIZE < IF 2DROP 0 EXIT THEN
    DBAS-HEADER-SIZE -                       ( payload rest )
    OVER _DBAS-H.SCHEDULES @ OVER DBAS-SCHEDULE-SIZE _DBAS-COUNT-OK?
    0= IF 2DROP 0 EXIT THEN
    OVER _DBAS-H.OCCURRENCES @ OVER DBAS-OCCURRENCE-SIZE _DBAS-COUNT-OK?
    0= IF 2DROP 0 EXIT THEN
    OVER _DBAS-H.KEYS @ OVER DBAS-KEY-SIZE _DBAS-COUNT-OK?
    0= IF 2DROP 0 EXIT THEN
    OVER _DBAS-H.SCHEDULES @ DBAS-SCHEDULE-SIZE *
    2 PICK _DBAS-H.OCCURRENCES @ DBAS-OCCURRENCE-SIZE * +
    ROT _DBAS-H.KEYS @ DBAS-KEY-SIZE * + = ;

\ An identity, counters past zero, and a default zone that parses.
: _DBAS-HEADER-OK?  ( payload zone -- flag )
    OVER DBAS-H.STORE-ID RID-ZERO?
    2 PICK DBAS-H.SERIAL @ 1 < OR
    2 PICK DBAS-H.OCCURRENCE @ 1 < OR
    2 PICK DBAS-H.RETAIN @ 0< OR
    2 PICK _DBAS-H.RESERVED 8 _DBAS-ZERO? 0= OR
    IF 2DROP 0 EXIT THEN
    SWAP DBAS-H.ZONE SWAP _DBAS-ZONE-OK? ;

\ A completed schedule has no next occurrence.  Any other's next instant
\ is the one its rule and zone give its next ordinal, within any UNTIL.
: _DBAS-NEXT-OK?  ( schedule zone -- flag )
    OVER DBAS-S.NEXT @ 0= IF
        DROP DUP DBAS-S.NEXT-UTC @ 0=
        SWAP DBAS-S.STATE @ DBAS-COMPLETED = AND EXIT
    THEN
    OVER DBAS-S.STATE @ DBAS-COMPLETED = IF 2DROP 0 EXIT THEN
    OVER DBAS-S.NEXT @ 2 PICK DBAS-S.RULE DBREC-OCCURRENCE IF
        2DROP DROP 0 EXIT
    THEN                                     ( s zone local )
    SWAP TZ-LOCAL>UTC NIP IF 2DROP 0 EXIT THEN   ( s utc )
    OVER DBAS-S.RULE DBREC.END @ DBREC-END-UNTIL = IF
        DUP 2 PICK DBAS-S.RULE DBREC.LIMIT @ > IF 2DROP 0 EXIT THEN
    THEN
    SWAP DBAS-S.NEXT-UTC @ = ;

\ A schedule: an identity, counters the header has passed, and either a
\ tombstone's zeroes or a reminder whose next instant matches its rule.
: _DBAS-SCHEDULE-OK?  ( schedule header zone -- flag )
    >R >R                                    ( s ; R: zone header )
    DUP RID-ZERO?
    OVER DBAS-S.REVISION @ 1 < OR
    OVER DBAS-S.SERIAL @ 1 R@ DBAS-H.SERIAL @ 1- _DBAS-WITHIN? 0= OR
    OVER DBAS-S.LAST @ 0 R> DBAS-H.OCCURRENCE @ 1- _DBAS-WITHIN? 0= OR
    OVER _DBAS-S.RESERVED DBAS-SCHEDULE-SIZE 464 - _DBAS-ZERO? 0= OR
    IF R> 2DROP 0 EXIT THEN                  ( s ; R: zone )
    DUP DBAS-S.STATE @ DBAS-TOMBSTONE = IF
        R> DROP DUP DBAS-S.ARCHIVED SWAP DBAS-S.CREATED OVER - _DBAS-ZERO?
        EXIT
    THEN
    DUP DBAS-S.STATE @ DBAS-ENABLED DBAS-COMPLETED _DBAS-WITHIN? 0=
    OVER DBAS-S.ARCHIVED @ 0 1 _DBAS-WITHIN? 0= OR
    OVER DBAS-S.ACTION @ DBAS-ACTION-REMINDER <> OR
    OVER DBAS-S.LAST @ 0= 2 PICK DBAS-S.RESULT @ 0= <> OR
    OVER DBAS-S.RESULT @ 0 DBAS-MISSED _DBAS-WITHIN? 0= OR
    OVER DBAS-S.PRUNED @ 0< OR
    OVER DBAS-S.TITLE _DBAS-TITLE-FIELD-OK? 0= OR
    IF R> 2DROP 0 EXIT THEN
    DUP DBAS-S.ZONE R@ _DBAS-ZONE-OK? 0= IF R> 2DROP 0 EXIT THEN
    DUP DBAS-S.RULE R@ DBREC-CHECK IF R> 2DROP 0 EXIT THEN
    R> _DBAS-NEXT-OK? ;

\ An occurrence: an id the counter has passed, a live schedule at a
\ revision it has reached, and ordinals, instants and a count that agree.
\ One awaiting review has no review time.
: _DBAS-OCCURRENCE-OK?  ( occurrence payload -- flag )
    OVER DBAS-O.ID @ 1 2 PICK DBAS-H.OCCURRENCE @ 1- _DBAS-WITHIN? 0= IF
        2DROP 0 EXIT
    THEN
    OVER DBAS-O.RID SWAP _DBAS-P-SCHEDULE    ( o schedule|0 )
    ?DUP 0= IF DROP 0 EXIT THEN
    DUP DBAS-S.STATE @ DBAS-TOMBSTONE = IF 2DROP 0 EXIT THEN
    DBAS-S.REVISION @ OVER DBAS-O.REVISION @ < IF DROP 0 EXIT THEN
    DUP DBAS-O.REVISION @ 1 <
    OVER DBAS-O.KIND @ DBAS-ON-TIME DBAS-MISSED _DBAS-WITHIN? 0= OR
    OVER DBAS-O.STATE @ DBAS-DUE DBAS-REVIEWED _DBAS-WITHIN? 0= OR
    OVER DBAS-O.BASIS @ DBAS-CONTINUOUS DBAS-JUMP _DBAS-WITHIN? 0= OR
    OVER DBAS-O.FIRST @ 1 < OR
    OVER DBAS-O.LAST @ 2 PICK DBAS-O.FIRST @ < OR
    OVER DBAS-O.LAST-UTC @ 2 PICK DBAS-O.FIRST-UTC @ < OR
    OVER DBAS-O.COUNT @ 1 3 PICK DBAS-O.LAST @ 4 PICK DBAS-O.FIRST @ - 1+
        _DBAS-WITHIN? 0= OR
    IF DROP 0 EXIT THEN
    DUP DBAS-O.STATE @ DBAS-DUE = IF DBAS-O.REVIEWED @ 0= EXIT THEN
    DROP -1 ;

\ A create key: nonzero key bytes naming a schedule in the payload.
: _DBAS-KEY-OK?  ( key-record payload -- flag )
    OVER DBAS-K.KEY 32 _DBAS-ZERO? IF 2DROP 0 EXIT THEN
    SWAP DBAS-K.RID SWAP _DBAS-P-SCHEDULE 0<> ;

\ N records of ELEMENT-U bytes in strictly ascending order of their first
\ 32 bytes.
: _DBAS-ASCENDING?  ( records n element-u -- flag )
    OVER 2 < IF 2DROP DROP -1 EXIT THEN
    ROT ROT 1 DO                             ( u record )
        DUP 32 2 PICK 4 PICK + 32 COMPARE 0< 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        OVER +
    LOOP
    2DROP -1 ;

: _DBAS-IDS-ASCENDING?  ( occurrences n -- flag )
    DUP 2 < IF 2DROP -1 EXIT THEN
    1 DO
        DUP @ OVER DBAS-OCCURRENCE-SIZE + @ < 0= IF DROP 0 UNLOOP EXIT THEN
        DBAS-OCCURRENCE-SIZE +
    LOOP
    DROP -1 ;

: _DBAS-SCHEDULES-OK?  ( payload zone -- flag )
    OVER _DBAS-P-SCHEDULES 2 PICK _DBAS-H.SCHEDULES @   ( p zone s n )
    2DUP DBAS-SCHEDULE-SIZE _DBAS-ASCENDING? 0= IF 2DROP 2DROP 0 EXIT THEN
    0 ?DO                                               ( p zone s )
        DUP 3 PICK 3 PICK _DBAS-SCHEDULE-OK? 0= IF
            2DROP DROP 0 UNLOOP EXIT
        THEN
        DBAS-SCHEDULE-SIZE +
    LOOP
    2DROP DROP -1 ;

: _DBAS-OCCURRENCES-OK?  ( payload -- flag )
    DUP _DBAS-P-OCCURRENCES OVER _DBAS-H.OCCURRENCES @   ( p o n )
    2DUP _DBAS-IDS-ASCENDING? 0= IF 2DROP DROP 0 EXIT THEN
    0 ?DO
        DUP 2 PICK _DBAS-OCCURRENCE-OK? 0= IF 2DROP 0 UNLOOP EXIT THEN
        DBAS-OCCURRENCE-SIZE +
    LOOP
    2DROP -1 ;

: _DBAS-KEYS-OK?  ( payload -- flag )
    DUP _DBAS-P-KEYS OVER _DBAS-H.KEYS @                 ( p k n )
    2DUP DBAS-KEY-SIZE _DBAS-ASCENDING? 0= IF 2DROP DROP 0 EXIT THEN
    0 ?DO
        DUP 2 PICK _DBAS-KEY-OK? 0= IF 2DROP 0 UNLOOP EXIT THEN
        DBAS-KEY-SIZE +
    LOOP
    2DROP -1 ;

\ The checked-record callbacks.  The context is the store's head.
: _DBAS-VALIDATE  ( store store-u payload payload-u tag -- status )
    DROP 2SWAP DROP >R                       ( payload payload-u ; R: store )
    OVER SWAP _DBAS-GEOMETRY-OK? 0= IF R> 2DROP CREC-S-SEMANTIC EXIT THEN
    DUP R@ _DBAS.ZONE _DBAS-HEADER-OK? 0= IF
        R> 2DROP CREC-S-SEMANTIC EXIT
    THEN
    DUP R@ _DBAS.ZONE _DBAS-SCHEDULES-OK? 0= IF
        R> 2DROP CREC-S-SEMANTIC EXIT
    THEN
    DUP _DBAS-OCCURRENCES-OK? 0= IF R> 2DROP CREC-S-SEMANTIC EXIT THEN
    _DBAS-KEYS-OK? R> DROP IF CREC-S-OK ELSE CREC-S-SEMANTIC THEN ;

: _DBAS-ENCODE  ( store store-u payload payload-u tag -- status )
    2DROP NIP                                ( store payload )
    OVER DBAS-HEADER OVER DBAS-HEADER-SIZE MOVE
    OVER DBAS-SCHEDULE-COUNT@ OVER _DBAS-H.SCHEDULES !
    OVER DBAS-OCCURRENCE-COUNT@ OVER _DBAS-H.OCCURRENCES !
    OVER DBAS-KEY-COUNT@ OVER _DBAS-H.KEYS !
    DBAS-HEADER-SIZE +
    OVER _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE _DBAS-PUT
    OVER _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-PUT
    OVER _DBAS.KEYS DBAS-KEY-SIZE _DBAS-PUT
    2DROP CREC-S-OK ;

: _DBAS-PAYLOAD-U  ( store -- payload-u )
    DUP DBAS-SCHEDULE-COUNT@ DBAS-SCHEDULE-SIZE *
    OVER DBAS-OCCURRENCE-COUNT@ DBAS-OCCURRENCE-SIZE * +
    SWAP DBAS-KEY-COUNT@ DBAS-KEY-SIZE * + DBAS-HEADER-SIZE + ;

\ =====================================================================
\  Reading the file
\ =====================================================================

\ An empty store: counters at one, the default retention, and UTC.
: _DBAS-FRESH  ( store -- )
    0 OVER _DBAS.GENERATION !
    DBAS-HEADER DUP DBAS-HEADER-SIZE 0 FILL
    1 OVER DBAS-H.SERIAL !
    1 OVER DBAS-H.OCCURRENCE !
    DBAS-DEFAULT-RETAIN OVER DBAS-H.RETAIN !
    S" UTC0" ROT DBAS-H.ZONE TZ-STRING-MAX DBAS-FIELD! ;

\ The file open for reading, or 0 when it does not exist.
: _DBAS-OPEN-READ  ( store -- fd|0 status )
    >R R@ _DBAS.REPL VREPL-TARGET$ VFS-FF-READ R> _DBAS.VFS @ VFS-OPEN?
    ?DUP IF
        NIP VFS-IOR-REASON VFS-R-NOENT = IF 0 DBAS-S-OK ELSE 0 DBAS-S-IO THEN
        EXIT
    THEN
    DBAS-S-OK ;

\ Validates the file's bytes and takes their tables and generation.  A
\ file that fails its checks blocks the store.
: _DBAS-TAKE-FILE  ( record record-u store -- status )
    >R R@ _DBAS-CONTEXT-U 2SWAP R@ _DBAS.SPEC R@ _DBAS.WORK CREC-VALIDATE
    ?DUP IF
        CREC-S-UNSUPPORTED = IF DBAS-R-FUTURE ELSE DBAS-R-CORRUPT THEN
        R> _DBAS-BLOCK! DBAS-S-OK EXIT
    THEN
    R@ _DBAS.WORK CREC-TAG@ R@ _DBAS.GENERATION !
    R@ _DBAS.WORK CREC-PAYLOAD$ DROP                    ( payload )
    DUP R@ DBAS-HEADER DBAS-HEADER-SIZE MOVE
    \ In memory the tables keep their own counts.
    R@ DBAS-HEADER _DBAS-H.SCHEDULES 24 0 FILL
    DUP _DBAS-P-SCHEDULES OVER _DBAS-H.SCHEDULES @
        R@ _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE _DBAS-TAKE
    ?DUP IF NIP R> DROP EXIT THEN
    DUP _DBAS-P-OCCURRENCES OVER _DBAS-H.OCCURRENCES @
        R@ _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-TAKE
    ?DUP IF NIP R> DROP EXIT THEN
    DUP _DBAS-P-KEYS SWAP _DBAS-H.KEYS @ R> _DBAS.KEYS DBAS-KEY-SIZE _DBAS-TAKE ;

\ Reads the file into the empty tables.  A missing file leaves an empty
\ store; one that is too short to be a record, unreadable, or refused
\ blocks it.  Fails only for want of memory to hold it.
: _DBAS-LOAD  ( store -- status )
    DUP _DBAS-OPEN-READ ?DUP IF
        NIP DROP DBAS-R-IO SWAP _DBAS-BLOCK! DBAS-S-OK EXIT
    THEN                                                ( store fd|0 )
    ?DUP 0= IF _DBAS-FRESH DBAS-S-OK EXIT THEN          ( store fd )
    DUP VFS-SIZE                                        ( store fd size )
    DUP CREC-HEADER-SIZE < IF
        DROP VFS-CLOSE? DROP DBAS-R-CORRUPT SWAP _DBAS-BLOCK! DBAS-S-OK EXIT
    THEN
    DUP ALLOCATE IF
        2DROP VFS-CLOSE? DROP DROP DBAS-S-NOMEM EXIT
    THEN                                                ( store fd size buffer )
    2DUP SWAP 4 PICK VFS-READ-EXACT                     ( store fd size buffer ior )
    3 PICK VFS-CLOSE? DROP
    >R ROT DROP SWAP R>                                 ( store buffer size ior )
    IF DROP FREE DBAS-R-IO SWAP _DBAS-BLOCK! DBAS-S-OK EXIT THEN
    OVER SWAP 3 PICK _DBAS-TAKE-FILE                    ( store buffer status )
    SWAP FREE NIP ;

\ Drops what memory holds and reads the file again, returning STATUS.  A
\ file that can no longer be read blocks the store.
: _DBAS-RELOAD  ( status store -- status )
    DUP _DBAS-FREE-TABLES
    DUP ['] _DBAS-LOAD CATCH IF DROP DBAS-S-NOMEM THEN  ( status store load )
    IF DBAS-R-IO SWAP _DBAS-BLOCK! DROP DBAS-S-BLOCKED EXIT THEN
    DBAS-STATE@ DBAS-BLOCKED = IF DROP DBAS-S-BLOCKED THEN ;

\ Finishes or undoes an interrupted replacement.  One nobody can resolve
\ blocks the store.
: _DBAS-RECOVER  ( store -- )
    DUP _DBAS.REPL ['] VREPL-RECOVER CATCH IF DROP VREPL-S-RECOVERY THEN
    DUP VREPL-S-OK = OVER VREPL-S-ROLLED-BACK = OR
    SWAP VREPL-S-COMMITTED-CLEANUP = OR
    IF DROP ELSE DBAS-R-UNCERTAIN SWAP _DBAS-BLOCK! THEN ;

\ =====================================================================
\  Writing the file
\ =====================================================================

\ The file's bytes for the tables, one generation on, checked as OPEN
\ would check them.  The caller frees the record.
: _DBAS-ENCODE-FILE  ( store -- record record-u status )
    DUP _DBAS-PAYLOAD-U OVER _DBAS.SPEC CREC-MEASURE IF
        2DROP 0 0 DBAS-S-INVALID EXIT
    THEN                                     ( store capacity )
    DUP ALLOCATE IF 2DROP DROP 0 0 DBAS-S-NOMEM EXIT THEN
    SWAP                                     ( store record capacity )
    2 PICK _DBAS-CONTEXT-U
    4 PICK _DBAS-PAYLOAD-U
    5 PICK _DBAS.GENERATION @ 1+
    5 PICK 5 PICK
    8 PICK _DBAS.SPEC 9 PICK _DBAS.WORK CREC-ENCODE
                                             ( store record capacity record-u status )
    IF 2DROP FREE DROP 0 0 DBAS-S-INVALID EXIT THEN
    NIP                                      ( store record record-u )
    2 PICK _DBAS-CONTEXT-U 2OVER 6 PICK _DBAS.SPEC 7 PICK _DBAS.WORK
        CREC-VALIDATE
    IF DROP FREE DROP 0 0 DBAS-S-INVALID EXIT THEN
    ROT DROP DBAS-S-OK ;

\ Nobody can tell which file the disk holds until recovery runs again.
: _DBAS-UNCERTAIN  ( store -- status )
    DBAS-R-UNCERTAIN SWAP _DBAS-BLOCK! DBAS-S-BLOCKED ;

\ The store after a replacement: one generation on, unchanged and
\ reloaded, or blocked when nobody can tell which.
: _DBAS-REPLACED  ( vrepl-status store -- status )
    OVER VREPL-S-OK = 2 PICK VREPL-S-COMMITTED-CLEANUP = OR IF
        NIP 1 SWAP _DBAS.GENERATION +! DBAS-S-OK EXIT
    THEN
    OVER VREPL-S-IO = 2 PICK VREPL-S-CONFLICT = OR
    2 PICK VREPL-S-BUSY = OR 2 PICK VREPL-S-INVALID = OR IF
        NIP DBAS-S-IO SWAP _DBAS-RELOAD EXIT
    THEN
    NIP _DBAS-UNCERTAIN ;

\ Writes the tables as the next generation.  Any failure reloads the
\ last committed file, undoing the edits; one whose outcome is unknown
\ blocks the store instead.
: DBAS-COMMIT  ( store -- status )
    DUP DBAS-VALID? 0= IF DROP DBAS-S-INVALID EXIT THEN
    DUP DBAS-STATE@ DBAS-READY <> IF
        DBAS-STATE@ DBAS-BLOCKED = IF DBAS-S-BLOCKED ELSE DBAS-S-STATE THEN
        EXIT
    THEN
    DUP DBAS-IDENTITY NIP ?DUP IF SWAP _DBAS-RELOAD EXIT THEN
    DUP _DBAS-ENCODE-FILE ?DUP IF NIP NIP SWAP _DBAS-RELOAD EXIT THEN
                                             ( store record record-u )
    2DUP 4 PICK _DBAS.REPL ['] VREPL-REPLACE CATCH IF
        2DROP DROP VREPL-S-UNCERTAIN
    THEN                                     ( store record record-u vstatus )
    NIP SWAP FREE
    SWAP _DBAS-REPLACED ;

\ =====================================================================
\  Lifecycle
\ =====================================================================

\ Configures STORE, DBAS-SIZE cell-aligned bytes, to keep its file at
\ PATH, an absolute path, in VFS.  vfs-replace derives the stage, backup
\ and marker names beside it.  The store starts closed.
: DBAS-INIT  ( vfs path path-u store -- status )
    DUP 0= OVER 7 AND OR IF 2DROP 2DROP DBAS-S-INVALID EXIT THEN
    DUP DBAS-VALID? IF 2DROP 2DROP DBAS-S-STATE EXIT THEN
    3 PICK 0= IF 2DROP 2DROP DBAS-S-INVALID EXIT THEN
    DUP DBAS-SIZE 0 FILL
    >R
    2 PICK R@ _DBAS.VFS !
    2 PICK R@ _DBAS.REPL VREPL-INIT IF
        2DROP DROP R> DBAS-SIZE 0 FILL DBAS-S-INVALID EXIT
    THEN
    R@ _DBAS.REPL VREPL-DERIVE-PATHS! IF
        DROP R> DBAS-SIZE 0 FILL DBAS-S-INVALID EXIT
    THEN
    DROP
    _DBAS-MAGIC$ 1 CREC-TAG-POSITIVE ['] _DBAS-ENCODE ['] _DBAS-VALIDATE
        R@ _DBAS.SPEC CREC-SPEC-INIT
    \ The file grows with its tables; memory, not the format, bounds it.
    DBAS-HEADER-SIZE 1 62 LSHIFT 8 R@ _DBAS.SPEC CREC-SPEC-FRAMED! OR
    R@ _DBAS.SPEC CREC-SPEC-SEAL OR
    R@ _DBAS.WORK CREC-WORK-INIT OR IF
        R> DBAS-SIZE 0 FILL DBAS-S-INVALID EXIT
    THEN
    R@ DUP _DBAS.SELF !
    _DBAS-MAGIC R@ _DBAS.MAGIC !
    DBAS-CLOSED R> _DBAS.STATE !
    DBAS-S-OK ;

\ Frees what OPEN read.  The store stays configured.
: DBAS-CLOSE  ( store -- status )
    DUP DBAS-VALID? 0= IF DROP DBAS-S-INVALID EXIT THEN
    DUP _DBAS-FREE-TABLES
    DUP DBAS-HEADER DBAS-HEADER-SIZE 0 FILL
    0 OVER _DBAS.GENERATION !
    0 OVER _DBAS.REASON !
    DBAS-CLOSED SWAP _DBAS.STATE !
    DBAS-S-OK ;

\ Recovers the file and reads it.  Returns OK when the store is READY, or
\ BLOCKED with DBAS-REASON@ saying why it cannot be used.
: DBAS-OPEN  ( store -- status )
    DUP DBAS-VALID? 0= IF DROP DBAS-S-INVALID EXIT THEN
    DUP DBAS-STATE@ DBAS-CLOSED <> IF DROP DBAS-S-STATE EXIT THEN
    DBAS-READY OVER _DBAS.STATE !
    0 OVER _DBAS.REASON !
    DUP _DBAS-RECOVER
    DUP DBAS-STATE@ DBAS-READY <> IF DROP DBAS-S-BLOCKED EXIT THEN
    DBAS-S-OK SWAP _DBAS-RELOAD ;
