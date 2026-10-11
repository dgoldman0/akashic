\ =====================================================================
\  automation-store.f - Daybook's durable automation store
\ =====================================================================
\  Daybook keeps its schedules in one file, replaced whole and atomically
\  through vfs-replace.f.  The file is a CRC-checked record
\  (utils/checked-record.f, magic AKDBAUTO, format 2) whose tag is its
\  generation.  Its payload is a header, four tables kept sorted, and a
\  region of variable-length bytes:
\
\    schedules    a 512-byte record per schedule ever created, by RID; a
\                 deleted schedule stays as a tombstone, so its RID is
\                 never reused
\    actions      a 144-byte record per live schedule that runs the Agent,
\                 by RID: its operands and the permission it was approved
\                 under
\    occurrences  a 272-byte record per firing, Agent run, or short record
\                 of a deleted schedule's run, by id
\    keys         a 96-byte create key per create, by key bytes, so a
\                 repeated create finds the schedule it already made
\    blob         each action's operands, then each occurrence's summary,
\                 in table order, each padded to a cell
\
\  The tables live in memory and grow as needed: memory and the file bound
\  them, not a count.  In memory a record owns a heap copy of its blob
\  bytes; in the file it names their offset.  The owner edits the tables
\  and commits the whole file.  COMMIT checks the file it is about to
\  write as OPEN would, so the store never writes a file it would refuse
\  to read.  A commit that fails reloads the last committed file, so
\  memory never runs ahead of the disk.
\
\  OPEN finishes or undoes an interrupted replacement, then reads the file.
\  A missing file is an empty store.  A file the store cannot trust (a bad
\  CRC, truncation, tables that break their rules), one written in another
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
\    DBAS-REVERT       ( store -- status )
\    DBAS-STATE@       ( store -- state )
\    DBAS-REASON@      ( store -- reason )
\    DBAS-GENERATION@  ( store -- n )
\    DBAS-IDENTITY     ( store -- id status )
\    DBAS-HEADER       ( store -- header )
\    DBAS-SCHEDULE-COUNT@ DBAS-ACTION-COUNT@ DBAS-OCCURRENCE-COUNT@
\    DBAS-KEY-COUNT@   ( store -- n )
\    DBAS-SCHEDULE DBAS-ACTION DBAS-OCCURRENCE DBAS-KEY
\                      ( index store -- record )
\    DBAS-FIND-SCHEDULE    ( rid store -- index found? )
\    DBAS-FIND-ACTION      ( rid store -- index found? )
\    DBAS-ACTION-OF        ( rid store -- action|0 )
\    DBAS-FIND-KEY         ( key store -- index found? )
\    DBAS-FIND-OCCURRENCE  ( id store -- index found? )
\    DBAS-FIND-KEYED       ( key store -- occurrence|0 )
\    DBAS-INSERT-SCHEDULE  ( index store -- schedule status )
\    DBAS-INSERT-ACTION    ( index store -- action status )
\    DBAS-INSERT-KEY       ( index store -- key-record status )
\    DBAS-APPEND-OCCURRENCE  ( store -- occurrence status )
\    DBAS-DELETE-ACTION      ( index store -- )
\    DBAS-DELETE-OCCURRENCE  ( index store -- )
\    DBAS-BLOB$        ( slot -- address length )
\    DBAS-BLOB!        ( address length slot -- status )
\    DBAS-TITLE-OK?    ( address length -- flag )
\    DBAS-FIELD$       ( field -- address length )
\    DBAS-FIELD!       ( address length field capacity -- )
\ =====================================================================

PROVIDED akashic-dbk-auto-store

REQUIRE recurrence.f
REQUIRE ../../../runtime/identity.f
REQUIRE ../../../math/entropy.f
REQUIRE ../../../utils/checked-record.f
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/fs/vfs-replace.f
REQUIRE ../../../utils/record-table.f
REQUIRE ../../../text/utf8.f
REQUIRE ../../../interop/scheduled-action.f

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

\ Actions are the catalog's (interop/scheduled-action.f).
SACT-REMINDER  CONSTANT DBAS-ACTION-REMINDER
SACT-AGENT-RUN CONSTANT DBAS-ACTION-AGENT

\ Occurrence kinds.
1 CONSTANT DBAS-ON-TIME
2 CONSTANT DBAS-MISSED
3 CONSTANT DBAS-MANUAL         \ asked for by hand: Run Now
\ Review states.
0 CONSTANT DBAS-IN-FLIGHT      \ an Agent run not yet ended
1 CONSTANT DBAS-DUE            \ awaiting review
2 CONSTANT DBAS-REVIEWED
3 CONSTANT DBAS-CLEAR          \ ended well; nothing to review
\ The clock evidence behind an occurrence.
1 CONSTANT DBAS-CONTINUOUS     \ seen while the clock ran continuously
2 CONSTANT DBAS-ACTIVATION     \ caught up when the runner started
3 CONSTANT DBAS-JUMP           \ caught up after the wall clock jumped
4 CONSTANT DBAS-USER           \ asked for by hand
\ An Agent run's phases.
1 CONSTANT DBAS-ACCEPTED       \ recorded with its dispatch key
2 CONSTANT DBAS-RUNNING        \ the Agent started it
3 CONSTANT DBAS-ENDED
\ Occurrence flags.
1 CONSTANT DBAS-F-AUDIT        \ the short record a deleted schedule keeps

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
\  +160 last occurrence id   +168 last occurrence kind
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

\ An action, for a schedule that runs the Agent:
\    +0 schedule RID   +32 action   +40 schema   +48 approved (0 or 1)
\   +56 Practice RID   +88 permission RID   +120 permission revision
\  +128 operands: blob
\  The Practice and permission are zero until the schedule is approved.
144 CONSTANT DBAS-ACTION-SIZE
128 CONSTANT _DBAS-A-OPERANDS
: DBAS-A.RID         ( a -- addr ) ;
: DBAS-A.ACTION      ( a -- addr ) 32 + ;
: DBAS-A.SCHEMA      ( a -- addr ) 40 + ;
: DBAS-A.AUTHORIZED  ( a -- addr ) 48 + ;
: DBAS-A.PRACTICE    ( a -- addr ) 56 + ;
: DBAS-A.PERMISSION  ( a -- addr ) 88 + ;
: DBAS-A.PERMISSION-REVISION ( a -- addr ) 120 + ;
: DBAS-A.OPERANDS    ( a -- slot ) _DBAS-A-OPERANDS + ;

