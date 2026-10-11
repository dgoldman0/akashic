\ =====================================================================
\  automation-view.f - Daybook's view of its automations
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
\  A create takes three steps, as a prompt asks for them: when and the
\  title ("HH:MM title" for the next such time, or "YYYY-MM-DD HH:MM
\  title"), how it repeats, and its zone, where an empty answer means the
\  default zone.  DBAV-BEGIN draws a fresh create key for each create, so
\  a create submitted twice makes one reminder.
\
\  The view is caller-owned and caller-serialized.  It borrows the
\  service, which is 0 when Daybook runs outside Desk.  Row words take an
\  index below DBAV-COUNT@; actions check theirs.
\
\  Public API:
\    DBAV-INIT        ( service view -- )
\    DBAV-FREE        ( view -- )
\    DBAV-STALE?      ( view -- flag )
\    DBAV-REBUILD     ( view -- status )
\    DBAV-COUNT@      ( view -- n )
\    DBAV-ROW         ( index view -- kind position )
\    DBAV-REMINDER?   ( index view -- flag )
\    DBAV-KEY         ( index view -- key )
\    DBAV-TITLE       ( index view -- address length )
\    DBAV-DETAIL      ( index view -- address length )
\    DBAV-NOTE        ( view -- address length )
\    DBAV-ARCHIVED@   ( view -- flag )
\    DBAV-ARCHIVED!   ( flag view -- )
\    DBAV-REVIEW DBAV-PAUSE DBAV-ARCHIVE DBAV-DELETE
\                     ( index view -- status )
\    DBAV-SERVICE?    ( view -- flag )
\    DBAV-BEGIN       ( view -- status )
\    DBAV-WHEN!       ( address length view -- status )
\    DBAV-REPEAT!     ( address length view -- status )
\    DBAV-CREATE      ( zone-a zone-u view -- status )
\    DBAV-DEFAULT-ZONE$  ( view -- address length )
\    DBAV-DEFAULT-ZONE!  ( address length view -- status )
\    DBAV-MESSAGE     ( status -- address length )
\ =====================================================================

PROVIDED akashic-dbk-auto-view

REQUIRE automation-service.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../math/entropy.f

\ Row kinds.
0 CONSTANT DBAV-HEADING          \ position: the section
1 CONSTANT DBAV-REMINDER         \ position: the schedule's index
2 CONSTANT DBAV-FIRING           \ position: the occurrence's index

\ Sections.
1 CONSTANT DBAV-REVIEW-SECTION
2 CONSTANT DBAV-ACTIVE-SECTION
3 CONSTANT DBAV-PAUSED-SECTION
4 CONSTANT DBAV-COMPLETED-SECTION
5 CONSTANT DBAV-ARCHIVED-SECTION

\ View statuses beyond the owner's.
40 CONSTANT DBAV-S-CHANGED       \ the store changed since the rows were built
41 CONSTANT DBAV-S-NONE          \ the row has no such action
42 CONSTANT DBAV-S-NOMEM
43 CONSTANT DBAV-S-WHEN          \ not "HH:MM title" or "YYYY-MM-DD HH:MM title"
44 CONSTANT DBAV-S-REPEAT        \ not a repeat the view knows

\ The longest detail: "missed 1000000000, last 9999-12-31 23:59".
48 CONSTANT _DBAV-DETAIL-MAX

0x5745495641424442 CONSTANT _DBAV-MAGIC  \ "BDBAVIEW"

 0 CONSTANT _DBAV-MAGIC-OFF
 8 CONSTANT _DBAV-SERVICE
16 CONSTANT _DBAV-ROWS          \ the rows: kind and position, two cells each
24 CONSTANT _DBAV-COUNT
32 CONSTANT _DBAV-ROOM
40 CONSTANT _DBAV-BUILT         \ the store generation at the build, plus one
48 CONSTANT _DBAV-BUILT-STATE   \ the store state at the build
56 CONSTANT _DBAV-ARCHIVED      \ the view shows archived reminders
64 CONSTANT _DBAV-HELD          \ scratch: a row held while sorting
80 CONSTANT _DBAV-LEN           \ the detail's length
88 CONSTANT _DBAV-TEXT
_DBAV-TEXT _DBAV-DETAIL-MAX + 7 + -8 AND CONSTANT _DBAV-ZONE
\ A create in progress: the day (local seconds, or -1 for the next such
\ time), the minute, the create key, the new RID, and the draft.
_DBAV-ZONE TZ-SIZE + 7 + -8 AND CONSTANT _DBAV-DAY
_DBAV-DAY 8 + CONSTANT _DBAV-MINUTE
_DBAV-MINUTE 8 + CONSTANT _DBAV-KEY
_DBAV-KEY RID-SIZE + CONSTANT _DBAV-RID
_DBAV-RID RID-SIZE + CONSTANT _DBAV-DRAFT
_DBAV-DRAFT DBAO-DRAFT-SIZE + 7 + -8 AND CONSTANT DBAV-SIZE

: _DBAV.SERVICE  ( view -- a ) _DBAV-SERVICE + ;
: _DBAV.ROWS     ( view -- a ) _DBAV-ROWS + ;
: _DBAV.COUNT    ( view -- a ) _DBAV-COUNT + ;
: _DBAV.ROOM     ( view -- a ) _DBAV-ROOM + ;
: _DBAV.BUILT    ( view -- a ) _DBAV-BUILT + ;
: _DBAV.BUILT-STATE  ( view -- a ) _DBAV-BUILT-STATE + ;
: _DBAV.ARCHIVED ( view -- a ) _DBAV-ARCHIVED + ;
: _DBAV.HELD     ( view -- a ) _DBAV-HELD + ;
: _DBAV.LEN      ( view -- a ) _DBAV-LEN + ;
: _DBAV.TEXT     ( view -- a ) _DBAV-TEXT + ;
: _DBAV.ZONE     ( view -- zone ) _DBAV-ZONE + ;
: _DBAV.DAY      ( view -- a ) _DBAV-DAY + ;
: _DBAV.MINUTE   ( view -- a ) _DBAV-MINUTE + ;
: _DBAV.KEY      ( view -- key ) _DBAV-KEY + ;
: _DBAV.RID      ( view -- rid ) _DBAV-RID + ;
: _DBAV.DRAFT    ( view -- draft ) _DBAV-DRAFT + ;

\ Starts a view over SERVICE, which may be 0.
: DBAV-INIT  ( service view -- )
    DUP DBAV-SIZE 0 FILL
    _DBAV-MAGIC OVER _DBAV-MAGIC-OFF + !
    _DBAV.SERVICE ! ;

: DBAV-FREE  ( view -- )
    DUP _DBAV.ROWS @ ?DUP IF FREE THEN
    0 OVER _DBAV.ROWS ! 0 OVER _DBAV.COUNT ! 0 SWAP _DBAV.ROOM ! ;

: _DBAV-OWNER  ( view -- owner ) _DBAV.SERVICE @ DBSVC-OWNER ;
: _DBAV-STORE  ( view -- store ) _DBAV-OWNER DBAO-STORE ;

\ The store's state, or DBAS-CLOSED without a service.
: _DBAV-STATE  ( view -- state )
    DUP _DBAV.SERVICE @ 0= IF DROP DBAS-CLOSED EXIT THEN
    _DBAV-STORE DBAS-STATE@ ;

: _DBAV-GENERATION  ( view -- n )
    DUP _DBAV.SERVICE @ 0= IF DROP 1 EXIT THEN
    _DBAV-STORE DBAS-GENERATION@ 1+ ;

\ Whether the rows are older than the store.
: DBAV-STALE?  ( view -- flag )
    DUP _DBAV-GENERATION OVER _DBAV.BUILT @ <>
    SWAP DUP _DBAV-STATE SWAP _DBAV.BUILT-STATE @ <> OR ;

: DBAV-COUNT@  ( view -- n ) _DBAV.COUNT @ ;

: DBAV-ARCHIVED@  ( view -- flag ) _DBAV.ARCHIVED @ ;

\ Shows or hides archived reminders; the rows are then stale.
: DBAV-ARCHIVED!  ( flag view -- )
    TUCK _DBAV.ARCHIVED ! 0 SWAP _DBAV.BUILT ! ;

\ =====================================================================
\  Rows
\ =====================================================================

: _DBAV-AT  ( index view -- row ) _DBAV.ROWS @ SWAP 16 * + ;

\ The kind and position of row INDEX.
: DBAV-ROW  ( index view -- kind position ) _DBAV-AT DUP @ SWAP 8 + @ ;

\ Room for one more row.
: _DBAV-ROOM  ( view -- status )
    DUP _DBAV.COUNT @ OVER _DBAV.ROOM @ < IF DROP DBAO-S-OK EXIT THEN
    DUP _DBAV.ROOM @ 2 * 16 MAX                ( view room' )
    DUP 16 * ALLOCATE IF 2DROP DROP DBAV-S-NOMEM EXIT THEN
                                               ( view room' new )
    2 PICK _DBAV.ROWS @ ?DUP IF
        OVER 4 PICK _DBAV.COUNT @ 16 * MOVE
        2 PICK _DBAV.ROWS @ FREE
    THEN
    2 PICK _DBAV.ROWS ! SWAP _DBAV.ROOM ! DBAO-S-OK ;

: _DBAV-ADD  ( kind position view -- status )
    DUP _DBAV-ROOM ?DUP IF NIP NIP NIP EXIT THEN
    DUP _DBAV.COUNT @ OVER _DBAV-AT            ( kind position view row )
    ROT OVER 8 + ! ROT SWAP !
    1 SWAP _DBAV.COUNT +! DBAO-S-OK ;

\ Which section a schedule shows in, or 0 for none.
: _DBAV-SECTION-OF  ( schedule view -- section )
    OVER DBAS-S.STATE @ DBAS-TOMBSTONE = IF 2DROP 0 EXIT THEN
    OVER DBAS-S.ARCHIVED @ IF
        DBAV-ARCHIVED@ IF DROP DBAV-ARCHIVED-SECTION ELSE DROP 0 THEN EXIT
    THEN
    DROP DBAS-S.STATE @ CASE
        DBAS-ENABLED OF DBAV-ACTIVE-SECTION ENDOF
        DBAS-PAUSED OF DBAV-PAUSED-SECTION ENDOF
        DBAS-COMPLETED OF DBAV-COMPLETED-SECTION ENDOF
        0 SWAP
    ENDCASE ;

\ What orders a section's reminders: the next instant for active ones,
\ creation order for the rest.
: _DBAV-ORDER  ( position section view -- n )
    ROT SWAP _DBAV-STORE DBAS-SCHEDULE         ( section schedule )
    SWAP DBAV-ACTIVE-SECTION = IF DBAS-S.NEXT-UTC @ ELSE DBAS-S.SERIAL @ THEN ;

\ Sorts rows FIRST to the end, all of SECTION, by their order: an
\ insertion sort, as it runs only when the store changes.
: _DBAV-SORT  ( first section view -- )
    >R OVER 1+                                 ( first section i ; R: view )
    BEGIN DUP R@ _DBAV.COUNT @ < WHILE
        DUP R@ _DBAV-AT R@ _DBAV.HELD 16 MOVE
        DUP                                    ( first section i j )
        BEGIN
            DUP 4 PICK > IF
                DUP 1- R@ _DBAV-AT 8 + @ 3 PICK R@ _DBAV-ORDER
                R@ _DBAV.HELD 8 + @ 4 PICK R@ _DBAV-ORDER >
            ELSE
                0
            THEN
        WHILE
            DUP 1- R@ _DBAV-AT OVER R@ _DBAV-AT 16 MOVE
            1-
        REPEAT
        R@ _DBAV.HELD SWAP R@ _DBAV-AT 16 MOVE
        1+
    REPEAT
    DROP 2DROP R> DROP ;

\ Adds a section of reminders: its heading, then its rows in order.  A
\ section with none shows no heading.
: _DBAV-SECTION  ( section view -- status )
    DUP DBAV-COUNT@ 1+ >R                      ( section view ; R: first )
    DBAV-HEADING 2 PICK 2 PICK _DBAV-ADD ?DUP IF NIP NIP R> DROP EXIT THEN
    0                                          ( section view i )
    BEGIN DUP 2 PICK _DBAV-STORE DBAS-SCHEDULE-COUNT@ < WHILE
        DUP 2 PICK _DBAV-STORE DBAS-SCHEDULE 2 PICK _DBAV-SECTION-OF
        3 PICK = IF
            DBAV-REMINDER OVER 3 PICK _DBAV-ADD ?DUP IF
                NIP NIP NIP R> DROP EXIT
            THEN
        THEN
        1+
    REPEAT
    DROP
    DUP DBAV-COUNT@ R@ = IF -1 OVER _DBAV.COUNT +! THEN
    R> ROT ROT _DBAV-SORT DBAO-S-OK ;

\ Adds the firings awaiting review, newest first.
: _DBAV-FIRINGS  ( view -- status )
    DUP DBAV-COUNT@ 1+ >R
    DBAV-HEADING DBAV-REVIEW-SECTION 2 PICK _DBAV-ADD ?DUP IF
        NIP R> DROP EXIT
    THEN
    DUP _DBAV-STORE DBAS-OCCURRENCE-COUNT@     ( view i )
    BEGIN DUP WHILE
        1-
        DUP 2 PICK _DBAV-STORE DBAS-OCCURRENCE DBAS-O.STATE @ DBAS-DUE = IF
            DBAV-FIRING OVER 3 PICK _DBAV-ADD ?DUP IF NIP NIP R> DROP EXIT THEN
        THEN
    REPEAT
    DROP
    DUP DBAV-COUNT@ R> = IF -1 SWAP _DBAV.COUNT +! ELSE DROP THEN
    DBAO-S-OK ;

: _DBAV-BUILD  ( view -- status )
    DUP _DBAV-FIRINGS ?DUP IF NIP EXIT THEN
    DBAV-ACTIVE-SECTION OVER _DBAV-SECTION ?DUP IF NIP EXIT THEN
    DBAV-PAUSED-SECTION OVER _DBAV-SECTION ?DUP IF NIP EXIT THEN
    DBAV-COMPLETED-SECTION OVER _DBAV-SECTION ?DUP IF NIP EXIT THEN
    DUP DBAV-ARCHIVED@ IF
        DBAV-ARCHIVED-SECTION OVER _DBAV-SECTION ?DUP IF NIP EXIT THEN
    THEN
    DROP DBAO-S-OK ;

\ Builds the rows from the store as it is now.  A store that is not ready
\ has none; DBAV-NOTE says why.
: DBAV-REBUILD  ( view -- status )
    0 OVER _DBAV.COUNT !
    DUP _DBAV-GENERATION OVER _DBAV.BUILT !
    DUP _DBAV-STATE OVER _DBAV.BUILT-STATE !
    DUP _DBAV-STATE DBAS-READY <> IF DROP DBAO-S-OK EXIT THEN
    DUP _DBAV-BUILD ?DUP IF
        0 2 PICK _DBAV.COUNT ! 0 ROT _DBAV.BUILT ! EXIT
    THEN
    DROP DBAO-S-OK ;

\ A row's key: headings by section, reminders by serial, firings by id.
: DBAV-KEY  ( index view -- key )
    TUCK DBAV-ROW                              ( view kind position )
    OVER DBAV-HEADING = IF NIP NIP EXIT THEN
    SWAP DBAV-FIRING = IF
        SWAP _DBAV-STORE DBAS-OCCURRENCE DBAS-O.ID @ 2 * 17 +
    ELSE
        SWAP _DBAV-STORE DBAS-SCHEDULE DBAS-S.SERIAL @ 2 * 16 +
    THEN ;

\ =====================================================================
\  Text
\ =====================================================================

: _DBAV-HEADING$  ( section -- address length )
    CASE
        DBAV-REVIEW-SECTION OF S" NEEDS REVIEW" ENDOF
        DBAV-ACTIVE-SECTION OF S" ACTIVE" ENDOF
        DBAV-PAUSED-SECTION OF S" PAUSED" ENDOF
        DBAV-COMPLETED-SECTION OF S" COMPLETED" ENDOF
        S" ARCHIVED" ROT
    ENDCASE ;

\ The reminder a firing belongs to.
: _DBAV-FIRING-SCHEDULE  ( position view -- schedule|0 )
    TUCK _DBAV-STORE DBAS-OCCURRENCE DBAS-O.RID SWAP _DBAV-OWNER DBAO-FIND ;

\ The title of row INDEX: a section's name, or its reminder's title.
: DBAV-TITLE  ( index view -- address length )
    TUCK DBAV-ROW                              ( view kind position )
    OVER DBAV-HEADING = IF NIP NIP _DBAV-HEADING$ EXIT THEN
    SWAP DBAV-FIRING = IF
        SWAP _DBAV-FIRING-SCHEDULE
    ELSE
        SWAP _DBAV-STORE DBAS-SCHEDULE
    THEN
    ?DUP 0= IF 0 0 EXIT THEN
    DBAS-S.TITLE DBAS-FIELD$ ;

\ Appends text to the detail, as much as fits.
: _DBAV-ADD$  ( address length view -- )
    >R _DBAV-DETAIL-MAX R@ _DBAV.LEN @ - MIN 0 MAX
    TUCK R@ _DBAV.TEXT R@ _DBAV.LEN @ + SWAP MOVE
    R> _DBAV.LEN +! ;

: _DBAV-CHAR  ( char view -- )
    DUP _DBAV.LEN @ _DBAV-DETAIL-MAX < 0= IF 2DROP EXIT THEN
    TUCK DUP _DBAV.TEXT SWAP _DBAV.LEN @ + C!
    1 SWAP _DBAV.LEN +! ;

: _DBAV-2D  ( n view -- )
    >R 100 MOD DUP 10 / [CHAR] 0 + R@ _DBAV-CHAR
    10 MOD [CHAR] 0 + R> _DBAV-CHAR ;

\ Appends an instant as "YYYY-MM-DD HH:MM" in the reminder's zone.
: _DBAV-WHEN  ( utc schedule view -- )
    >R
    DBAS-S.ZONE DBAS-FIELD$ R@ _DBAV.ZONE TZ-PARSE IF DROP R> DROP EXIT THEN
    R@ _DBAV.ZONE TZ-UTC>LOCAL IF DROP R> DROP EXIT THEN
    DUP R@ _DBAV.TEXT R@ _DBAV.LEN @ +
        _DBAV-DETAIL-MAX R@ _DBAV.LEN @ - DT-DATE-S
    IF 2DROP R> DROP EXIT THEN
    R@ _DBAV.LEN +!
    BL R@ _DBAV-CHAR
    86400 MOD 60 / DUP 60 / R@ _DBAV-2D
    [CHAR] : R@ _DBAV-CHAR
    60 MOD R> _DBAV-2D ;

: _DBAV-REMINDER$  ( position view -- )
    TUCK _DBAV-STORE DBAS-SCHEDULE             ( view schedule )
    DUP DBAS-S.ARCHIVED @ IF DROP S" archived" ROT _DBAV-ADD$ EXIT THEN
    DUP DBAS-S.STATE @ CASE
        DBAS-ENABLED OF
            S" next " 3 PICK _DBAV-ADD$
            DUP DBAS-S.NEXT-UTC @ OVER 3 PICK _DBAV-WHEN
        ENDOF
        DBAS-PAUSED OF S" paused" 3 PICK _DBAV-ADD$ ENDOF
        DBAS-COMPLETED OF S" done" 3 PICK _DBAV-ADD$ ENDOF
    ENDCASE
    2DROP ;

: _DBAV-FIRING$  ( position view -- )
    TUCK _DBAV-STORE DBAS-OCCURRENCE           ( view item )
    DUP DBAS-O.KIND @ DBAS-MISSED = IF
        S" missed" 3 PICK _DBAV-ADD$
        DUP DBAS-O.COUNT @ 1 > IF
            BL 2 PICK _DBAV-CHAR
            DUP DBAS-O.COUNT @ NUM>STR 3 PICK _DBAV-ADD$
            S" , last" 3 PICK _DBAV-ADD$
        THEN
    ELSE
        S" fired" 3 PICK _DBAV-ADD$
    THEN
    BL 2 PICK _DBAV-CHAR
    DUP DBAS-O.LAST-UTC @                      ( view item utc )
    OVER DBAS-O.RID 3 PICK _DBAV-OWNER DBAO-FIND
    ?DUP IF 3 PICK _DBAV-WHEN ELSE DROP THEN
    2DROP ;

\ The detail of row INDEX: when a reminder fires next, or how a firing
\ went.  The text stays put until the next call.
: DBAV-DETAIL  ( index view -- address length )
    0 OVER _DBAV.LEN !
    TUCK DBAV-ROW                              ( view kind position )
    OVER DBAV-HEADING = IF 2DROP DROP 0 0 EXIT THEN
    SWAP DBAV-FIRING = IF OVER _DBAV-FIRING$ ELSE OVER _DBAV-REMINDER$ THEN
    DUP _DBAV.TEXT SWAP _DBAV.LEN @ ;

\ Why the view shows no reminders, or that they wait, or nothing.
: DBAV-NOTE  ( view -- address length )
    DUP _DBAV.SERVICE @ 0= IF DROP S" Automations run inside Desk" EXIT THEN
    DUP _DBAV-STORE DBAS-STATE@ DBAS-BLOCKED = IF
        _DBAV-STORE DBAS-REASON@ CASE
            DBAS-R-CORRUPT OF
                S" Automations unavailable: the file is damaged" ENDOF
            DBAS-R-FUTURE OF
                S" Automations unavailable: saved by a newer Daybook" ENDOF
            DBAS-R-UNCERTAIN OF
                S" Automations unavailable until Desk restarts" ENDOF
            S" Automations unavailable: the file could not be read" ROT
        ENDCASE
        EXIT
    THEN
    _DBAV.SERVICE @ DBSVC-CLOCK@ DBRUN-CLOCK-UNSET = IF
        S" The clock is not set; automations wait" EXIT
    THEN
    0 0 ;

\ =====================================================================
\  Actions
\ =====================================================================
\  Each acts on the record its row showed, with the revision or the last
\  firing the row showed, and only while the rows are current.

: _DBAV-INDEX?  ( index view -- flag )
    DBAV-COUNT@ 0 SWAP WITHIN ;

\ Whether row INDEX shows a reminder.
: DBAV-REMINDER?  ( index view -- flag )
    2DUP _DBAV-INDEX? 0= IF 2DROP 0 EXIT THEN
    DBAV-ROW DROP DBAV-REMINDER = ;

\ The reminder row INDEX shows, while the rows are current.
: _DBAV-REMINDER  ( index view -- schedule status )
    DUP DBAV-STALE? IF 2DROP 0 DBAV-S-CHANGED EXIT THEN
    2DUP _DBAV-INDEX? 0= IF 2DROP 0 DBAV-S-NONE EXIT THEN
    TUCK DBAV-ROW SWAP DBAV-REMINDER <> IF 2DROP 0 DBAV-S-NONE EXIT THEN
    SWAP _DBAV-STORE DBAS-SCHEDULE DBAO-S-OK ;

\ Marks the firing row INDEX shows reviewed.
: DBAV-REVIEW  ( index view -- status )
    DUP DBAV-STALE? IF 2DROP DBAV-S-CHANGED EXIT THEN
    2DUP _DBAV-INDEX? 0= IF 2DROP DBAV-S-NONE EXIT THEN
    TUCK DBAV-ROW SWAP DBAV-FIRING <> IF 2DROP DBAV-S-NONE EXIT THEN
    OVER _DBAV-STORE DBAS-OCCURRENCE           ( view item )
    DUP DBAS-O.ID @ SWAP DBAS-O.LAST @ DBSVC-NOW 3 PICK _DBAV-OWNER
        DBAO-REVIEW
    NIP ;

\ Pauses an enabled reminder or resumes a paused one.
: DBAV-PAUSE  ( index view -- status )
    TUCK _DBAV-REMINDER ?DUP IF NIP NIP EXIT THEN   ( view schedule )
    DUP DBAS-S.STATE @ CASE
        DBAS-ENABLED OF
            DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBAV-OWNER DBAO-PAUSE
        ENDOF
        DBAS-PAUSED OF
            DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBAV-OWNER DBAO-RESUME
        ENDOF
        DBAV-S-NONE SWAP
    ENDCASE
    NIP NIP ;

\ Archives a reminder, or brings an archived one back.
: DBAV-ARCHIVE  ( index view -- status )
    TUCK _DBAV-REMINDER ?DUP IF NIP NIP EXIT THEN
    DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBAV-OWNER
    3 PICK DBAS-S.ARCHIVED @ IF DBAO-UNARCHIVE ELSE DBAO-ARCHIVE THEN
    NIP NIP ;

\ Deletes a reminder.
: DBAV-DELETE  ( index view -- status )
    TUCK _DBAV-REMINDER ?DUP IF NIP NIP EXIT THEN
    DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBAV-OWNER DBAO-DELETE
    NIP NIP ;

\ =====================================================================
\  Creating
\ =====================================================================

\ Whether there are reminders to work: Daybook runs inside Desk.
: DBAV-SERVICE?  ( view -- flag ) _DBAV.SERVICE @ 0<> ;

\ Starts a create: an empty reminder draft and a fresh create key.
: DBAV-BEGIN  ( view -- status )
    DUP _DBAV.SERVICE @ 0= IF DROP DBAO-S-STATE EXIT THEN
    DUP _DBAV.DRAFT DBAO-DRAFT-SIZE 0 FILL
    DBAS-ACTION-REMINDER OVER _DBAV.DRAFT DBAO-D.ACTION !
    -1 OVER _DBAV.DAY ! 0 OVER _DBAV.MINUTE !
    _DBAV.KEY RID-SIZE ENTROPY-FILL ENTROPY-S-OK <> IF
        DBAO-S-ENTROPY EXIT
    THEN
    DBAO-S-OK ;

\ The value of N decimal digits.
: _DBAV-DIGITS  ( address n -- value ok? )
    0 SWAP 0 ?DO                               ( address value )
        OVER I + C@ DUP [CHAR] 0 [CHAR] 9 1+ WITHIN 0= IF
            2DROP DROP 0 0 UNLOOP EXIT
        THEN
        [CHAR] 0 - SWAP 10 * +
    LOOP
    NIP -1 ;

\ "HH:MM" as minutes past midnight.
: _DBAV-HHMM  ( address -- minute ok? )
    DUP 2 + C@ [CHAR] : <> IF DROP 0 0 EXIT THEN
    DUP 2 _DBAV-DIGITS 0= IF 2DROP 0 0 EXIT THEN
    DUP 23 > IF 2DROP 0 0 EXIT THEN            ( address hours )
    SWAP 3 + 2 _DBAV-DIGITS 0= IF 2DROP 0 0 EXIT THEN
    DUP 59 > IF 2DROP 0 0 EXIT THEN
    SWAP 60 * + -1 ;

\ "YYYY-MM-DD" as the local seconds of its midnight.
: _DBAV-DATE  ( address -- day ok? )
    DUP 4 + C@ [CHAR] - <> OVER 7 + C@ [CHAR] - <> OR IF DROP 0 0 EXIT THEN
    DUP 4 _DBAV-DIGITS 0= IF 2DROP 0 0 EXIT THEN
    OVER 5 + 2 _DBAV-DIGITS 0= IF 2DROP DROP 0 0 EXIT THEN
    ROT 8 + 2 _DBAV-DIGITS 0= IF 2DROP DROP 0 0 EXIT THEN
    DT-YMD>EPOCH-S IF DROP 0 0 ELSE -1 THEN ;

\ The first step: "HH:MM title", the next time it is HH:MM, or
\ "YYYY-MM-DD HH:MM title".
: DBAV-WHEN!  ( address length view -- status )
    >R
    -1 R@ _DBAV.DAY !
    DUP 17 > IF
        OVER 10 + C@ BL = IF
            OVER _DBAV-DATE IF
                R@ _DBAV.DAY ! SWAP 11 + SWAP 11 -
            ELSE
                DROP
            THEN
        THEN
    THEN
    DUP 7 < IF 2DROP R> DROP DBAV-S-WHEN EXIT THEN
    OVER 5 + C@ BL <> IF 2DROP R> DROP DBAV-S-WHEN EXIT THEN
    OVER _DBAV-HHMM 0= IF DROP 2DROP R> DROP DBAV-S-WHEN EXIT THEN
    R@ _DBAV.MINUTE !
    SWAP 6 + SWAP 6 -
    2DUP DBAS-TITLE-OK? 0= IF 2DROP R> DROP DBAO-S-TITLE EXIT THEN
    R> _DBAV.DRAFT DBAO-D.TITLE DBAS-TITLE-MAX DBAS-FIELD!
    DBAO-S-OK ;

\ An answer lowercased into the detail scratch, which it may fill.
: _DBAV-LOWER  ( address length view -- address' length' )
    _DBAV.TEXT SWAP _DBAV-DETAIL-MAX MIN 0 MAX     ( address text n )
    DUP >R 0 ?DO
        OVER I + C@ DUP [CHAR] A [CHAR] Z 1+ WITHIN IF 32 OR THEN
        OVER I + C!
    LOOP
    NIP R> ;

: _DBAV-IS?  ( address length word-a word-u -- address length flag )
    2OVER COMPARE 0= ;

\ The second step: once (or nothing), daily, weekdays (Monday to
\ Friday), weekly, monthly or yearly, every one from the start.
: DBAV-REPEAT!  ( address length view -- status )
    DUP >R _DBAV-LOWER
    R> _DBAV.DRAFT DBAO-D.RULE >R              ( address length ; R: rule )
    1 R@ DBREC.INTERVAL ! DBREC-END-NEVER R@ DBREC.END !
    0 R@ DBREC.WEEKDAYS ! 0 R@ DBREC.MONTH-MODE !
    0 R@ DBREC.MONTH-DAY ! 0 R@ DBREC.MONTH-WEEKDAY !
    0 R@ DBREC.LIMIT !
    DUP 0= IF 2DROP DBREC-ONCE R> DBREC.FREQ ! DBAO-S-OK EXIT THEN
    S" once" _DBAV-IS? IF 2DROP DBREC-ONCE R> DBREC.FREQ ! DBAO-S-OK EXIT THEN
    S" daily" _DBAV-IS? IF 2DROP DBREC-DAILY R> DBREC.FREQ ! DBAO-S-OK EXIT THEN
    S" weekly" _DBAV-IS? IF 2DROP DBREC-WEEKLY R> DBREC.FREQ ! DBAO-S-OK EXIT THEN
    S" weekdays" _DBAV-IS? IF
        2DROP DBREC-WEEKLY R@ DBREC.FREQ ! 62 R> DBREC.WEEKDAYS ! DBAO-S-OK EXIT
    THEN
    S" monthly" _DBAV-IS? IF 2DROP DBREC-MONTHLY R> DBREC.FREQ ! DBAO-S-OK EXIT THEN
    S" yearly" _DBAV-IS? IF 2DROP DBREC-YEARLY R> DBREC.FREQ ! DBAO-S-OK EXIT THEN
    2DROP R> DROP DBAV-S-REPEAT ;

\ The store's default zone.
: DBAV-DEFAULT-ZONE$  ( view -- address length )
    DUP _DBAV-STATE DBAS-READY <> IF DROP S" UTC0" EXIT THEN
    _DBAV-STORE DBAS-HEADER DBAS-H.ZONE DBAS-FIELD$ ;

: DBAV-DEFAULT-ZONE!  ( address length view -- status )
    DUP _DBAV.SERVICE @ 0= IF DROP 2DROP DBAO-S-STATE EXIT THEN
    _DBAV-OWNER DBAO-DEFAULT-ZONE! ;

\ The last step: the zone, or the default for an empty answer, which
\ places a start given as only a time at its next occurrence there.
\ Then the reminder is created under the create's key.
: DBAV-CREATE  ( zone-a zone-u view -- status )
    >R
    DUP 0= IF 2DROP R@ DBAV-DEFAULT-ZONE$ THEN
    DUP TZ-STRING-MAX > IF 2DROP R> DROP DBAO-S-ZONE EXIT THEN
    R@ _DBAV.DRAFT DBAO-D.ZONE TZ-STRING-MAX DBAS-FIELD!
    R@ _DBAV.DRAFT DBAO-D.ZONE DBAS-FIELD$ R@ _DBAV.ZONE TZ-PARSE IF
        R> DROP DBAO-S-ZONE EXIT
    THEN
    DBSVC-NOW DUP 0< IF DROP R> DROP DBAO-S-CLOCK EXIT THEN
    R@ _DBAV.DAY @ 0< IF
        1000 / R@ _DBAV.ZONE TZ-UTC>LOCAL IF DROP R> DROP DBAO-S-ZONE EXIT THEN
        DUP DUP 86400 MOD - R@ _DBAV.MINUTE @ 60 * +
        TUCK > IF 86400 + THEN
    ELSE
        DROP R@ _DBAV.DAY @ R@ _DBAV.MINUTE @ 60 * +
    THEN
    R@ _DBAV.DRAFT DBAO-D.RULE DBREC.START !
    R@ _DBAV.KEY R@ _DBAV.DRAFT DBSVC-NOW R@ _DBAV.RID R> _DBAV-OWNER DBAO-CREATE ;

\ What an action's status means to the user.
: DBAV-MESSAGE  ( status -- address length )
    CASE
        DBAO-S-OK OF S" Done" ENDOF
        DBAO-S-CLOCK OF S" Set the clock first" ENDOF
        DBAV-S-WHEN OF S" Use HH:MM or YYYY-MM-DD HH:MM, then a title" ENDOF
        DBAV-S-REPEAT OF
            S" Repeat: once, daily, weekdays, weekly, monthly or yearly" ENDOF
        DBAO-S-TITLE OF S" A title is one line of at most 120 bytes" ENDOF
        DBAO-S-ZONE OF S" That zone is not a POSIX TZ string" ENDOF
        DBAO-S-NEVER OF S" That time has passed" ENDOF
        DBAO-S-ENTROPY OF S" No randomness for a new automation" ENDOF
        DBAO-S-CONFLICT OF S" The automation changed; look again" ENDOF
        DBAV-S-CHANGED OF S" Automations changed; look again" ENDOF
        DBAO-S-DELETED OF S" That automation was deleted" ENDOF
        DBAO-S-BLOCKED OF S" Automations are unavailable" ENDOF
        DBAO-S-IO OF S" Could not save automations" ENDOF
        DBAV-S-NONE OF S" Nothing to do for that row" ENDOF
        S" The automation could not be changed" ROT
    ENDCASE ;
