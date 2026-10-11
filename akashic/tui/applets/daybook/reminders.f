\ =====================================================================
\  reminders.f - Daybook's view of its reminders
\ =====================================================================
\  The view lists the reminders in the service Desk lends, in sections:
\
\    NEEDS REVIEW  firings awaiting review, newest first
\    ACTIVE        enabled reminders, soonest first
\    PAUSED        paused reminders, oldest first
\    COMPLETED     series with nothing left to fire, oldest first
\    ARCHIVED      archived reminders, when the view shows them
\
\  Each row has a title and a detail: when a reminder fires next, in its
\  own zone, or how a firing went.  A row names its record by position.
\  Every action therefore first checks that the store has not changed
\  since the rows were built.  If it has, the action does nothing and asks
\  for a rebuild, so it never lands on a record the user did not see.
\  Actions name the revision or the last firing the row showed.
\
\  The view is caller-owned and caller-serialized.  It borrows the
\  service, which is 0 when Daybook runs outside Desk.  Row words take an
\  index below DBRV-COUNT@; actions check theirs.
\
\  Public API:
\    DBRV-INIT        ( service view -- )
\    DBRV-FREE        ( view -- )
\    DBRV-STALE?      ( view -- flag )
\    DBRV-REBUILD     ( view -- status )
\    DBRV-COUNT@      ( view -- n )
\    DBRV-ROW         ( index view -- kind position )
\    DBRV-REMINDER?   ( index view -- flag )
\    DBRV-KEY         ( index view -- key )
\    DBRV-TITLE       ( index view -- address length )
\    DBRV-DETAIL      ( index view -- address length )
\    DBRV-NOTE        ( view -- address length )
\    DBRV-ARCHIVED@   ( view -- flag )
\    DBRV-ARCHIVED!   ( flag view -- )
\    DBRV-REVIEW DBRV-PAUSE DBRV-ARCHIVE DBRV-DELETE
\                     ( index view -- status )
\    DBRV-MESSAGE     ( status -- address length )
\ =====================================================================

PROVIDED akashic-dbk-reminders

REQUIRE automation-service.f
REQUIRE ../../../utils/string.f

\ Row kinds.
0 CONSTANT DBRV-HEADING          \ position: the section
1 CONSTANT DBRV-REMINDER         \ position: the schedule's index
2 CONSTANT DBRV-FIRING           \ position: the occurrence's index

\ Sections.
1 CONSTANT DBRV-REVIEW-SECTION
2 CONSTANT DBRV-ACTIVE-SECTION
3 CONSTANT DBRV-PAUSED-SECTION
4 CONSTANT DBRV-COMPLETED-SECTION
5 CONSTANT DBRV-ARCHIVED-SECTION

\ View statuses beyond the owner's.
20 CONSTANT DBRV-S-CHANGED       \ the store changed since the rows were built
21 CONSTANT DBRV-S-NONE          \ the row has no such action
22 CONSTANT DBRV-S-NOMEM

\ The longest detail: "missed 1000000000, last 9999-12-31 23:59".
48 CONSTANT _DBRV-DETAIL-MAX

0x5745495652424442 CONSTANT _DBRV-MAGIC  \ "BDBRVIEW"

 0 CONSTANT _DBRV-MAGIC-OFF
 8 CONSTANT _DBRV-SERVICE
16 CONSTANT _DBRV-ROWS          \ the rows: kind and position, two cells each
24 CONSTANT _DBRV-COUNT
32 CONSTANT _DBRV-ROOM
40 CONSTANT _DBRV-BUILT         \ the store generation at the build, plus one
48 CONSTANT _DBRV-BUILT-STATE   \ the store state at the build
56 CONSTANT _DBRV-ARCHIVED      \ the view shows archived reminders
64 CONSTANT _DBRV-HELD          \ scratch: a row held while sorting
80 CONSTANT _DBRV-LEN           \ the detail's length
88 CONSTANT _DBRV-TEXT
_DBRV-TEXT _DBRV-DETAIL-MAX + 7 + -8 AND CONSTANT _DBRV-ZONE
_DBRV-ZONE TZ-SIZE + 7 + -8 AND CONSTANT DBRV-SIZE