\ An occurrence:
\    +0 id   +8 schedule RID   +40 schedule revision
\   +48 first ordinal   +56 last ordinal
\   +64 first instant   +72 last instant (UTC seconds)
\   +80 occurrences merged   +88 kind   +96 review state   +104 basis
\  +112 accepted (wall ms)   +120 reviewed (wall ms)   +128 action
\  For an Agent run, and zero for a reminder:
\  +136 phase   +144 outcome   +152 reason   +160 dispatch key
\  +192 run RID   +224 started   +232 ended (wall ms)   +240 flags
\  +248 summary: blob   +264 zero to 272
272 CONSTANT DBAS-OCCURRENCE-SIZE
248 CONSTANT _DBAS-O-SUMMARY
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
: DBAS-O.ACTION     ( o -- addr ) 128 + ;
: DBAS-O.PHASE      ( o -- addr ) 136 + ;
: DBAS-O.OUTCOME    ( o -- addr ) 144 + ;
: DBAS-O.REASON     ( o -- addr ) 152 + ;
: DBAS-O.KEY        ( o -- addr ) 160 + ;
: DBAS-O.RUN        ( o -- addr ) 192 + ;
: DBAS-O.STARTED    ( o -- addr ) 224 + ;
: DBAS-O.ENDED      ( o -- addr ) 232 + ;
: DBAS-O.FLAGS      ( o -- addr ) 240 + ;
: DBAS-O.SUMMARY    ( o -- slot ) _DBAS-O-SUMMARY + ;
: _DBAS-O.RESERVED  ( o -- addr ) 264 + ;

\ A create key: +0 key   +32 schedule RID   +64 request digest
96 CONSTANT DBAS-KEY-SIZE
: DBAS-K.KEY      ( k -- addr ) ;
: DBAS-K.RID      ( k -- addr ) 32 + ;
: DBAS-K.DIGEST   ( k -- addr ) 64 + ;

\ The header:
\    +0 store id (32 bytes)   +32 next serial   +40 next occurrence id
\   +48 schedule count   +56 occurrence count   +64 key count
\   +72 reviewed occurrences kept per schedule
\   +80 default zone: length cell, TZ-STRING-MAX bytes
\  +216 action count   +224 blob bytes   +232 zero
240 CONSTANT DBAS-HEADER-SIZE
: DBAS-H.STORE-ID     ( h -- addr ) ;
: DBAS-H.SERIAL       ( h -- addr ) 32 + ;
: DBAS-H.OCCURRENCE   ( h -- addr ) 40 + ;
: _DBAS-H.SCHEDULES   ( h -- addr ) 48 + ;
: _DBAS-H.OCCURRENCES ( h -- addr ) 56 + ;
: _DBAS-H.KEYS        ( h -- addr ) 64 + ;
: DBAS-H.RETAIN       ( h -- addr ) 72 + ;
: DBAS-H.ZONE         ( h -- field ) 80 + ;
: _DBAS-H.ACTIONS     ( h -- addr ) 216 + ;
: _DBAS-H.BLOB        ( h -- addr ) 224 + ;
: _DBAS-H.RESERVED    ( h -- addr ) 232 + ;

: _DBAS-MAGIC$  ( -- address length ) S" AKDBAUTO" ;
2 CONSTANT _DBAS-FORMAT

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

\ ---------------------------------------------------------------------
\  Blobs
\ ---------------------------------------------------------------------
\  A blob slot is two cells: the bytes' address in memory (their offset
\  in the file) and their length.  An empty blob is zero and zero.

: DBAS-BLOB$  ( slot -- address length ) DUP @ SWAP 8 + @ ;

\ Wipes and frees a blob; the slot is empty.
: _DBAS-BLOB-FREE  ( slot -- )
    DUP @ ?DUP IF
        OVER 8 + @ OVER SWAP 0 FILL FREE
    THEN
    16 0 FILL ;

\ Sets a blob to a copy of LENGTH bytes at ADDRESS, which may be the
\ blob's own.  Zero bytes empty it.
: DBAS-BLOB!  ( address length slot -- status )
    OVER 0= IF NIP NIP _DBAS-BLOB-FREE DBAS-S-OK EXIT THEN
    OVER ALLOCATE IF DROP DROP 2DROP DBAS-S-NOMEM EXIT THEN   ( a u slot new )
    3 PICK OVER 4 PICK MOVE
    OVER _DBAS-BLOB-FREE
    OVER !
    8 + ! DROP DBAS-S-OK ;

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
\ Four growing tables, each RTAB-SIZE bytes.
 48 CONSTANT _DBAS-SCHEDULES
 72 CONSTANT _DBAS-ACTIONS
 96 CONSTANT _DBAS-OCCURRENCES
120 CONSTANT _DBAS-KEYS
144 CONSTANT _DBAS-HEADER
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
: _DBAS.ACTIONS     ( store -- table ) _DBAS-ACTIONS + ;
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

\ The tables are utils/record-table.f's; its statuses become the store's.
: _DBAS-STATUS  ( rtab-status -- status )
    IF DBAS-S-NOMEM ELSE DBAS-S-OK THEN ;

\ Frees the blob at OFFSET of each of TABLE's records, then the table.
: _DBAS-FREE-BLOBS  ( table element-u offset -- )
    2 PICK RTAB-COUNT@ 0 ?DO
        I 3 PICK 3 PICK RTAB-NTH OVER + _DBAS-BLOB-FREE
    LOOP
    DROP RTAB-FREE ;

: _DBAS-FREE-TABLES  ( store -- )
    DUP _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE RTAB-FREE
    DUP _DBAS.ACTIONS DBAS-ACTION-SIZE _DBAS-A-OPERANDS _DBAS-FREE-BLOBS
    DUP _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-O-SUMMARY _DBAS-FREE-BLOBS
    _DBAS.KEYS DBAS-KEY-SIZE RTAB-FREE ;

: DBAS-SCHEDULE-COUNT@  ( store -- n ) _DBAS.SCHEDULES RTAB-COUNT@ ;
: DBAS-ACTION-COUNT@  ( store -- n ) _DBAS.ACTIONS RTAB-COUNT@ ;
: DBAS-OCCURRENCE-COUNT@  ( store -- n ) _DBAS.OCCURRENCES RTAB-COUNT@ ;
: DBAS-KEY-COUNT@  ( store -- n ) _DBAS.KEYS RTAB-COUNT@ ;

: DBAS-SCHEDULE  ( index store -- schedule )
    _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE RTAB-NTH ;
: DBAS-ACTION  ( index store -- action )
    _DBAS.ACTIONS DBAS-ACTION-SIZE RTAB-NTH ;
: DBAS-OCCURRENCE  ( index store -- occurrence )
    _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE RTAB-NTH ;
: DBAS-KEY  ( index store -- key-record )
    _DBAS.KEYS DBAS-KEY-SIZE RTAB-NTH ;

\ Blocking frees the tables: a blocked store holds nothing to trust.
: _DBAS-BLOCK!  ( reason store -- )
    DUP _DBAS-FREE-TABLES
    DUP DBAS-HEADER DBAS-HEADER-SIZE 0 FILL
    DBAS-BLOCKED OVER _DBAS.STATE !
    _DBAS.REASON ! ;

\ =====================================================================
\  Searching
\ =====================================================================

: DBAS-FIND-SCHEDULE  ( rid store -- index found? )
    DUP _DBAS.SCHEDULES @ SWAP DBAS-SCHEDULE-COUNT@
    DBAS-SCHEDULE-SIZE RTAB-SEARCH ;

: DBAS-FIND-ACTION  ( rid store -- index found? )
    DUP _DBAS.ACTIONS @ SWAP DBAS-ACTION-COUNT@ DBAS-ACTION-SIZE RTAB-SEARCH ;

\ The action of the schedule RID names, or 0.
: DBAS-ACTION-OF  ( rid store -- action|0 )
    DUP _DBAS.ACTIONS @ SWAP DBAS-ACTION-COUNT@ DBAS-ACTION-SIZE RTAB-RECORD ;

: DBAS-FIND-KEY  ( key store -- index found? )
    DUP _DBAS.KEYS @ SWAP DBAS-KEY-COUNT@ DBAS-KEY-SIZE RTAB-SEARCH ;

\ Where occurrence ID is or belongs.
: DBAS-FIND-OCCURRENCE  ( id store -- index found? )
    DUP _DBAS.OCCURRENCES @ SWAP DBAS-OCCURRENCE-COUNT@
    DBAS-OCCURRENCE-SIZE RTAB-SEARCH-ID ;

\ The Agent run whose dispatch key is KEY, or 0.
: DBAS-FIND-KEYED  ( key store -- occurrence|0 )
    DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
        I OVER DBAS-OCCURRENCE
        DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT = IF
            DUP DBAS-O.KEY 32 4 PICK 32 COMPARE 0= IF
                NIP NIP UNLOOP EXIT
            THEN
        THEN
        DROP
    LOOP
    2DROP 0 ;

\ =====================================================================
\  Editing the tables
\ =====================================================================
\  The owner edits only a READY store, keeps every table sorted, and
\  commits.  A failed commit reloads the file and undoes the edits.

\ A zeroed schedule slot at INDEX.
: DBAS-INSERT-SCHEDULE  ( index store -- schedule status )
    DUP _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE RTAB-RESERVE IF
        2DROP 0 DBAS-S-NOMEM EXIT
    THEN
    _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE RTAB-INSERT DBAS-S-OK ;

\ A zeroed action slot at INDEX.
: DBAS-INSERT-ACTION  ( index store -- action status )
    DUP _DBAS.ACTIONS DBAS-ACTION-SIZE RTAB-RESERVE IF
        2DROP 0 DBAS-S-NOMEM EXIT
    THEN
    _DBAS.ACTIONS DBAS-ACTION-SIZE RTAB-INSERT DBAS-S-OK ;

\ A zeroed create-key slot at INDEX.
: DBAS-INSERT-KEY  ( index store -- key-record status )
    DUP _DBAS.KEYS DBAS-KEY-SIZE RTAB-RESERVE IF 2DROP 0 DBAS-S-NOMEM EXIT THEN
    _DBAS.KEYS DBAS-KEY-SIZE RTAB-INSERT DBAS-S-OK ;

\ A zeroed occurrence slot after every other: ids only increase.
: DBAS-APPEND-OCCURRENCE  ( store -- occurrence status )
    DUP _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE RTAB-RESERVE IF
        DROP 0 DBAS-S-NOMEM EXIT
    THEN
    DUP DBAS-OCCURRENCE-COUNT@ SWAP _DBAS.OCCURRENCES
        DBAS-OCCURRENCE-SIZE RTAB-INSERT DBAS-S-OK ;

\ Removes an action and its operands.
: DBAS-DELETE-ACTION  ( index store -- )
    2DUP DBAS-ACTION DBAS-A.OPERANDS _DBAS-BLOB-FREE
    _DBAS.ACTIONS DBAS-ACTION-SIZE RTAB-DELETE ;

\ Removes an occurrence and its summary.
: DBAS-DELETE-OCCURRENCE  ( index store -- )
    2DUP DBAS-OCCURRENCE DBAS-O.SUMMARY _DBAS-BLOB-FREE
    _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE RTAB-DELETE ;

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

\ The payload's parts.
: _DBAS-P-SCHEDULES  ( payload -- schedules ) DBAS-HEADER-SIZE + ;
: _DBAS-P-ACTIONS  ( payload -- actions )
    DUP _DBAS-P-SCHEDULES SWAP _DBAS-H.SCHEDULES @ DBAS-SCHEDULE-SIZE * + ;