: _DBRV.SERVICE  ( view -- a ) _DBRV-SERVICE + ;
: _DBRV.ROWS     ( view -- a ) _DBRV-ROWS + ;
: _DBRV.COUNT    ( view -- a ) _DBRV-COUNT + ;
: _DBRV.ROOM     ( view -- a ) _DBRV-ROOM + ;
: _DBRV.BUILT    ( view -- a ) _DBRV-BUILT + ;
: _DBRV.BUILT-STATE  ( view -- a ) _DBRV-BUILT-STATE + ;
: _DBRV.ARCHIVED ( view -- a ) _DBRV-ARCHIVED + ;
: _DBRV.HELD     ( view -- a ) _DBRV-HELD + ;
: _DBRV.LEN      ( view -- a ) _DBRV-LEN + ;
: _DBRV.TEXT     ( view -- a ) _DBRV-TEXT + ;
: _DBRV.ZONE     ( view -- zone ) _DBRV-ZONE + ;

\ Starts a view over SERVICE, which may be 0.
: DBRV-INIT  ( service view -- )
    DUP DBRV-SIZE 0 FILL
    _DBRV-MAGIC OVER _DBRV-MAGIC-OFF + !
    _DBRV.SERVICE ! ;

: DBRV-FREE  ( view -- )
    DUP _DBRV.ROWS @ ?DUP IF FREE THEN
    0 OVER _DBRV.ROWS ! 0 OVER _DBRV.COUNT ! 0 SWAP _DBRV.ROOM ! ;

: _DBRV-OWNER  ( view -- owner ) _DBRV.SERVICE @ DBSVC-OWNER ;
: _DBRV-STORE  ( view -- store ) _DBRV-OWNER DBAO-STORE ;

\ The store's state, or DBAS-CLOSED without a service.
: _DBRV-STATE  ( view -- state )
    DUP _DBRV.SERVICE @ 0= IF DROP DBAS-CLOSED EXIT THEN
    _DBRV-STORE DBAS-STATE@ ;

: _DBRV-GENERATION  ( view -- n )
    DUP _DBRV.SERVICE @ 0= IF DROP 1 EXIT THEN
    _DBRV-STORE DBAS-GENERATION@ 1+ ;

\ Whether the rows are older than the store.
: DBRV-STALE?  ( view -- flag )
    DUP _DBRV-GENERATION OVER _DBRV.BUILT @ <>
    SWAP DUP _DBRV-STATE SWAP _DBRV.BUILT-STATE @ <> OR ;

: DBRV-COUNT@  ( view -- n ) _DBRV.COUNT @ ;

: DBRV-ARCHIVED@  ( view -- flag ) _DBRV.ARCHIVED @ ;

\ Shows or hides archived reminders; the rows are then stale.
: DBRV-ARCHIVED!  ( flag view -- )
    TUCK _DBRV.ARCHIVED ! 0 SWAP _DBRV.BUILT ! ;

\ =====================================================================
\  Rows
\ =====================================================================

: _DBRV-AT  ( index view -- row ) _DBRV.ROWS @ SWAP 16 * + ;

\ The kind and position of row INDEX.
: DBRV-ROW  ( index view -- kind position ) _DBRV-AT DUP @ SWAP 8 + @ ;