: _DBAS-P-OCCURRENCES  ( payload -- occurrences )
    DUP _DBAS-P-ACTIONS SWAP _DBAS-H.ACTIONS @ DBAS-ACTION-SIZE * + ;
: _DBAS-P-KEYS  ( payload -- keys )
    DUP _DBAS-P-OCCURRENCES SWAP _DBAS-H.OCCURRENCES @
    DBAS-OCCURRENCE-SIZE * + ;
: _DBAS-P-BLOB  ( payload -- blob )
    DUP _DBAS-P-KEYS SWAP _DBAS-H.KEYS @ DBAS-KEY-SIZE * + ;

\ The schedule with RID among the payload's, or 0.
: _DBAS-P-SCHEDULE  ( rid payload -- schedule|0 )
    DUP _DBAS-P-SCHEDULES SWAP _DBAS-H.SCHEDULES @
    DBAS-SCHEDULE-SIZE RTAB-RECORD ;

: _DBAS-COUNT-OK?  ( n room element-u -- flag ) / 0 SWAP _DBAS-WITHIN? ;

\ The four tables' bytes for the counts in HEADER.
: _DBAS-TABLES-U  ( header -- bytes )
    DUP _DBAS-H.SCHEDULES @ DBAS-SCHEDULE-SIZE *
    OVER _DBAS-H.ACTIONS @ DBAS-ACTION-SIZE * +
    OVER _DBAS-H.OCCURRENCES @ DBAS-OCCURRENCE-SIZE * +
    SWAP _DBAS-H.KEYS @ DBAS-KEY-SIZE * + ;

\ The counts and the blob's size describe the payload exactly.
: _DBAS-GEOMETRY-OK?  ( payload payload-u -- flag )
    DUP DBAS-HEADER-SIZE < IF 2DROP 0 EXIT THEN
    DBAS-HEADER-SIZE -                       ( payload rest )
    OVER _DBAS-H.SCHEDULES @ OVER DBAS-SCHEDULE-SIZE _DBAS-COUNT-OK?
    0= IF 2DROP 0 EXIT THEN
    OVER _DBAS-H.ACTIONS @ OVER DBAS-ACTION-SIZE _DBAS-COUNT-OK?
    0= IF 2DROP 0 EXIT THEN
    OVER _DBAS-H.OCCURRENCES @ OVER DBAS-OCCURRENCE-SIZE _DBAS-COUNT-OK?
    0= IF 2DROP 0 EXIT THEN
    OVER _DBAS-H.KEYS @ OVER DBAS-KEY-SIZE _DBAS-COUNT-OK?
    0= IF 2DROP 0 EXIT THEN
    \ A negative blob would let the tables run past the payload.
    OVER _DBAS-H.BLOB @ 0< IF 2DROP 0 EXIT THEN
    OVER _DBAS-TABLES-U ROT _DBAS-H.BLOB @ + = ;

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
\ tombstone's zeroes or a schedule whose next instant matches its rule.
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
    OVER DBAS-S.ACTION @ DBAS-ACTION-REMINDER DBAS-ACTION-AGENT _DBAS-WITHIN? 0= OR
    OVER DBAS-S.LAST @ 0= 2 PICK DBAS-S.RESULT @ 0= <> OR
    OVER DBAS-S.RESULT @ 0 DBAS-MANUAL _DBAS-WITHIN? 0= OR
    OVER DBAS-S.PRUNED @ 0< OR
    OVER DBAS-S.TITLE _DBAS-TITLE-FIELD-OK? 0= OR
    IF R> 2DROP 0 EXIT THEN
    DUP DBAS-S.ZONE R@ _DBAS-ZONE-OK? 0= IF R> 2DROP 0 EXIT THEN
    DUP DBAS-S.RULE R@ DBREC-CHECK IF R> 2DROP 0 EXIT THEN
    R> _DBAS-NEXT-OK? ;

\ An action: one for a schedule that runs the Agent, with the permission
\ it names only when approved.  A tombstone's action is zero, so none
\ names one.  The blob check holds the schema and operands to the
\ catalog's.
: _DBAS-ACTION-OK?  ( action payload -- flag )
    OVER DBAS-A.RID SWAP _DBAS-P-SCHEDULE    ( action schedule|0 )
    ?DUP 0= IF DROP 0 EXIT THEN
    DBAS-S.ACTION @ OVER DBAS-A.ACTION @ <> IF DROP 0 EXIT THEN
    DUP DBAS-A.ACTION @ DBAS-ACTION-AGENT <> IF DROP 0 EXIT THEN
    DUP DBAS-A.AUTHORIZED @ 0= IF DBAS-A.PRACTICE 72 _DBAS-ZERO? EXIT THEN
    DUP DBAS-A.AUTHORIZED @ 1 <> IF DROP 0 EXIT THEN
    DUP DBAS-A.PRACTICE RID-ZERO?
    OVER DBAS-A.PERMISSION RID-ZERO? OR
    SWAP DBAS-A.PERMISSION-REVISION @ 1 < OR 0= ;

\ An on-time or missed occurrence covers ordinals of the schedule's rule.
: _DBAS-FIRING-OK?  ( occurrence -- flag )
    DUP DBAS-O.KIND @ DBAS-ON-TIME DBAS-MISSED _DBAS-WITHIN? 0= IF
        DROP 0 EXIT
    THEN
    DUP DBAS-O.BASIS @ DBAS-CONTINUOUS DBAS-JUMP _DBAS-WITHIN? 0= IF
        DROP 0 EXIT
    THEN
    DUP DBAS-O.FIRST @ 1 < IF DROP 0 EXIT THEN
    DUP DBAS-O.LAST @ OVER DBAS-O.FIRST @ < IF DROP 0 EXIT THEN
    DUP DBAS-O.COUNT @ 1 ROT DUP DBAS-O.LAST @ SWAP DBAS-O.FIRST @ - 1+
    _DBAS-WITHIN? ;

\ A run asked for by hand covers no ordinal.
: _DBAS-MANUAL-OK?  ( occurrence -- flag )
    DUP DBAS-O.BASIS @ DBAS-USER =
    OVER DBAS-O.ACTION @ DBAS-ACTION-AGENT = AND
    OVER DBAS-O.FIRST @ 0= AND
    OVER DBAS-O.LAST @ 0= AND
    SWAP DBAS-O.COUNT @ 1 = AND ;

\ A reminder's item awaits review or was reviewed, and holds no Agent
\ run's fields.
: _DBAS-REMINDER-ITEM-OK?  ( occurrence -- flag )
    DUP DBAS-O.STATE @ DBAS-DUE DBAS-REVIEWED _DBAS-WITHIN? 0= IF
        DROP 0 EXIT
    THEN
    DUP DBAS-O.PHASE 128 _DBAS-ZERO? 0= IF DROP 0 EXIT THEN
    DUP DBAS-O.STATE @ DBAS-DUE = IF DBAS-O.REVIEWED @ 0= EXIT THEN
    DROP -1 ;

\ A run not yet ended: its key, no outcome, end or summary.
: _DBAS-IN-FLIGHT-OK?  ( occurrence -- flag )
    DUP DBAS-O.STATE @ DBAS-IN-FLIGHT =
    OVER DBAS-O.KEY 32 _DBAS-ZERO? 0= AND
    OVER DBAS-O.OUTCOME 16 _DBAS-ZERO? AND
    OVER DBAS-O.ENDED @ 0= AND
    OVER DBAS-O.FLAGS @ 0= AND
    OVER DBAS-O.REVIEWED @ 0= AND
    SWAP DBAS-O.SUMMARY 8 + @ 0= AND ;

: _DBAS-ACCEPTED-OK?  ( occurrence -- flag )
    DUP _DBAS-IN-FLIGHT-OK?
    OVER DBAS-O.RUN 32 _DBAS-ZERO? AND
    SWAP DBAS-O.STARTED @ 0= AND ;

: _DBAS-RUNNING-OK?  ( occurrence -- flag )
    DUP _DBAS-IN-FLIGHT-OK? SWAP DBAS-O.RUN 32 _DBAS-ZERO? 0= AND ;

\ An ended run: a valid outcome and reason, review unless it completed,
\ the run's RID when the Agent started it and none when it never ran.  A
\ short record keeps no summary and awaits no review.
: _DBAS-ENDED-OK?  ( occurrence -- flag )
    DUP DBAS-O.OUTCOME @ OVER DBAS-O.REASON @ SACT-OUTCOME-OK? 0= IF
        DROP 0 EXIT
    THEN
    DUP DBAS-O.STATE @ DBAS-DUE DBAS-CLEAR _DBAS-WITHIN? 0= IF DROP 0 EXIT THEN
    DUP DBAS-O.OUTCOME @ SACT-O-COMPLETED =
    OVER DBAS-O.STATE @ DBAS-CLEAR = <> IF DROP 0 EXIT THEN
    DUP DBAS-O.STATE @ DBAS-DUE = OVER DBAS-O.REVIEWED @ 0<> AND IF
        DROP 0 EXIT
    THEN
    DUP DBAS-O.OUTCOME @
    DUP SACT-O-COMPLETED = OVER SACT-O-EXPIRED = OR SWAP SACT-O-STOPPED = OR
    OVER DBAS-O.RUN 32 _DBAS-ZERO? AND IF DROP 0 EXIT THEN
    DUP DBAS-O.OUTCOME @ DUP SACT-O-BLOCKED = SWAP SACT-O-NOT-STARTED = OR
    OVER DBAS-O.RUN 32 _DBAS-ZERO? 0= AND IF DROP 0 EXIT THEN
    DUP DBAS-O.FLAGS @ DBAS-F-AUDIT INVERT AND IF DROP 0 EXIT THEN
    DUP DBAS-O.FLAGS @ IF
        DUP DBAS-O.SUMMARY 8 + @ 0= SWAP DBAS-O.STATE @ DBAS-DUE <> AND EXIT
    THEN
    DROP -1 ;

: _DBAS-RUN-ITEM-OK?  ( occurrence -- flag )
    DUP DBAS-O.PHASE @ CASE
        DBAS-ACCEPTED OF _DBAS-ACCEPTED-OK? ENDOF
        DBAS-RUNNING  OF _DBAS-RUNNING-OK? ENDOF
        DBAS-ENDED    OF _DBAS-ENDED-OK? ENDOF
        >R DROP 0 R>
    ENDCASE ;

\ An occurrence: an id the counter has passed, a schedule at a revision it
\ has reached, and ordinals, instants and a count that agree.  A deleted
\ schedule keeps only the short records of its Agent runs; a live one's
\ occurrences take its action.
: _DBAS-OCCURRENCE-OK?  ( occurrence payload -- flag )
    OVER DBAS-O.ID @ 1 2 PICK DBAS-H.OCCURRENCE @ 1- _DBAS-WITHIN? 0= IF
        2DROP 0 EXIT
    THEN
    OVER _DBAS-O.RESERVED 8 _DBAS-ZERO? 0= IF 2DROP 0 EXIT THEN
    OVER DBAS-O.RID SWAP _DBAS-P-SCHEDULE    ( o schedule|0 )
    ?DUP 0= IF DROP 0 EXIT THEN
    DUP DBAS-S.STATE @ DBAS-TOMBSTONE =
    2 PICK DBAS-O.FLAGS @ DBAS-F-AUDIT AND 0<> <> IF 2DROP 0 EXIT THEN
    DUP DBAS-S.STATE @ DBAS-TOMBSTONE <> IF
        DUP DBAS-S.ACTION @ 2 PICK DBAS-O.ACTION @ <> IF 2DROP 0 EXIT THEN
    THEN
    DBAS-S.REVISION @ OVER DBAS-O.REVISION @ < IF DROP 0 EXIT THEN
    DUP DBAS-O.REVISION @ 1 <
    OVER DBAS-O.LAST-UTC @ 2 PICK DBAS-O.FIRST-UTC @ < OR
    IF DROP 0 EXIT THEN
    DUP DBAS-O.KIND @ DBAS-MANUAL = IF
        DUP _DBAS-MANUAL-OK?
    ELSE
        DUP _DBAS-FIRING-OK?
    THEN
    0= IF DROP 0 EXIT THEN
    DUP DBAS-O.ACTION @ DBAS-ACTION-REMINDER = IF _DBAS-REMINDER-ITEM-OK? EXIT THEN
    DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT = IF _DBAS-RUN-ITEM-OK? EXIT THEN
    DROP 0 ;