\ Room for one more row.
: _DBRV-ROOM  ( view -- status )
    DUP _DBRV.COUNT @ OVER _DBRV.ROOM @ < IF DROP DBAO-S-OK EXIT THEN
    DUP _DBRV.ROOM @ 2 * 16 MAX                ( view room' )
    DUP 16 * ALLOCATE IF 2DROP DROP DBRV-S-NOMEM EXIT THEN
                                               ( view room' new )
    2 PICK _DBRV.ROWS @ ?DUP IF
        OVER 4 PICK _DBRV.COUNT @ 16 * MOVE
        2 PICK _DBRV.ROWS @ FREE
    THEN
    2 PICK _DBRV.ROWS ! SWAP _DBRV.ROOM ! DBAO-S-OK ;

: _DBRV-ADD  ( kind position view -- status )
    DUP _DBRV-ROOM ?DUP IF NIP NIP NIP EXIT THEN
    DUP _DBRV.COUNT @ OVER _DBRV-AT            ( kind position view row )
    ROT OVER 8 + ! ROT SWAP !
    1 SWAP _DBRV.COUNT +! DBAO-S-OK ;

\ Which section a schedule shows in, or 0 for none.
: _DBRV-SECTION-OF  ( schedule view -- section )
    OVER DBAS-S.STATE @ DBAS-TOMBSTONE = IF 2DROP 0 EXIT THEN
    OVER DBAS-S.ARCHIVED @ IF
        DBRV-ARCHIVED@ IF DROP DBRV-ARCHIVED-SECTION ELSE DROP 0 THEN EXIT
    THEN
    DROP DBAS-S.STATE @ CASE
        DBAS-ENABLED OF DBRV-ACTIVE-SECTION ENDOF
        DBAS-PAUSED OF DBRV-PAUSED-SECTION ENDOF
        DBAS-COMPLETED OF DBRV-COMPLETED-SECTION ENDOF
        0 SWAP
    ENDCASE ;

\ What orders a section's reminders: the next instant for active ones,
\ creation order for the rest.
: _DBRV-ORDER  ( position section view -- n )
    ROT SWAP _DBRV-STORE DBAS-SCHEDULE         ( section schedule )
    SWAP DBRV-ACTIVE-SECTION = IF DBAS-S.NEXT-UTC @ ELSE DBAS-S.SERIAL @ THEN ;

\ Sorts rows FIRST to the end, all of SECTION, by their order: an
\ insertion sort, as it runs only when the store changes.
: _DBRV-SORT  ( first section view -- )
    >R OVER 1+                                 ( first section i ; R: view )
    BEGIN DUP R@ _DBRV.COUNT @ < WHILE
        DUP R@ _DBRV-AT R@ _DBRV.HELD 16 MOVE
        DUP                                    ( first section i j )
        BEGIN
            DUP 4 PICK > IF
                DUP 1- R@ _DBRV-AT 8 + @ 3 PICK R@ _DBRV-ORDER
                R@ _DBRV.HELD 8 + @ 4 PICK R@ _DBRV-ORDER >
            ELSE
                0
            THEN
        WHILE
            DUP 1- R@ _DBRV-AT OVER R@ _DBRV-AT 16 MOVE
            1-
        REPEAT
        R@ _DBRV.HELD SWAP R@ _DBRV-AT 16 MOVE
        1+
    REPEAT
    DROP 2DROP R> DROP ;

\ Adds a section of reminders: its heading, then its rows in order.  A
\ section with none shows no heading.
: _DBRV-SECTION  ( section view -- status )
    DUP DBRV-COUNT@ 1+ >R                      ( section view ; R: first )
    DBRV-HEADING 2 PICK 2 PICK _DBRV-ADD ?DUP IF NIP NIP R> DROP EXIT THEN
    0                                          ( section view i )
    BEGIN DUP 2 PICK _DBRV-STORE DBAS-SCHEDULE-COUNT@ < WHILE
        DUP 2 PICK _DBRV-STORE DBAS-SCHEDULE 2 PICK _DBRV-SECTION-OF
        3 PICK = IF
            DBRV-REMINDER OVER 3 PICK _DBRV-ADD ?DUP IF
                NIP NIP NIP R> DROP EXIT
            THEN
        THEN
        1+
    REPEAT
    DROP
    DUP DBRV-COUNT@ R@ = IF -1 OVER _DBRV.COUNT +! THEN
    R> ROT ROT _DBRV-SORT DBAO-S-OK ;

\ Adds the firings awaiting review, newest first.
: _DBRV-FIRINGS  ( view -- status )
    DUP DBRV-COUNT@ 1+ >R
    DBRV-HEADING DBRV-REVIEW-SECTION 2 PICK _DBRV-ADD ?DUP IF
        NIP R> DROP EXIT
    THEN
    DUP _DBRV-STORE DBAS-OCCURRENCE-COUNT@     ( view i )
    BEGIN DUP WHILE
        1-
        DUP 2 PICK _DBRV-STORE DBAS-OCCURRENCE DBAS-O.STATE @ DBAS-DUE = IF
            DBRV-FIRING OVER 3 PICK _DBRV-ADD ?DUP IF NIP NIP R> DROP EXIT THEN
        THEN
    REPEAT
    DROP
    DUP DBRV-COUNT@ R> = IF -1 SWAP _DBRV.COUNT +! ELSE DROP THEN
    DBAO-S-OK ;

: _DBRV-BUILD  ( view -- status )
    DUP _DBRV-FIRINGS ?DUP IF NIP EXIT THEN
    DBRV-ACTIVE-SECTION OVER _DBRV-SECTION ?DUP IF NIP EXIT THEN
    DBRV-PAUSED-SECTION OVER _DBRV-SECTION ?DUP IF NIP EXIT THEN
    DBRV-COMPLETED-SECTION OVER _DBRV-SECTION ?DUP IF NIP EXIT THEN
    DUP DBRV-ARCHIVED@ IF
        DBRV-ARCHIVED-SECTION OVER _DBRV-SECTION ?DUP IF NIP EXIT THEN
    THEN
    DROP DBAO-S-OK ;

\ Builds the rows from the store as it is now.  A store that is not ready
\ has none; DBRV-NOTE says why.
: DBRV-REBUILD  ( view -- status )
    0 OVER _DBRV.COUNT !
    DUP _DBRV-GENERATION OVER _DBRV.BUILT !
    DUP _DBRV-STATE OVER _DBRV.BUILT-STATE !
    DUP _DBRV-STATE DBAS-READY <> IF DROP DBAO-S-OK EXIT THEN
    DUP _DBRV-BUILD ?DUP IF
        0 2 PICK _DBRV.COUNT ! 0 ROT _DBRV.BUILT ! EXIT
    THEN
    DROP DBAO-S-OK ;

\ A row's key: headings by section, reminders by serial, firings by id.
: DBRV-KEY  ( index view -- key )
    TUCK DBRV-ROW                              ( view kind position )
    OVER DBRV-HEADING = IF NIP NIP EXIT THEN
    SWAP DBRV-FIRING = IF
        SWAP _DBRV-STORE DBAS-OCCURRENCE DBAS-O.ID @ 2 * 17 +
    ELSE
        SWAP _DBRV-STORE DBAS-SCHEDULE DBAS-S.SERIAL @ 2 * 16 +
    THEN ;

\ =====================================================================
\  Text
\ =====================================================================

: _DBRV-HEADING$  ( section -- address length )
    CASE
        DBRV-REVIEW-SECTION OF S" NEEDS REVIEW" ENDOF
        DBRV-ACTIVE-SECTION OF S" ACTIVE" ENDOF
        DBRV-PAUSED-SECTION OF S" PAUSED" ENDOF
        DBRV-COMPLETED-SECTION OF S" COMPLETED" ENDOF
        S" ARCHIVED" ROT
    ENDCASE ;

\ The reminder a firing belongs to.
: _DBRV-FIRING-SCHEDULE  ( position view -- schedule|0 )
    TUCK _DBRV-STORE DBAS-OCCURRENCE DBAS-O.RID SWAP _DBRV-OWNER DBAO-FIND ;

\ The title of row INDEX: a section's name, or its reminder's title.
: DBRV-TITLE  ( index view -- address length )
    TUCK DBRV-ROW                              ( view kind position )
    OVER DBRV-HEADING = IF NIP NIP _DBRV-HEADING$ EXIT THEN
    SWAP DBRV-FIRING = IF
        SWAP _DBRV-FIRING-SCHEDULE
    ELSE
        SWAP _DBRV-STORE DBAS-SCHEDULE
    THEN
    ?DUP 0= IF 0 0 EXIT THEN
    DBAS-S.TITLE DBAS-FIELD$ ;

\ Appends text to the detail, as much as fits.
: _DBRV-ADD$  ( address length view -- )
    >R _DBRV-DETAIL-MAX R@ _DBRV.LEN @ - MIN 0 MAX
    TUCK R@ _DBRV.TEXT R@ _DBRV.LEN @ + SWAP MOVE
    R> _DBRV.LEN +! ;

: _DBRV-CHAR  ( char view -- )
    DUP _DBRV.LEN @ _DBRV-DETAIL-MAX < 0= IF 2DROP EXIT THEN
    TUCK DUP _DBRV.TEXT SWAP _DBRV.LEN @ + C!
    1 SWAP _DBRV.LEN +! ;

: _DBRV-2D  ( n view -- )
    >R 100 MOD DUP 10 / [CHAR] 0 + R@ _DBRV-CHAR
    10 MOD [CHAR] 0 + R> _DBRV-CHAR ;

\ Appends an instant as "YYYY-MM-DD HH:MM" in the reminder's zone.
: _DBRV-WHEN  ( utc schedule view -- )
    >R
    DBAS-S.ZONE DBAS-FIELD$ R@ _DBRV.ZONE TZ-PARSE IF DROP R> DROP EXIT THEN
    R@ _DBRV.ZONE TZ-UTC>LOCAL IF DROP R> DROP EXIT THEN
    DUP R@ _DBRV.TEXT R@ _DBRV.LEN @ +
        _DBRV-DETAIL-MAX R@ _DBRV.LEN @ - DT-DATE-S
    IF 2DROP R> DROP EXIT THEN
    R@ _DBRV.LEN +!
    BL R@ _DBRV-CHAR
    86400 MOD 60 / DUP 60 / R@ _DBRV-2D
    [CHAR] : R@ _DBRV-CHAR
    60 MOD R> _DBRV-2D ;

: _DBRV-REMINDER$  ( position view -- )
    TUCK _DBRV-STORE DBAS-SCHEDULE             ( view schedule )
    DUP DBAS-S.ARCHIVED @ IF DROP S" archived" ROT _DBRV-ADD$ EXIT THEN
    DUP DBAS-S.STATE @ CASE
        DBAS-ENABLED OF
            S" next " 3 PICK _DBRV-ADD$
            DUP DBAS-S.NEXT-UTC @ OVER 3 PICK _DBRV-WHEN
        ENDOF
        DBAS-PAUSED OF S" paused" 3 PICK _DBRV-ADD$ ENDOF
        DBAS-COMPLETED OF S" done" 3 PICK _DBRV-ADD$ ENDOF
    ENDCASE
    2DROP ;

: _DBRV-FIRING$  ( position view -- )
    TUCK _DBRV-STORE DBAS-OCCURRENCE           ( view item )
    DUP DBAS-O.KIND @ DBAS-MISSED = IF
        S" missed" 3 PICK _DBRV-ADD$
        DUP DBAS-O.COUNT @ 1 > IF
            BL 2 PICK _DBRV-CHAR
            DUP DBAS-O.COUNT @ NUM>STR 3 PICK _DBRV-ADD$
            S" , last" 3 PICK _DBRV-ADD$
        THEN
    ELSE
        S" fired" 3 PICK _DBRV-ADD$
    THEN
    BL 2 PICK _DBRV-CHAR
    DUP DBAS-O.LAST-UTC @                      ( view item utc )
    OVER DBAS-O.RID 3 PICK _DBRV-OWNER DBAO-FIND
    ?DUP IF 3 PICK _DBRV-WHEN ELSE DROP THEN
    2DROP ;

\ The detail of row INDEX: when a reminder fires next, or how a firing
\ went.  The text stays put until the next call.
: DBRV-DETAIL  ( index view -- address length )
    0 OVER _DBRV.LEN !
    TUCK DBRV-ROW                              ( view kind position )
    OVER DBRV-HEADING = IF 2DROP DROP 0 0 EXIT THEN
    SWAP DBRV-FIRING = IF OVER _DBRV-FIRING$ ELSE OVER _DBRV-REMINDER$ THEN
    DUP _DBRV.TEXT SWAP _DBRV.LEN @ ;

\ Why the view shows no reminders, or that they wait, or nothing.
: DBRV-NOTE  ( view -- address length )
    DUP _DBRV.SERVICE @ 0= IF DROP S" Reminders run inside Desk" EXIT THEN
    DUP _DBRV-STORE DBAS-STATE@ DBAS-BLOCKED = IF
        _DBRV-STORE DBAS-REASON@ CASE
            DBAS-R-CORRUPT OF
                S" Reminders unavailable: the file is damaged" ENDOF
            DBAS-R-FUTURE OF
                S" Reminders unavailable: saved by a newer Daybook" ENDOF
            DBAS-R-UNCERTAIN OF
                S" Reminders unavailable until Desk restarts" ENDOF
            S" Reminders unavailable: the file could not be read" ROT
        ENDCASE
        EXIT
    THEN
    _DBRV.SERVICE @ DBSVC-CLOCK@ DBRUN-CLOCK-UNSET = IF
        S" The clock is not set; reminders wait" EXIT
    THEN
    0 0 ;

\ =====================================================================
\  Actions
\ =====================================================================
\  Each acts on the record its row showed, with the revision or the last
\  firing the row showed, and only while the rows are current.

: _DBRV-INDEX?  ( index view -- flag )
    DBRV-COUNT@ 0 SWAP WITHIN ;

\ Whether row INDEX shows a reminder.
: DBRV-REMINDER?  ( index view -- flag )
    2DUP _DBRV-INDEX? 0= IF 2DROP 0 EXIT THEN
    DBRV-ROW DROP DBRV-REMINDER = ;

\ The reminder row INDEX shows, while the rows are current.
: _DBRV-REMINDER  ( index view -- schedule status )
    DUP DBRV-STALE? IF 2DROP 0 DBRV-S-CHANGED EXIT THEN
    2DUP _DBRV-INDEX? 0= IF 2DROP 0 DBRV-S-NONE EXIT THEN
    TUCK DBRV-ROW SWAP DBRV-REMINDER <> IF 2DROP 0 DBRV-S-NONE EXIT THEN
    SWAP _DBRV-STORE DBAS-SCHEDULE DBAO-S-OK ;

\ Marks the firing row INDEX shows reviewed.
: DBRV-REVIEW  ( index view -- status )
    DUP DBRV-STALE? IF 2DROP DBRV-S-CHANGED EXIT THEN
    2DUP _DBRV-INDEX? 0= IF 2DROP DBRV-S-NONE EXIT THEN
    TUCK DBRV-ROW SWAP DBRV-FIRING <> IF 2DROP DBRV-S-NONE EXIT THEN
    OVER _DBRV-STORE DBAS-OCCURRENCE           ( view item )
    DUP DBAS-O.ID @ SWAP DBAS-O.LAST @ DBSVC-NOW 3 PICK _DBRV-OWNER
        DBAO-REVIEW
    NIP ;

\ Pauses an enabled reminder or resumes a paused one.
: DBRV-PAUSE  ( index view -- status )
    TUCK _DBRV-REMINDER ?DUP IF NIP NIP EXIT THEN   ( view schedule )
    DUP DBAS-S.STATE @ CASE
        DBAS-ENABLED OF
            DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBRV-OWNER DBAO-PAUSE
        ENDOF
        DBAS-PAUSED OF
            DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBRV-OWNER DBAO-RESUME
        ENDOF
        DBRV-S-NONE SWAP
    ENDCASE
    NIP NIP ;

\ Archives a reminder, or brings an archived one back.
: DBRV-ARCHIVE  ( index view -- status )
    TUCK _DBRV-REMINDER ?DUP IF NIP NIP EXIT THEN
    DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBRV-OWNER
    3 PICK DBAS-S.ARCHIVED @ IF DBAO-UNARCHIVE ELSE DBAO-ARCHIVE THEN
    NIP NIP ;

\ Deletes a reminder.
: DBRV-DELETE  ( index view -- status )
    TUCK _DBRV-REMINDER ?DUP IF NIP NIP EXIT THEN
    DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBRV-OWNER DBAO-DELETE
    NIP NIP ;

\ What an action's status means to the user.
: DBRV-MESSAGE  ( status -- address length )
    CASE
        DBAO-S-OK OF S" Done" ENDOF
        DBAO-S-CLOCK OF S" Set the clock first" ENDOF
        DBAO-S-CONFLICT OF S" The reminder changed; look again" ENDOF
        DBRV-S-CHANGED OF S" Reminders changed; look again" ENDOF
        DBAO-S-DELETED OF S" That reminder was deleted" ENDOF
        DBAO-S-BLOCKED OF S" Reminders are unavailable" ENDOF
        DBAO-S-IO OF S" Could not save reminders" ENDOF
        DBRV-S-NONE OF S" Nothing to do for that row" ENDOF
        S" The reminder could not be changed" ROT
    ENDCASE ;