\ A create key: nonzero key bytes naming a schedule in the payload.
: _DBAS-KEY-OK?  ( key-record payload -- flag )
    OVER DBAS-K.KEY 32 _DBAS-ZERO? IF 2DROP 0 EXIT THEN
    SWAP DBAS-K.RID SWAP _DBAS-P-SCHEDULE 0<> ;

: _DBAS-SCHEDULES-OK?  ( payload zone -- flag )
    OVER _DBAS-P-SCHEDULES 2 PICK _DBAS-H.SCHEDULES @   ( p zone s n )
    2DUP DBAS-SCHEDULE-SIZE RTAB-ASCENDING? 0= IF 2DROP 2DROP 0 EXIT THEN
    0 ?DO                                               ( p zone s )
        DUP 3 PICK 3 PICK _DBAS-SCHEDULE-OK? 0= IF
            2DROP DROP 0 UNLOOP EXIT
        THEN
        DBAS-SCHEDULE-SIZE +
    LOOP
    2DROP DROP -1 ;

\ How many live schedules run the Agent.
: _DBAS-AGENTS  ( payload -- n )
    0 OVER _DBAS-P-SCHEDULES ROT _DBAS-H.SCHEDULES @ 0 ?DO   ( n s )
        DUP DBAS-S.STATE @ DBAS-TOMBSTONE <>
        OVER DBAS-S.ACTION @ DBAS-ACTION-AGENT = AND
        IF SWAP 1+ SWAP THEN
        DBAS-SCHEDULE-SIZE +
    LOOP
    DROP ;

\ Exactly one action per live schedule that runs the Agent.
: _DBAS-ACTIONS-OK?  ( payload -- flag )
    DUP _DBAS-AGENTS OVER _DBAS-H.ACTIONS @ <> IF DROP 0 EXIT THEN
    DUP _DBAS-P-ACTIONS OVER _DBAS-H.ACTIONS @            ( p a n )
    2DUP DBAS-ACTION-SIZE RTAB-ASCENDING? 0= IF 2DROP DROP 0 EXIT THEN
    0 ?DO
        DUP 2 PICK _DBAS-ACTION-OK? 0= IF 2DROP 0 UNLOOP EXIT THEN
        DBAS-ACTION-SIZE +
    LOOP
    2DROP -1 ;

: _DBAS-OCCURRENCES-OK?  ( payload -- flag )
    DUP _DBAS-P-OCCURRENCES OVER _DBAS-H.OCCURRENCES @   ( p o n )
    2DUP DBAS-OCCURRENCE-SIZE RTAB-IDS-ASCENDING? 0= IF 2DROP DROP 0 EXIT THEN
    0 ?DO
        DUP 2 PICK _DBAS-OCCURRENCE-OK? 0= IF 2DROP 0 UNLOOP EXIT THEN
        DBAS-OCCURRENCE-SIZE +
    LOOP
    2DROP -1 ;

\ Two runs in flight may not share a schedule or a dispatch key.
: _DBAS-CLASH?  ( a b -- flag )
    OVER DBAS-O.RID OVER DBAS-O.RID RID= IF 2DROP -1 EXIT THEN
    DBAS-O.KEY 32 ROT DBAS-O.KEY 32 COMPARE 0= ;

: _DBAS-IN-FLIGHT?  ( occurrence -- flag )
    DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT =
    SWAP DBAS-O.STATE @ DBAS-IN-FLIGHT = AND ;

\ At most one run in flight per schedule, each with its own key.
: _DBAS-FLIGHTS-OK?  ( payload -- flag )
    DUP _DBAS-P-OCCURRENCES SWAP _DBAS-H.OCCURRENCES @     ( o n )
    DUP 0 ?DO
        OVER I DBAS-OCCURRENCE-SIZE * + _DBAS-IN-FLIGHT? IF
            DUP I 1+ ?DO
                OVER I DBAS-OCCURRENCE-SIZE * +
                DUP _DBAS-IN-FLIGHT? IF
                    2 PICK J DBAS-OCCURRENCE-SIZE * + _DBAS-CLASH? IF
                        2DROP 0 UNLOOP UNLOOP EXIT
                    THEN
                ELSE DROP THEN
            LOOP
        THEN
    LOOP
    2DROP -1 ;

: _DBAS-KEYS-OK?  ( payload -- flag )
    DUP _DBAS-P-KEYS OVER _DBAS-H.KEYS @                 ( p k n )
    2DUP DBAS-KEY-SIZE RTAB-ASCENDING? 0= IF 2DROP DROP 0 EXIT THEN
    0 ?DO
        DUP 2 PICK _DBAS-KEY-OK? 0= IF 2DROP 0 UNLOOP EXIT THEN
        DBAS-KEY-SIZE +
    LOOP
    2DROP -1 ;

\ ---------------------------------------------------------------------
\  The blob
\ ---------------------------------------------------------------------
\  Each action's operands, then each occurrence's summary, in table order,
\  each padded with zeroes to a cell.  Nothing else is in it.

VARIABLE _DBAS-BLOB-A      \ the blob being read or written
VARIABLE _DBAS-BLOB-U
VARIABLE _DBAS-AT          \ the offset of the next part, or -1

\ The bytes the file blob slot at SLOT names, when they are the next part
\ and their padding is zero; otherwise 0 0, and _DBAS-AT becomes -1.
: _DBAS-REF  ( slot -- address u )
    _DBAS-AT @ 0< IF DROP 0 0 EXIT THEN
    DUP 8 + @ ?DUP 0= IF
        @ IF -1 _DBAS-AT ! THEN 0 0 EXIT
    THEN                                     ( slot u )
    OVER @ _DBAS-AT @ <> OVER _DBAS-BLOB-U @ U> OR IF
        2DROP -1 _DBAS-AT ! 0 0 EXIT
    THEN
    NIP                                      ( u )
    DUP 7 + -8 AND _DBAS-AT @ + DUP _DBAS-BLOB-U @ U> IF
        2DROP -1 _DBAS-AT ! 0 0 EXIT
    THEN                                     ( u end )
    _DBAS-BLOB-A @ _DBAS-AT @ + 2 PICK +
    OVER _DBAS-AT @ - 3 PICK -
    _DBAS-ZERO? 0= IF 2DROP -1 _DBAS-AT ! 0 0 EXIT THEN
    _DBAS-BLOB-A @ _DBAS-AT @ + ROT
    ROT _DBAS-AT ! ;

\ Every action's operands check out, every summary is a line of text, and
\ the parts fill the blob exactly.
: _DBAS-BLOBS-OK?  ( payload -- flag )
    DUP _DBAS-P-BLOB _DBAS-BLOB-A !
    DUP _DBAS-H.BLOB @ _DBAS-BLOB-U !
    0 _DBAS-AT !
    DUP _DBAS-P-ACTIONS OVER _DBAS-H.ACTIONS @ 0 ?DO         ( p a )
        DUP DBAS-A.OPERANDS _DBAS-REF                        ( p a addr u )
        >R >R DUP DBAS-A.ACTION @ OVER DBAS-A.SCHEMA @ R> R>
        SACT-OPERANDS-OK? IF 2DROP 0 UNLOOP EXIT THEN
        DBAS-ACTION-SIZE +
    LOOP
    DROP
    DUP _DBAS-P-OCCURRENCES OVER _DBAS-H.OCCURRENCES @ 0 ?DO  ( p o )
        DUP DBAS-O.SUMMARY _DBAS-REF SACT-LINE-OK? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        DBAS-OCCURRENCE-SIZE +
    LOOP
    DROP
    _DBAS-AT @ SWAP _DBAS-H.BLOB @ = ;

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
    DUP _DBAS-ACTIONS-OK? 0= IF R> 2DROP CREC-S-SEMANTIC EXIT THEN
    DUP _DBAS-OCCURRENCES-OK? 0= IF R> 2DROP CREC-S-SEMANTIC EXIT THEN
    DUP _DBAS-FLIGHTS-OK? 0= IF R> 2DROP CREC-S-SEMANTIC EXIT THEN
    DUP _DBAS-BLOBS-OK? 0= IF R> 2DROP CREC-S-SEMANTIC EXIT THEN
    _DBAS-KEYS-OK? R> DROP IF CREC-S-OK ELSE CREC-S-SEMANTIC THEN ;

\ ---------------------------------------------------------------------
\  Writing the payload
\ ---------------------------------------------------------------------

\ The padded bytes of the blobs at OFFSET of TABLE's records.
: _DBAS-SLOTS-U  ( table element-u offset -- bytes )
    0 3 PICK RTAB-COUNT@ 0 ?DO               ( table u off bytes )
        I 4 PICK 4 PICK RTAB-NTH 2 PICK + 8 + @ 7 + -8 AND +
    LOOP
    NIP NIP NIP ;

: _DBAS-BLOB-SIZE  ( store -- bytes )
    DUP _DBAS.ACTIONS DBAS-ACTION-SIZE _DBAS-A-OPERANDS _DBAS-SLOTS-U
    SWAP _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-O-SUMMARY _DBAS-SLOTS-U + ;

\ Copies a written record's blob into the blob at _DBAS-AT, zero-padded,
\ and sets its slot to that offset.
: _DBAS-PUT-SLOT  ( slot -- )
    DUP 8 + @ 0= IF 0 SWAP ! EXIT THEN
    DUP @ _DBAS-BLOB-A @ _DBAS-AT @ + 2 PICK 8 + @ MOVE
    DUP 8 + @ _DBAS-BLOB-A @ _DBAS-AT @ + OVER +       ( slot u pad-start )
    SWAP DUP 7 + -8 AND SWAP - 0 FILL
    _DBAS-AT @ OVER !
    8 + @ 7 + -8 AND _DBAS-AT +! ;

\ Puts the blobs of N written records at RECORDS, whose slots lie at
\ OFFSET.
: _DBAS-PUT-BLOBS  ( records n element-u offset -- )
    ROT 0 ?DO                                ( records u off )
        2 PICK I 3 PICK * + OVER + _DBAS-PUT-SLOT
    LOOP
    2DROP DROP ;

: _DBAS-ENCODE  ( store store-u payload payload-u tag -- status )
    2DROP NIP                                ( store payload )
    OVER DBAS-HEADER OVER DBAS-HEADER-SIZE MOVE
    OVER DBAS-SCHEDULE-COUNT@ OVER _DBAS-H.SCHEDULES !
    OVER DBAS-ACTION-COUNT@ OVER _DBAS-H.ACTIONS !
    OVER DBAS-OCCURRENCE-COUNT@ OVER _DBAS-H.OCCURRENCES !
    OVER DBAS-KEY-COUNT@ OVER _DBAS-H.KEYS !
    OVER _DBAS-BLOB-SIZE OVER _DBAS-H.BLOB !
    DUP DBAS-HEADER-SIZE +                   ( store payload at )
    2 PICK _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE RTAB-PUT
    2 PICK _DBAS.ACTIONS DBAS-ACTION-SIZE RTAB-PUT
    2 PICK _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE RTAB-PUT
    2 PICK _DBAS.KEYS DBAS-KEY-SIZE RTAB-PUT ( store payload blob )
    _DBAS-BLOB-A ! 0 _DBAS-AT !
    DUP _DBAS-P-ACTIONS OVER _DBAS-H.ACTIONS @
        DBAS-ACTION-SIZE _DBAS-A-OPERANDS _DBAS-PUT-BLOBS
    DUP _DBAS-P-OCCURRENCES SWAP _DBAS-H.OCCURRENCES @
        DBAS-OCCURRENCE-SIZE _DBAS-O-SUMMARY _DBAS-PUT-BLOBS
    DROP CREC-S-OK ;

: _DBAS-PAYLOAD-U  ( store -- payload-u )
    DUP DBAS-SCHEDULE-COUNT@ DBAS-SCHEDULE-SIZE *
    OVER DBAS-ACTION-COUNT@ DBAS-ACTION-SIZE * +
    OVER DBAS-OCCURRENCE-COUNT@ DBAS-OCCURRENCE-SIZE * +
    OVER DBAS-KEY-COUNT@ DBAS-KEY-SIZE * +
    SWAP _DBAS-BLOB-SIZE + DBAS-HEADER-SIZE + ;

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

\ Copies the payload's tables into the store's empty tables.
: _DBAS-TAKE-TABLES  ( payload store -- status )
    OVER _DBAS-P-SCHEDULES 2 PICK _DBAS-H.SCHEDULES @
        2 PICK _DBAS.SCHEDULES DBAS-SCHEDULE-SIZE RTAB-TAKE
    IF 2DROP DBAS-S-NOMEM EXIT THEN
    OVER _DBAS-P-ACTIONS 2 PICK _DBAS-H.ACTIONS @
        2 PICK _DBAS.ACTIONS DBAS-ACTION-SIZE RTAB-TAKE
    IF 2DROP DBAS-S-NOMEM EXIT THEN
    OVER _DBAS-P-OCCURRENCES 2 PICK _DBAS-H.OCCURRENCES @
        2 PICK _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE RTAB-TAKE
    IF 2DROP DBAS-S-NOMEM EXIT THEN
    OVER _DBAS-P-KEYS 2 PICK _DBAS-H.KEYS @
        2 PICK _DBAS.KEYS DBAS-KEY-SIZE RTAB-TAKE
    IF 2DROP DBAS-S-NOMEM EXIT THEN
    2DROP DBAS-S-OK ;

\ Empties the blob slots of TABLE's records from index FROM on: they
\ hold file offsets that no record owns.
: _DBAS-FORGET  ( from table element-u offset -- )
    2 PICK RTAB-COUNT@ 4 ROLL ?DO            ( table u off )
        I 3 PICK 3 PICK RTAB-NTH OVER + 16 0 FILL
    LOOP
    2DROP DROP ;

: _DBAS-FORGET-ALL  ( store -- )
    0 OVER _DBAS.ACTIONS DBAS-ACTION-SIZE _DBAS-A-OPERANDS _DBAS-FORGET
    0 SWAP _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-O-SUMMARY _DBAS-FORGET ;

\ A copy of the blob bytes a file slot names, which the record owns from
\ now on.  A slot that cannot get memory keeps its offset.
: _DBAS-OWN-SLOT  ( blob slot -- status )
    DUP 8 + @ 0= IF 2DROP DBAS-S-OK EXIT THEN
    DUP 8 + @ ALLOCATE IF DROP 2DROP DBAS-S-NOMEM EXIT THEN   ( blob slot new )
    ROT 2 PICK @ +                           ( slot new source )
    OVER 3 PICK 8 + @ MOVE
    SWAP ! DBAS-S-OK ;

\ Turns TABLE's file offsets into copies its records own.  On failure no
\ slot of TABLE holds an offset.
: _DBAS-OWN-TABLE  ( blob table element-u offset -- status )
    2 PICK RTAB-COUNT@ 0 ?DO                 ( blob table u off )
        I 3 PICK 3 PICK RTAB-NTH OVER +      ( blob table u off slot )
        4 PICK SWAP _DBAS-OWN-SLOT IF
            I 3 PICK 3 PICK 3 PICK _DBAS-FORGET
            2DROP 2DROP DBAS-S-NOMEM UNLOOP EXIT
        THEN
    LOOP
    2DROP 2DROP DBAS-S-OK ;

: _DBAS-OWN-ALL  ( payload store -- status )
    OVER _DBAS-P-BLOB OVER _DBAS.ACTIONS DBAS-ACTION-SIZE _DBAS-A-OPERANDS
    _DBAS-OWN-TABLE ?DUP IF
        >R 0 OVER _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-O-SUMMARY
        _DBAS-FORGET 2DROP R> EXIT
    THEN
    SWAP _DBAS-P-BLOB SWAP _DBAS.OCCURRENCES DBAS-OCCURRENCE-SIZE _DBAS-O-SUMMARY
    _DBAS-OWN-TABLE ;

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
    \ In memory the tables keep their own counts, and the blob is theirs.
    R@ DBAS-HEADER _DBAS-H.SCHEDULES 24 0 FILL
    0 R@ DBAS-HEADER _DBAS-H.ACTIONS !
    0 R@ DBAS-HEADER _DBAS-H.BLOB !
    DUP R@ _DBAS-TAKE-TABLES ?DUP IF
        R@ _DBAS-FORGET-ALL NIP R> DROP EXIT
    THEN
    R> _DBAS-OWN-ALL ;

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

\ Drops edits not yet committed by reading the file again.
: DBAS-REVERT  ( store -- status )
    DUP DBAS-VALID? 0= IF DROP DBAS-S-INVALID EXIT THEN
    DUP DBAS-STATE@ DBAS-READY <> IF
        DBAS-STATE@ DBAS-BLOCKED = IF DBAS-S-BLOCKED ELSE DBAS-S-STATE THEN
        EXIT
    THEN
    DBAS-S-OK SWAP _DBAS-RELOAD ;

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
    _DBAS-MAGIC$ _DBAS-FORMAT CREC-TAG-POSITIVE ['] _DBAS-ENCODE ['] _DBAS-VALIDATE
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
