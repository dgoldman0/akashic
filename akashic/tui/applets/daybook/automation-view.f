\ =====================================================================
\  automation-view.f - Daybook's view of its automations
\ =====================================================================
\  The view lists the automations in the service Desk lends: schedules,
\  each a reminder or an Agent run, and the items they made.  In sections:
\
\    NEEDS REVIEW  reminder firings and Agent runs awaiting review,
\                  newest first
\    IN PROGRESS   Agent runs handed to Desk and not yet over, newest
\                  first
\    ACTIVE        enabled schedules, soonest first
\    PAUSED        paused schedules, oldest first
\    COMPLETED     series with nothing left to fire, oldest first
\    ARCHIVED      archived schedules, when the view shows them
\
\  Each row has a title and a detail: when a schedule fires next, in its
\  own zone, and for an Agent run whether it is approved; how a firing or
\  a run went; or that a run waits or runs.  The detail grows to what it
\  says.  A row names its record by position.
\  Every action therefore first checks that the store has not changed
\  since the rows were built.  If it has, the action does nothing and asks
\  for a rebuild, so it never lands on a record the user did not see.
\  Actions name the revision or the last firing the row showed.  An
\  Agent run's row also runs it now, asks Desk's user to approve it, or
\  cancels its run in flight, all through the service.
\
\  A create takes steps, as prompts ask for them: when and the title
\  ("HH:MM title" for the next such time, or "YYYY-MM-DD HH:MM title"),
\  how it repeats, and its zone, where an empty answer means the default
\  zone.  An Agent run then names the model it must use, from the list
\  Desk's broker gives, with its effort, tier and verbosity where the
\  model offers them; how many minutes it may run; how many bytes of
\  reply it keeps; and its prompt, which is also exactly what it may
\  disclose.  A start given as only a time is placed when the create
\  completes.  DBAV-BEGIN draws a fresh create key for each create, so a
\  create submitted twice makes one schedule.  The view then asks Desk's
\  user to approve the Agent run it made.
\
\  DBAV-OPEN opens one schedule's details: its facts, each a label and a
\  text, then each item it made, newest first.  The opened schedule
\  follows the store; DBAV-REREAD brings its facts current, and the
\  opened-run actions refuse while they are old.
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
\    DBAV-SCHEDULE?   ( index view -- flag )
\    DBAV-AGENT?      ( index view -- flag )
\    DBAV-IN-FLIGHT?  ( index view -- flag )
\    DBAV-KEY         ( index view -- key )
\    DBAV-TITLE       ( index view -- address length )
\    DBAV-DETAIL      ( index view -- address length )
\    DBAV-NOTE        ( view -- address length )
\    DBAV-ARCHIVED@   ( view -- flag )
\    DBAV-ARCHIVED!   ( flag view -- )
\    DBAV-REVIEW DBAV-PAUSE DBAV-ARCHIVE DBAV-DELETE DBAV-RUN-NOW
\    DBAV-ASK DBAV-CANCEL  ( index view -- status )
\    DBAV-ASK-NOTE    ( view -- address length )
\    DBAV-SERVICE?    ( view -- flag )
\    DBAV-BEGIN       ( action view -- status )
\    DBAV-WHEN!       ( address length view -- status )
\    DBAV-REPEAT!     ( address length view -- status )
\    DBAV-ZONE!       ( address length view -- status )
\    DBAV-MODELS-FETCH  ( view -- status )
\    DBAV-CHOICES     ( kind view -- n )
\    DBAV-CHOICE$     ( index kind view -- address length )
\    DBAV-CHOOSE      ( index kind view -- status )
\    DBAV-NEXT-KIND   ( kind view -- kind|0 )
\    DBAV-MINUTES!    ( address length view -- status )
\    DBAV-REPLY!      ( address length view -- status )
\    DBAV-PROMPT!     ( address length view -- status )
\    DBAV-CREATE      ( view -- status )
\    DBAV-ASK-CREATED ( view -- status )
\    DBAV-OPEN        ( index view -- status )
\    DBAV-SHUT        ( view -- )
\    DBAV-OPENED?     ( view -- flag )
\    DBAV-OPENED-STALE?  ( view -- flag )
\    DBAV-REREAD      ( view -- status )
\    DBAV-FACTS@      ( view -- n )
\    DBAV-FACT-LABEL  ( row view -- address length )
\    DBAV-FACT-TEXT   ( row view -- address length )
\    DBAV-OPENED-RUN-NOW DBAV-OPENED-ASK DBAV-OPENED-CANCEL
\                     ( view -- status )
\    DBAV-DEFAULT-ZONE$  ( view -- address length )
\    DBAV-DEFAULT-ZONE!  ( address length view -- status )
\    DBAV-MESSAGE     ( status -- address length )
\ =====================================================================

PROVIDED akashic-dbk-auto-view

REQUIRE automation-service.f
REQUIRE ../../../interop/scheduled-dispatch.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../math/entropy.f

\ Row kinds.
0 CONSTANT DBAV-HEADING          \ position: the section
1 CONSTANT DBAV-SCHEDULE         \ position: the schedule's index
2 CONSTANT DBAV-ITEM             \ position: the occurrence's index

\ Sections.
1 CONSTANT DBAV-REVIEW-SECTION
2 CONSTANT DBAV-PROGRESS-SECTION
3 CONSTANT DBAV-ACTIVE-SECTION
4 CONSTANT DBAV-PAUSED-SECTION
5 CONSTANT DBAV-COMPLETED-SECTION
6 CONSTANT DBAV-ARCHIVED-SECTION

\ View statuses beyond the owner's.
40 CONSTANT DBAV-S-CHANGED       \ the store changed since the rows were built
41 CONSTANT DBAV-S-NONE          \ the row has no such action
42 CONSTANT DBAV-S-NOMEM
43 CONSTANT DBAV-S-WHEN          \ not "HH:MM title" or "YYYY-MM-DD HH:MM title"
44 CONSTANT DBAV-S-REPEAT        \ not a repeat the view knows
45 CONSTANT DBAV-S-MODELS        \ the Agent offers no models now
46 CONSTANT DBAV-S-NUMBER        \ not a whole number above zero
47 CONSTANT DBAV-S-PROMPT        \ an empty prompt, or one that is not text

\ The kinds of choice an Agent run's model makes.
1 CONSTANT DBAV-MODEL-KIND
2 CONSTANT DBAV-EFFORT-KIND
3 CONSTANT DBAV-TIER-KIND
4 CONSTANT DBAV-VERBOSITY-KIND

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
88 CONSTANT _DBAV-TEXT          \ the detail's buffer, or 0
96 CONSTANT _DBAV-CAP           \ its bytes
104 CONSTANT _DBAV-ZONE
\ A create in progress: the day (local seconds, or -1 for the next such
\ time), the minute, the create key, the new RID, and the draft.
_DBAV-ZONE TZ-SIZE + 7 + -8 AND CONSTANT _DBAV-DAY
_DBAV-DAY 8 + CONSTANT _DBAV-MINUTE
_DBAV-MINUTE 8 + CONSTANT _DBAV-KEY
_DBAV-KEY RID-SIZE + CONSTANT _DBAV-RID
_DBAV-RID RID-SIZE + CONSTANT _DBAV-DRAFT
\ An Agent run's create: the model list Desk's broker gave and what was
\ chosen from it, the limits, the operands its prompt completed, and the
\ operands' draft.  The effort, tier and verbosity mean something only
\ while a model is chosen, and choosing one clears them.
_DBAV-DRAFT DBAO-DRAFT-SIZE + 7 + -8 AND CONSTANT _DBAV-MODELS  \ the list, or 0
_DBAV-MODELS 8 + CONSTANT _DBAV-MODEL        \ the chosen model, or 0
_DBAV-MODEL 8 + CONSTANT _DBAV-EFFORT        \ its chosen effort, or 0
_DBAV-EFFORT 8 + CONSTANT _DBAV-TIER         \ its chosen tier, or 0 for none
_DBAV-TIER 8 + CONSTANT _DBAV-VERBOSITY
_DBAV-VERBOSITY 8 + CONSTANT _DBAV-TIME      \ the milliseconds it may run
_DBAV-TIME 8 + CONSTANT _DBAV-OUTPUT         \ the bytes of reply it keeps
_DBAV-OUTPUT 8 + CONSTANT _DBAV-OPS          \ the operands, or 0
_DBAV-OPS 8 + CONSTANT _DBAV-SACT
_DBAV-SACT SACT-DRAFT-SIZE + CONSTANT _DBAV-OPENED   \ RID-SIZE bytes
\ The schedule opened in detail: its RID, zero when none; the store
\ generation its facts were read at, plus one; and its items' ids, newest
\ first, in a buffer that grows to them.
_DBAV-OPENED RID-SIZE + CONSTANT _DBAV-OPENED-BUILT
_DBAV-OPENED-BUILT 8 + CONSTANT _DBAV-HISTORY        \ the ids, or 0
_DBAV-HISTORY 8 + CONSTANT _DBAV-HISTORY-N
_DBAV-HISTORY-N 8 + CONSTANT _DBAV-HISTORY-CAP
_DBAV-HISTORY-CAP 8 + CONSTANT DBAV-SIZE

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
: _DBAV.CAP      ( view -- a ) _DBAV-CAP + ;
: _DBAV.ZONE     ( view -- zone ) _DBAV-ZONE + ;
: _DBAV.DAY      ( view -- a ) _DBAV-DAY + ;
: _DBAV.MINUTE   ( view -- a ) _DBAV-MINUTE + ;
: _DBAV.KEY      ( view -- key ) _DBAV-KEY + ;
: _DBAV.RID      ( view -- rid ) _DBAV-RID + ;
: _DBAV.DRAFT    ( view -- draft ) _DBAV-DRAFT + ;
: _DBAV.MODELS   ( view -- a ) _DBAV-MODELS + ;
: _DBAV.MODEL    ( view -- a ) _DBAV-MODEL + ;
: _DBAV.EFFORT   ( view -- a ) _DBAV-EFFORT + ;
: _DBAV.TIER     ( view -- a ) _DBAV-TIER + ;
: _DBAV.VERBOSITY  ( view -- a ) _DBAV-VERBOSITY + ;
: _DBAV.TIME     ( view -- a ) _DBAV-TIME + ;
: _DBAV.OUTPUT   ( view -- a ) _DBAV-OUTPUT + ;
: _DBAV.OPS      ( view -- a ) _DBAV-OPS + ;
: _DBAV.SACT     ( view -- draft ) _DBAV-SACT + ;
: _DBAV.OPENED   ( view -- rid ) _DBAV-OPENED + ;
: _DBAV.OPENED-BUILT  ( view -- a ) _DBAV-OPENED-BUILT + ;
: _DBAV.HISTORY  ( view -- a ) _DBAV-HISTORY + ;
: _DBAV.HISTORY-N    ( view -- a ) _DBAV-HISTORY-N + ;
: _DBAV.HISTORY-CAP  ( view -- a ) _DBAV-HISTORY-CAP + ;

\ Starts a view over SERVICE, which may be 0.
: DBAV-INIT  ( service view -- )
    DUP DBAV-SIZE 0 FILL
    _DBAV-MAGIC OVER _DBAV-MAGIC-OFF + !
    _DBAV.SERVICE ! ;

\ Gives back an Agent run's model list and operands, and forgets what
\ was chosen from the list.
: _DBAV-AGENT-FREE  ( view -- )
    DUP _DBAV.MODELS @ ?DUP IF FREE THEN
    DUP _DBAV.OPS @ ?DUP IF FREE THEN
    0 OVER _DBAV.MODELS ! 0 OVER _DBAV.MODEL ! 0 SWAP _DBAV.OPS ! ;

: DBAV-FREE  ( view -- )
    DUP _DBAV-AGENT-FREE
    DUP _DBAV.HISTORY @ ?DUP IF FREE THEN
    0 OVER _DBAV.HISTORY ! 0 OVER _DBAV.HISTORY-N ! 0 OVER _DBAV.HISTORY-CAP !
    DUP _DBAV.OPENED RID-SIZE 0 FILL
    DUP _DBAV.ROWS @ ?DUP IF FREE THEN
    DUP _DBAV.TEXT @ ?DUP IF FREE THEN
    0 OVER _DBAV.ROWS ! 0 OVER _DBAV.COUNT ! 0 OVER _DBAV.ROOM !
    0 OVER _DBAV.TEXT ! 0 OVER _DBAV.CAP ! 0 SWAP _DBAV.LEN ! ;

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
            DBAV-SCHEDULE OVER 3 PICK _DBAV-ADD ?DUP IF
                NIP NIP NIP R> DROP EXIT
            THEN
        THEN
        1+
    REPEAT
    DROP
    DUP DBAV-COUNT@ R@ = IF -1 OVER _DBAV.COUNT +! THEN
    R> ROT ROT _DBAV-SORT DBAO-S-OK ;

\ Adds a section of items: its heading, then the items in STATE, newest
\ first.  A section with none shows no heading.  The store keeps a
\ deleted schedule's short records neither due nor in flight, so no
\ section shows them.
: _DBAV-ITEMS  ( state section view -- status )
    DUP DBAV-COUNT@ 1+ >R                      ( state section view ; R: first )
    DBAV-HEADING ROT 2 PICK _DBAV-ADD ?DUP IF NIP NIP R> DROP EXIT THEN
    DUP _DBAV-STORE DBAS-OCCURRENCE-COUNT@     ( state view i )
    BEGIN DUP WHILE
        1-
        DUP 2 PICK _DBAV-STORE DBAS-OCCURRENCE DBAS-O.STATE @ 3 PICK = IF
            DBAV-ITEM OVER 3 PICK _DBAV-ADD ?DUP IF NIP NIP NIP R> DROP EXIT THEN
        THEN
    REPEAT
    DROP NIP
    DUP DBAV-COUNT@ R> = IF -1 SWAP _DBAV.COUNT +! ELSE DROP THEN
    DBAO-S-OK ;

: _DBAV-BUILD  ( view -- status )
    DBAS-DUE DBAV-REVIEW-SECTION 2 PICK _DBAV-ITEMS ?DUP IF NIP EXIT THEN
    DBAS-IN-FLIGHT DBAV-PROGRESS-SECTION 2 PICK _DBAV-ITEMS ?DUP IF NIP EXIT THEN
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

\ A row's key: headings by section, schedules by serial, items by id.
: DBAV-KEY  ( index view -- key )
    TUCK DBAV-ROW                              ( view kind position )
    OVER DBAV-HEADING = IF NIP NIP EXIT THEN
    SWAP DBAV-ITEM = IF
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
        DBAV-PROGRESS-SECTION OF S" IN PROGRESS" ENDOF
        DBAV-ACTIVE-SECTION OF S" ACTIVE" ENDOF
        DBAV-PAUSED-SECTION OF S" PAUSED" ENDOF
        DBAV-COMPLETED-SECTION OF S" COMPLETED" ENDOF
        S" ARCHIVED" ROT
    ENDCASE ;

\ The schedule an item belongs to.
: _DBAV-ITEM-SCHEDULE  ( position view -- schedule|0 )
    TUCK _DBAV-STORE DBAS-OCCURRENCE DBAS-O.RID SWAP _DBAV-OWNER DBAO-FIND ;

\ The title of row INDEX: a section's name, or its schedule's title.
: DBAV-TITLE  ( index view -- address length )
    TUCK DBAV-ROW                              ( view kind position )
    OVER DBAV-HEADING = IF NIP NIP _DBAV-HEADING$ EXIT THEN
    SWAP DBAV-ITEM = IF
        SWAP _DBAV-ITEM-SCHEDULE
    ELSE
        SWAP _DBAV-STORE DBAS-SCHEDULE
    THEN
    ?DUP 0= IF 0 0 EXIT THEN
    DBAS-S.TITLE DBAS-FIELD$ ;

\ Room for U more bytes of the detail, which grows to hold them; whether
\ there was memory for it.
: _DBAV-ROOM-TEXT  ( u view -- flag )
    >R R@ _DBAV.LEN @ + DUP R@ _DBAV.CAP @ > 0= IF DROP R> DROP -1 EXIT THEN
    R@ _DBAV.CAP @ 2 * MAX                     ( cap' )
    DUP ALLOCATE IF 2DROP R> DROP 0 EXIT THEN  ( cap' new )
    R@ _DBAV.TEXT @ ?DUP IF
        OVER R@ _DBAV.LEN @ MOVE R@ _DBAV.TEXT @ FREE
    THEN
    R@ _DBAV.TEXT ! R> _DBAV.CAP ! -1 ;

\ The end of the detail so far.
: _DBAV-END  ( view -- address ) DUP _DBAV.TEXT @ SWAP _DBAV.LEN @ + ;

\ Appends text to the detail; without memory for it, the detail stops.
: _DBAV-ADD$  ( address length view -- )
    >R DUP R@ _DBAV-ROOM-TEXT 0= IF 2DROP R> DROP EXIT THEN
    TUCK R@ _DBAV-END SWAP MOVE
    R> _DBAV.LEN +! ;

: _DBAV-CHAR  ( char view -- )
    1 OVER _DBAV-ROOM-TEXT 0= IF 2DROP EXIT THEN
    TUCK _DBAV-END C!
    1 SWAP _DBAV.LEN +! ;

: _DBAV-2D  ( n view -- )
    >R 100 MOD DUP 10 / [CHAR] 0 + R@ _DBAV-CHAR
    10 MOD [CHAR] 0 + R> _DBAV-CHAR ;

\ Appends an instant as "YYYY-MM-DD HH:MM" in the reminder's zone.
: _DBAV-WHEN  ( utc schedule view -- )
    >R
    DBAS-S.ZONE DBAS-FIELD$ R@ _DBAV.ZONE TZ-PARSE IF DROP R> DROP EXIT THEN
    R@ _DBAV.ZONE TZ-UTC>LOCAL IF DROP R> DROP EXIT THEN
    10 R@ _DBAV-ROOM-TEXT 0= IF DROP R> DROP EXIT THEN
    DUP R@ _DBAV-END 10 DT-DATE-S
    IF 2DROP R> DROP EXIT THEN
    R@ _DBAV.LEN +!
    BL R@ _DBAV-CHAR
    86400 MOD 60 / DUP 60 / R@ _DBAV-2D
    [CHAR] : R@ _DBAV-CHAR
    60 MOD R> _DBAV-2D ;

\ Whether SCHEDULE runs the Agent.
: _DBAV-AGENT?  ( schedule -- flag ) DBAS-S.ACTION @ DBAS-ACTION-AGENT = ;

\ Whether the Agent run SCHEDULE has been approved.
: _DBAV-APPROVED?  ( schedule view -- flag )
    SWAP DBAS-S.RID SWAP _DBAV-OWNER DBAO-ACTION
    ?DUP IF DBAS-A.AUTHORIZED @ 0<> ELSE 0 THEN ;

\ When SCHEDULE fires next, or that it is paused, done or archived.
: _DBAV-NEXT$  ( view schedule -- )
    DUP DBAS-S.ARCHIVED @ IF DROP S" archived" ROT _DBAV-ADD$ EXIT THEN
    DUP DBAS-S.STATE @ CASE
        DBAS-ENABLED OF DUP DBAS-S.NEXT-UTC @ OVER 3 PICK _DBAV-WHEN ENDOF
        DBAS-PAUSED OF S" paused" 3 PICK _DBAV-ADD$ ENDOF
        DBAS-COMPLETED OF S" done" 3 PICK _DBAV-ADD$ ENDOF
    ENDCASE
    2DROP ;

\ A schedule's detail: an Agent run says so, and whether it is approved;
\ then when it fires next, or that it is paused, done or archived.
: _DBAV-SCHEDULE$  ( position view -- )
    TUCK _DBAV-STORE DBAS-SCHEDULE             ( view schedule )
    DUP _DBAV-AGENT? IF
        S" Agent run, " 3 PICK _DBAV-ADD$
        DUP 2 PICK _DBAV-APPROVED? 0= IF S" not approved, " 3 PICK _DBAV-ADD$ THEN
    THEN
    DUP DBAS-S.STATE @ DBAS-ENABLED = OVER DBAS-S.ARCHIVED @ 0= AND IF
        S" next " 3 PICK _DBAV-ADD$
    THEN
    _DBAV-NEXT$ ;

\ "missed ", or for more than one "missed N, last ".
: _DBAV-MISSED$  ( item view -- )
    >R S" missed" R@ _DBAV-ADD$
    DBAS-O.COUNT @ DUP 1 > IF
        BL R@ _DBAV-CHAR NUM>STR R@ _DBAV-ADD$ S" , last" R@ _DBAV-ADD$
    ELSE
        DROP
    THEN
    BL R> _DBAV-CHAR ;

\ How an Agent run stands: waiting, running, or how it ended, and why.
: _DBAV-RUN-STATE$  ( item view -- )
    >R DUP DBAS-O.STATE @ DBAS-IN-FLIGHT = IF
        DBAS-O.PHASE @ DBAS-RUNNING = IF S" running" ELSE S" waiting" THEN
        R> _DBAV-ADD$ EXIT
    THEN
    DUP DBAS-O.OUTCOME @ SACT-OUTCOME$ R@ _DBAV-ADD$
    DBAS-O.REASON @ SACT-REASON$ DUP IF
        S" : " R@ _DBAV-ADD$ R> _DBAV-ADD$
    ELSE
        2DROP R> DROP
    THEN ;

: _DBAV-RUN$  ( item view -- ) TUCK _DBAV-RUN-STATE$ S" , " ROT _DBAV-ADD$ ;

\ An item's detail: how a reminder fired or how an Agent run stands, and
\ when it was due.
: _DBAV-ITEM$  ( position view -- )
    TUCK _DBAV-STORE DBAS-OCCURRENCE           ( view item )
    DUP DBAS-O.KIND @ DBAS-MISSED = IF
        DUP 2 PICK _DBAV-MISSED$
    ELSE
        DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT = IF
            DUP 2 PICK _DBAV-RUN$
        ELSE
            S" fired " 3 PICK _DBAV-ADD$
        THEN
    THEN
    DUP DBAS-O.LAST-UTC @                      ( view item utc )
    OVER DBAS-O.RID 3 PICK _DBAV-OWNER DBAO-FIND
    ?DUP IF 3 PICK _DBAV-WHEN ELSE DROP THEN
    2DROP ;

\ The detail of row INDEX: when a schedule fires next, or how a firing
\ or a run went.  The text stays put until the next call.
: DBAV-DETAIL  ( index view -- address length )
    0 OVER _DBAV.LEN !
    TUCK DBAV-ROW                              ( view kind position )
    OVER DBAV-HEADING = IF 2DROP DROP 0 0 EXIT THEN
    SWAP DBAV-ITEM = IF OVER _DBAV-ITEM$ ELSE OVER _DBAV-SCHEDULE$ THEN
    DUP _DBAV.TEXT @ SWAP _DBAV.LEN @ ;

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

\ Whether row INDEX shows a schedule.
: DBAV-SCHEDULE?  ( index view -- flag )
    2DUP _DBAV-INDEX? 0= IF 2DROP 0 EXIT THEN
    DBAV-ROW DROP DBAV-SCHEDULE = ;

\ Whether row INDEX shows a schedule that runs the Agent.
: DBAV-AGENT?  ( index view -- flag )
    2DUP DBAV-SCHEDULE? 0= IF 2DROP 0 EXIT THEN
    TUCK DBAV-ROW NIP SWAP _DBAV-STORE DBAS-SCHEDULE _DBAV-AGENT? ;

\ The schedule row INDEX shows, while the rows are current.
: _DBAV-SCHEDULE  ( index view -- schedule status )
    DUP DBAV-STALE? IF 2DROP 0 DBAV-S-CHANGED EXIT THEN
    2DUP _DBAV-INDEX? 0= IF 2DROP 0 DBAV-S-NONE EXIT THEN
    TUCK DBAV-ROW SWAP DBAV-SCHEDULE <> IF 2DROP 0 DBAV-S-NONE EXIT THEN
    SWAP _DBAV-STORE DBAS-SCHEDULE DBAO-S-OK ;

\ The item row INDEX shows, while the rows are current.
: _DBAV-ITEM  ( index view -- item status )
    DUP DBAV-STALE? IF 2DROP 0 DBAV-S-CHANGED EXIT THEN
    2DUP _DBAV-INDEX? 0= IF 2DROP 0 DBAV-S-NONE EXIT THEN
    TUCK DBAV-ROW SWAP DBAV-ITEM <> IF 2DROP 0 DBAV-S-NONE EXIT THEN
    SWAP _DBAV-STORE DBAS-OCCURRENCE DBAO-S-OK ;

\ Whether row INDEX shows an Agent run in flight.
: DBAV-IN-FLIGHT?  ( index view -- flag )
    2DUP _DBAV-INDEX? 0= IF 2DROP 0 EXIT THEN
    TUCK DBAV-ROW SWAP DBAV-ITEM <> IF 2DROP 0 EXIT THEN
    SWAP _DBAV-STORE DBAS-OCCURRENCE DBAS-O.STATE @ DBAS-IN-FLIGHT = ;

\ Marks the item row INDEX shows reviewed.
: DBAV-REVIEW  ( index view -- status )
    DUP DBAV-STALE? IF 2DROP DBAV-S-CHANGED EXIT THEN
    2DUP _DBAV-INDEX? 0= IF 2DROP DBAV-S-NONE EXIT THEN
    TUCK DBAV-ROW SWAP DBAV-ITEM <> IF 2DROP DBAV-S-NONE EXIT THEN
    OVER _DBAV-STORE DBAS-OCCURRENCE           ( view item )
    DUP DBAS-O.ID @ SWAP DBAS-O.LAST @ DBSVC-NOW 3 PICK _DBAV-OWNER
        DBAO-REVIEW
    NIP ;

\ Pauses an enabled schedule or resumes a paused one.
: DBAV-PAUSE  ( index view -- status )
    TUCK _DBAV-SCHEDULE ?DUP IF NIP NIP EXIT THEN   ( view schedule )
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

\ Archives a schedule, or brings an archived one back.
: DBAV-ARCHIVE  ( index view -- status )
    TUCK _DBAV-SCHEDULE ?DUP IF NIP NIP EXIT THEN
    DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBAV-OWNER
    3 PICK DBAS-S.ARCHIVED @ IF DBAO-UNARCHIVE ELSE DBAO-ARCHIVE THEN
    NIP NIP ;

\ Deletes a schedule.  An Agent run's items become short records.
: DBAV-DELETE  ( index view -- status )
    TUCK _DBAV-SCHEDULE ?DUP IF NIP NIP EXIT THEN
    DUP DUP DBAS-S.REVISION @ DBSVC-NOW 4 PICK _DBAV-OWNER DBAO-DELETE
    NIP NIP ;

\ The Agent run row INDEX shows, while the rows are current.
: _DBAV-AGENT  ( index view -- schedule status )
    _DBAV-SCHEDULE ?DUP IF EXIT THEN
    DUP _DBAV-AGENT? 0= IF DROP 0 DBAV-S-NONE EXIT THEN
    DBAO-S-OK ;

\ Runs an Agent run now, by hand, through Desk, at the revision shown.
: _DBAV-RUN-NOW-OF  ( view schedule -- status )
    DUP DBAS-S.RID SWAP DBAS-S.REVISION @ ROT _DBAV.SERVICE @ DBSVC-RUN-NOW NIP ;

\ Asks Desk's user to approve an Agent run at the revision shown.
: _DBAV-ASK-OF  ( view schedule -- status )
    DUP DBAS-S.RID SWAP DBAS-S.REVISION @ ROT _DBAV.SERVICE @ DBSVC-ASK ;

\ Runs the Agent run row INDEX shows now, by hand, through Desk.
: DBAV-RUN-NOW  ( index view -- status )
    TUCK _DBAV-AGENT ?DUP IF NIP NIP EXIT THEN _DBAV-RUN-NOW-OF ;

\ Asks Desk's user to approve the Agent run row INDEX shows, at the
\ revision it shows.
: DBAV-ASK  ( index view -- status )
    TUCK _DBAV-AGENT ?DUP IF NIP NIP EXIT THEN _DBAV-ASK-OF ;

\ Cancels the Agent run in flight row INDEX shows.
: DBAV-CANCEL  ( index view -- status )
    TUCK _DBAV-ITEM ?DUP IF NIP NIP EXIT THEN       ( view item )
    DUP DBAS-O.STATE @ DBAS-IN-FLIGHT <> IF 2DROP DBAV-S-NONE EXIT THEN
    DBAS-O.ID @ SWAP _DBAV.SERVICE @ DBSVC-CANCEL ;

\ Where the approval asked for last stands, for the status line, or 0 0
\ when none was asked for.
: DBAV-ASK-NOTE  ( view -- address length )
    _DBAV.SERVICE @ ?DUP 0= IF 0 0 EXIT THEN
    DBSVC-ASK-STATE@ CASE
        DBSVC-ASK-PENDING OF S" Waiting for approval in Desk" ENDOF
        DBSVC-ASK-ALLOWED OF S" Approved" ENDOF
        DBSVC-ASK-REFUSED OF S" Not approved: refused in Desk" ENDOF
        DBSVC-ASK-GONE OF S" Not approved: the request was withdrawn" ENDOF
        DBSVC-ASK-FAILED OF S" Approved, but it changed meanwhile; ask again" ENDOF
        >R 0 0 R>
    ENDCASE ;

\ =====================================================================
\  Details
\ =====================================================================
\  A schedule opened from its row shows its facts, each a label and a
\  text: its title, when it runs and next runs, and for an Agent run
\  whether it is approved, the model it names, its provider, its limits
\  and its prompt, exactly as stored; then each of its items, newest
\  first.  The facts follow the store: once it changes, DBAV-REREAD reads
\  them again, and says when the schedule is gone.  An action on the
\  opened schedule refuses while its facts are older than the store.

\ The facts a schedule has before its items.
3 CONSTANT _DBAV-REMINDER-FACTS     \ title, when, next
8 CONSTANT _DBAV-AGENT-FACTS        \ and approval, model, provider, limits, prompt

\ The ids read at a time.
16 CONSTANT _DBAV-PAGE

: _DBAV-OWN-FACTS  ( schedule -- n )
    _DBAV-AGENT? IF _DBAV-AGENT-FACTS ELSE _DBAV-REMINDER-FACTS THEN ;

\ Whether a schedule is opened.
: DBAV-OPENED?  ( view -- flag ) _DBAV.OPENED RID-ZERO? 0= ;

\ The schedule opened, while it lives; 0 otherwise.
: _DBAV-OPENED-SCHEDULE  ( view -- schedule|0 )
    DUP DBAV-OPENED? 0= IF DROP 0 EXIT THEN
    DUP _DBAV.OPENED SWAP _DBAV-OWNER DBAO-FIND
    DUP IF DUP DBAS-S.STATE @ DBAS-TOMBSTONE = IF DROP 0 THEN THEN ;

\ Whether the facts are older than the store.
: DBAV-OPENED-STALE?  ( view -- flag )
    DUP _DBAV-GENERATION SWAP _DBAV.OPENED-BUILT @ <> ;

\ Room in the history for U ids; whether there was memory for it.
: _DBAV-HISTORY-ROOM  ( u view -- flag )
    >R DUP R@ _DBAV.HISTORY-CAP @ > 0= IF DROP R> DROP -1 EXIT THEN
    R@ _DBAV.HISTORY-CAP @ 2 * MAX
    DUP CELLS ALLOCATE IF 2DROP R> DROP 0 EXIT THEN      ( capacity buffer )
    R@ _DBAV.HISTORY @ ?DUP IF
        OVER R@ _DBAV.HISTORY-N @ CELLS MOVE R@ _DBAV.HISTORY @ FREE
    THEN
    R@ _DBAV.HISTORY ! R> _DBAV.HISTORY-CAP ! -1 ;

\ Reads the opened schedule's items again, newest first, a page of ids
\ at a time; DELETED when the schedule is gone.
: DBAV-REREAD  ( view -- status )
    >R R@ _DBAV-OPENED-SCHEDULE 0= IF R> DROP DBAO-S-DELETED EXIT THEN
    0 R@ _DBAV.HISTORY-N !
    BEGIN
        R@ _DBAV.HISTORY-N @ _DBAV-PAGE + R@ _DBAV-HISTORY-ROOM 0= IF
            R> DROP DBAV-S-NOMEM EXIT
        THEN
        R@ _DBAV.OPENED R@ _DBAV.HISTORY-N @
        R@ _DBAV.HISTORY @ OVER CELLS + _DBAV-PAGE R@ _DBAV-OWNER DBAO-HISTORY
        ?DUP IF NIP NIP R> DROP EXIT THEN          ( n cursor )
        R@ _DBAV.HISTORY-N ! _DBAV-PAGE <
    UNTIL
    R@ _DBAV-GENERATION R> _DBAV.OPENED-BUILT ! DBAO-S-OK ;

\ Opens the schedule row INDEX shows; a schedule whose items cannot be
\ read stays closed.
: DBAV-OPEN  ( index view -- status )
    TUCK _DBAV-SCHEDULE ?DUP IF NIP NIP EXIT THEN    ( view schedule )
    DBAS-S.RID OVER _DBAV.OPENED RID-SIZE MOVE
    DUP DBAV-REREAD ?DUP IF SWAP _DBAV.OPENED RID-SIZE 0 FILL EXIT THEN
    DROP DBAO-S-OK ;

\ Closes the schedule opened.
: DBAV-SHUT  ( view -- ) _DBAV.OPENED RID-SIZE 0 FILL ;

\ How many facts the opened schedule has, its own and its items'.
: DBAV-FACTS@  ( view -- n )
    DUP _DBAV-OPENED-SCHEDULE ?DUP 0= IF DROP 0 EXIT THEN
    _DBAV-OWN-FACTS SWAP _DBAV.HISTORY-N @ + ;

\ The item fact ROW shows, while it lives, or 0.
: _DBAV-FACT-ITEM  ( row schedule view -- item|0 )
    >R _DBAV-OWN-FACTS -
    DUP 0< OVER R@ _DBAV.HISTORY-N @ < 0= OR IF DROP R> DROP 0 EXIT THEN
    CELLS R@ _DBAV.HISTORY @ + @ R@ _DBAV-STORE DBAS-FIND-OCCURRENCE
    0= IF DROP R> DROP 0 EXIT THEN
    R> _DBAV-STORE DBAS-OCCURRENCE ;

\ The label of fact ROW: what the fact is, or what kind of item it is.
: DBAV-FACT-LABEL  ( row view -- address length )
    DUP _DBAV-OPENED-SCHEDULE ?DUP 0= IF 2DROP 0 0 EXIT THEN    ( row view schedule )
    2 PICK OVER _DBAV-OWN-FACTS < IF
        2DROP CASE
            0 OF S" Schedule" ENDOF
            1 OF S" When" ENDOF
            2 OF S" Next" ENDOF
            3 OF S" Approval" ENDOF
            4 OF S" Model" ENDOF
            5 OF S" Provider" ENDOF
            6 OF S" Limits" ENDOF
            >R S" Prompt" R>
        ENDCASE EXIT
    THEN
    SWAP _DBAV-FACT-ITEM ?DUP 0= IF 0 0 EXIT THEN
    DUP DBAS-O.KIND @ DBAS-MISSED = IF DROP S" Missed" EXIT THEN
    DUP DBAS-O.KIND @ DBAS-MANUAL = IF DROP S" Run now" EXIT THEN
    DBAS-O.ACTION @ DBAS-ACTION-AGENT = IF S" Run" ELSE S" Fired" THEN ;

: _DBAV-TEXT$  ( view -- address length ) DUP _DBAV.TEXT @ SWAP _DBAV.LEN @ ;

\ An Agent run's operands, as stored.
: _DBAV-OPERANDS  ( schedule view -- operands )
    SWAP DBAS-S.RID SWAP _DBAV-OWNER DBAO-ACTION DBAS-A.OPERANDS BSLOT$ DROP ;

\ What became of ITEM: when it was due, how many it covers when it
\ missed several, how an Agent run stands or ended, whether it awaits
\ review, and on a line of its own its run's summary.
: _DBAV-HISTORY$  ( item schedule view -- )
    >R OVER DBAS-O.LAST-UTC @ SWAP R@ _DBAV-WHEN    ( item )
    DUP DBAS-O.KIND @ DBAS-MISSED = OVER DBAS-O.COUNT @ 1 > AND IF
        S" , " R@ _DBAV-ADD$ DUP DBAS-O.COUNT @ NUM>STR R@ _DBAV-ADD$
        S"  times" R@ _DBAV-ADD$
    THEN
    DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT = IF
        S" , " R@ _DBAV-ADD$ DUP R@ _DBAV-RUN-STATE$
    THEN
    DUP DBAS-O.STATE @ DBAS-DUE = IF S" , needs review" R@ _DBAV-ADD$ THEN
    DBAS-O.SUMMARY BSLOT$ DUP IF
        10 R@ _DBAV-CHAR R> _DBAV-ADD$
    ELSE
        2DROP R> DROP
    THEN ;

\ The text of fact ROW, which stays put until the next call: what the
\ schedule names, exactly as stored, or what became of one of its items.
: DBAV-FACT-TEXT  ( row view -- address length )
    0 OVER _DBAV.LEN !
    DUP _DBAV-OPENED-SCHEDULE ?DUP 0= IF 2DROP 0 0 EXIT THEN    ( row view schedule )
    2 PICK OVER _DBAV-OWN-FACTS < 0= IF
        SWAP DUP >R _DBAV-FACT-ITEM ?DUP 0= IF R> DROP 0 0 EXIT THEN
        R@ _DBAV-OPENED-SCHEDULE R@ _DBAV-HISTORY$ R> _DBAV-TEXT$ EXIT
    THEN
    ROT CASE                                   ( view schedule )
        0 OF NIP DBAS-S.TITLE DBAS-FIELD$ ENDOF
        1 OF SWAP _DBAV.SERVICE @ DBSVC-WHEN$ ENDOF
        2 OF OVER SWAP _DBAV-NEXT$ _DBAV-TEXT$ ENDOF
        3 OF SWAP _DBAV-APPROVED? IF S" Approved" ELSE S" Not approved" THEN ENDOF
        4 OF
            OVER _DBAV-OPERANDS ['] _DBAV-ADD$ 2 PICK SACT-SAY-MODEL _DBAV-TEXT$
        ENDOF
        5 OF OVER _DBAV-OPERANDS SACT-PROVIDER$ ROT DROP ENDOF
        6 OF
            OVER _DBAV-OPERANDS DUP SACT-O.TIME @ OVER SACT-O.DISCLOSURE @
            ROT SACT-O.OUTPUT @ ['] _DBAV-ADD$ 4 PICK SACT-SAY-LIMITS _DBAV-TEXT$
        ENDOF
        >R OVER _DBAV-OPERANDS SACT-PROMPT$ ROT DROP R>
    ENDCASE ;

\ The opened schedule, while its facts are current.  They were read
\ while it lived, and any change since, deleting it too, would make them
\ old, so it still lives.
: _DBAV-OPENED-NOW  ( view -- schedule status )
    DUP DBAV-OPENED? 0= IF DROP 0 DBAV-S-NONE EXIT THEN
    DUP DBAV-OPENED-STALE? IF DROP 0 DBAV-S-CHANGED EXIT THEN
    _DBAV-OPENED-SCHEDULE DBAO-S-OK ;

\ The opened Agent run, while its facts are current.
: _DBAV-OPENED-AGENT  ( view -- schedule status )
    _DBAV-OPENED-NOW ?DUP IF EXIT THEN
    DUP _DBAV-AGENT? 0= IF DROP 0 DBAV-S-NONE EXIT THEN
    DBAO-S-OK ;

\ Runs the opened Agent run now, by hand, through Desk.
: DBAV-OPENED-RUN-NOW  ( view -- status )
    DUP _DBAV-OPENED-AGENT ?DUP IF NIP NIP EXIT THEN _DBAV-RUN-NOW-OF ;

\ Asks Desk's user to approve the opened Agent run.
: DBAV-OPENED-ASK  ( view -- status )
    DUP _DBAV-OPENED-AGENT ?DUP IF NIP NIP EXIT THEN _DBAV-ASK-OF ;

\ Cancels the opened Agent run's run in flight: its newest item, since
\ one schedule has at most one run in flight and runs no other meanwhile.
\ Its facts are current, so the item is in the store.
: DBAV-OPENED-CANCEL  ( view -- status )
    DUP _DBAV-OPENED-AGENT ?DUP IF NIP NIP EXIT THEN DROP
    DUP _DBAV.HISTORY-N @ 0= IF DROP DBAV-S-NONE EXIT THEN
    DUP _DBAV.HISTORY @ @ OVER _DBAV-STORE DBAS-FIND-OCCURRENCE DROP
    OVER _DBAV-STORE DBAS-OCCURRENCE
    DUP DBAS-O.STATE @ DBAS-IN-FLIGHT <> IF 2DROP DBAV-S-NONE EXIT THEN
    DBAS-O.ID @ SWAP _DBAV.SERVICE @ DBSVC-CANCEL ;

\ =====================================================================
\  Creating
\ =====================================================================

\ Whether there are reminders to work: Daybook runs inside Desk.
: DBAV-SERVICE?  ( view -- flag ) _DBAV.SERVICE @ 0<> ;

\ Starts a create of ACTION, a reminder or an Agent run: an empty draft
\ and a fresh create key.
: DBAV-BEGIN  ( action view -- status )
    DUP _DBAV.SERVICE @ 0= IF 2DROP DBAO-S-STATE EXIT THEN
    DUP _DBAV-AGENT-FREE
    DUP _DBAV.DRAFT DBAO-DRAFT-SIZE 0 FILL
    TUCK _DBAV.DRAFT DBAO-D.ACTION !
    0 OVER _DBAV.TIME ! 0 OVER _DBAV.OUTPUT !
    -1 OVER _DBAV.DAY ! 0 OVER _DBAV.MINUTE !
    DUP _DBAV.RID RID-SIZE 0 FILL
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

\ Whether an answer is WORD, whatever its case.
: _DBAV-IS?  ( address length word-a word-u -- address length flag )
    2OVER 2SWAP STR-STRI= ;

\ The second step: once (or nothing), daily, weekdays (Monday to
\ Friday), weekly, monthly or yearly, every one from the start.
: DBAV-REPEAT!  ( address length view -- status )
    _DBAV.DRAFT DBAO-D.RULE >R                 ( address length ; R: rule )
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

\ The third step: the zone, or the default for an empty answer.
: DBAV-ZONE!  ( address length view -- status )
    >R
    DUP 0= IF 2DROP R@ DBAV-DEFAULT-ZONE$ THEN
    DUP TZ-STRING-MAX > IF 2DROP R> DROP DBAO-S-ZONE EXIT THEN
    R@ _DBAV.DRAFT DBAO-D.ZONE TZ-STRING-MAX DBAS-FIELD!
    R@ _DBAV.DRAFT DBAO-D.ZONE DBAS-FIELD$ R> _DBAV.ZONE TZ-PARSE
    IF DBAO-S-ZONE ELSE DBAO-S-OK THEN ;

\ ---------------------------------------------------------------------
\  An Agent run's model, limits and prompt
\ ---------------------------------------------------------------------

\ Fetches the models an Agent run may name, as Desk's broker lists them:
\ asked first with no room, then with the room the list needs.  A list
\ that is not whole, or names no model, is none, as is a broker that
\ asks for no more room than it had.
: DBAV-MODELS-FETCH  ( view -- status )
    >R R@ _DBAV-AGENT-FREE
    R@ _DBAV.SERVICE @ 0= IF R> DROP DBAO-S-STATE EXIT THEN
    0                                          ( capacity )
    BEGIN
        R@ _DBAV.MODELS @ OVER R@ _DBAV.SERVICE @ DBSVC-MODELS
        DUP SDSP-S-SMALL =                     ( capacity bytes status small? )
    WHILE
        DROP TUCK < 0= IF DROP R> _DBAV-AGENT-FREE DBAV-S-MODELS EXIT THEN
        R@ _DBAV.MODELS @ ?DUP IF FREE THEN 0 R@ _DBAV.MODELS !
        DUP ALLOCATE IF 2DROP R> DROP DBAV-S-NOMEM EXIT THEN
        R@ _DBAV.MODELS !
    REPEAT
    IF 2DROP R> _DBAV-AGENT-FREE DBAV-S-MODELS EXIT THEN
    TUCK < IF DROP R> _DBAV-AGENT-FREE DBAV-S-MODELS EXIT THEN
    R@ _DBAV.MODELS @ SWAP SDSP-LIST-OK? 0= IF R> _DBAV-AGENT-FREE DBAV-S-MODELS EXIT THEN
    R@ _DBAV.MODELS @ SDSP-LIST-COUNT 0= IF R> _DBAV-AGENT-FREE DBAV-S-MODELS EXIT THEN
    R> DROP DBAO-S-OK ;

\ Model I of the list.
: _DBAV-NTH-MODEL  ( i view -- model )
    _DBAV.MODELS @ SDSP-LIST-FIRST SWAP 0 ?DO SDSP-MODEL-NEXT LOOP ;

\ The I'th of a model's efforts or tiers, from the first, CHOICE.
: _DBAV-NTH-CHOICE  ( i choice -- choice' ) SWAP 0 ?DO SDSP-CHOICE-NEXT LOOP ;

\ How many choices of KIND there are now: the models; the chosen model's
\ efforts; its tiers and none; or its verbosities, when it takes one.
: DBAV-CHOICES  ( kind view -- n )
    OVER DBAV-MODEL-KIND = IF
        NIP _DBAV.MODELS @ ?DUP IF SDSP-LIST-COUNT ELSE 0 THEN EXIT
    THEN
    _DBAV.MODEL @ ?DUP 0= IF DROP 0 EXIT THEN  ( kind model )
    SWAP CASE
        DBAV-EFFORT-KIND OF SDSP-MODEL-EFFORTS DROP ENDOF
        DBAV-TIER-KIND OF SDSP-MODEL-TIERS DROP DUP IF 1+ THEN ENDOF
        DBAV-VERBOSITY-KIND OF
            SDSP-MODEL-FLAGS SDSP-M-VERBOSITY AND IF SACT-VERBOSITY-MAX 1+ ELSE 0 THEN
        ENDOF
        NIP 0 SWAP
    ENDCASE ;

\ A label, or the id when it has none.
: _DBAV-NAMED  ( label-a label-u id-a id-u -- address length )
    2 PICK IF 2DROP ELSE 2SWAP 2DROP THEN ;

\ The verbosities in the Agent's order.
: _DBAV-VERBOSITY$  ( n -- address length )
    CASE
        0 OF S" Default" ENDOF
        1 OF S" Low" ENDOF
        2 OF S" Medium" ENDOF
        >R S" High" R>
    ENDCASE ;

\ The name of choice INDEX of KIND, below their count: a model's,
\ effort's or tier's label, or its id when it has none; the first tier
\ is none, the default; and a verbosity's name.
: DBAV-CHOICE$  ( index kind view -- address length )
    OVER DBAV-MODEL-KIND = IF
        NIP _DBAV-NTH-MODEL DUP SDSP-MODEL-LABEL$ ROT SDSP-MODEL-ID$ _DBAV-NAMED EXIT
    THEN
    OVER DBAV-VERBOSITY-KIND = IF 2DROP _DBAV-VERBOSITY$ EXIT THEN
    OVER DBAV-TIER-KIND = IF
        2 PICK 0= IF 2DROP DROP S" Default" EXIT THEN
        ROT 1- ROT ROT
    THEN                                       ( index kind view )
    _DBAV.MODEL @ SWAP DBAV-EFFORT-KIND = IF SDSP-MODEL-EFFORTS ELSE SDSP-MODEL-TIERS THEN
    NIP _DBAV-NTH-CHOICE
    DUP SDSP-CHOICE-LABEL$ ROT SDSP-CHOICE-ID$ _DBAV-NAMED ;

\ Chooses INDEX of KIND.  A model starts with no effort, tier or
\ verbosity chosen.
: DBAV-CHOOSE  ( index kind view -- status )
    >R 2DUP R@ DBAV-CHOICES 0 SWAP WITHIN 0= IF 2DROP R> DROP DBAV-S-NONE EXIT THEN
    CASE
        DBAV-MODEL-KIND OF
            R@ _DBAV-NTH-MODEL R@ _DBAV.MODEL !
            0 R@ _DBAV.EFFORT ! 0 R@ _DBAV.TIER ! 0 R@ _DBAV.VERBOSITY !
        ENDOF
        DBAV-EFFORT-KIND OF
            R@ _DBAV.MODEL @ SDSP-MODEL-EFFORTS NIP _DBAV-NTH-CHOICE R@ _DBAV.EFFORT !
        ENDOF
        DBAV-TIER-KIND OF
            ?DUP IF 1- R@ _DBAV.MODEL @ SDSP-MODEL-TIERS NIP _DBAV-NTH-CHOICE ELSE 0 THEN
            R@ _DBAV.TIER !
        ENDOF
        DBAV-VERBOSITY-KIND OF R@ _DBAV.VERBOSITY ! ENDOF
        NIP
    ENDCASE
    R> DROP DBAO-S-OK ;

\ The kind of choice after KIND that the chosen model offers, or 0 when
\ none is left: after the model come its effort, tier and verbosity,
\ each only when it offers some.
: DBAV-NEXT-KIND  ( kind view -- kind|0 )
    SWAP BEGIN
        1+ DUP DBAV-VERBOSITY-KIND > IF 2DROP 0 EXIT THEN
        DUP 2 PICK DBAV-CHOICES
    UNTIL
    NIP ;

\ A whole number above zero and no more than LIMIT, in decimal digits
\ that spaces may surround.  Nineteen digits hold every number a cell
\ does; those beyond it read as negative, and are refused, as are no
\ digits and anything else, which read as 0.
: _DBAV-NUMBER  ( address length limit -- n ok? )
    >R STR-TRIM
    DUP 19 > IF 2DROP R> DROP 0 0 EXIT THEN
    _DBAV-DIGITS AND
    DUP 1 R> 1+ WITHIN ;

\ The most minutes whose milliseconds a cell holds.
-1 1 RSHIFT 60000 / CONSTANT _DBAV-MINUTES-MAX

\ How long the run may take: whole minutes.
: DBAV-MINUTES!  ( address length view -- status )
    >R _DBAV-MINUTES-MAX _DBAV-NUMBER 0= IF DROP R> DROP DBAV-S-NUMBER EXIT THEN
    60000 * R> _DBAV.TIME ! DBAO-S-OK ;

\ How much of its reply the run keeps: bytes.
: DBAV-REPLY!  ( address length view -- status )
    >R -1 1 RSHIFT _DBAV-NUMBER 0= IF DROP R> DROP DBAV-S-NUMBER EXIT THEN
    R> _DBAV.OUTPUT ! DBAO-S-OK ;

\ The operands' draft from the limits and what was chosen.
: _DBAV-SACT!  ( view -- )
    DUP _DBAV.SACT >R R@ SACT-DRAFT-INIT
    DUP _DBAV.TIME @ R@ SACT-D.TIME !
    DUP _DBAV.OUTPUT @ R@ SACT-D.OUTPUT !
    DUP _DBAV.MODELS @ ?DUP IF SDSP-LIST-PROVIDER$ R@ SACT-D.PROVIDER SACT-D! THEN
    DUP _DBAV.MODEL @ ?DUP 0= IF DROP R> DROP EXIT THEN
    SDSP-MODEL-ID$ R@ SACT-D.MODEL SACT-D!
    DUP _DBAV.VERBOSITY @ R@ SACT-D.VERBOSITY !
    DUP _DBAV.EFFORT @ ?DUP IF SDSP-CHOICE-ID$ R@ SACT-D.EFFORT SACT-D! THEN
    _DBAV.TIER @ ?DUP IF SDSP-CHOICE-ID$ R@ SACT-D.TIER SACT-D! THEN
    R> DROP ;

\ The last step of an Agent run: its prompt, which completes its
\ operands.  What the run may disclose is exactly the prompt.
: DBAV-PROMPT!  ( address length view -- status )
    >R
    DUP 0= IF 2DROP R> DROP DBAV-S-PROMPT EXIT THEN
    R@ _DBAV-SACT!
    DUP R@ _DBAV.SACT SACT-D.DISCLOSURE !
    R@ _DBAV.SACT SACT-D.PROMPT SACT-D!
    R@ _DBAV.OPS @ ?DUP IF FREE THEN 0 R@ _DBAV.OPS !
    R@ _DBAV.SACT SACT-AGENT-SIZE
    DUP ALLOCATE IF 2DROP R> DROP DBAV-S-NOMEM EXIT THEN   ( u operands )
    R@ _DBAV.SACT OVER 3 PICK SACT-AGENT-ENCODE            ( u operands bytes status )
    ?DUP IF
        NIP SWAP FREE NIP R> DROP
        SACT-S-PROMPT = IF DBAV-S-PROMPT ELSE DBAO-S-INVALID THEN EXIT
    THEN
    ROT DROP OVER R@ _DBAV.OPS !
    R> _DBAV.DRAFT DBAO-D.OPERANDS SACT-D! DBAO-S-OK ;

\ Creates the schedule the steps drafted, under the create's key.  A
\ start given as only a time is the next such time in its zone.
: DBAV-CREATE  ( view -- status )
    >R
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

\ Asks Desk's user to approve the Agent run just created, at the
\ revision it has.
: DBAV-ASK-CREATED  ( view -- status )
    DUP _DBAV.RID OVER _DBAV-OWNER DBAO-FIND
    DUP 0= IF 2DROP DBAV-S-NONE EXIT THEN
    DUP _DBAV-AGENT? 0= IF 2DROP DBAV-S-NONE EXIT THEN
    DBAS-S.REVISION @ OVER _DBAV.RID SWAP ROT _DBAV.SERVICE @ DBSVC-ASK ;

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
        DBAO-S-BUSY OF S" A run of it is already in progress" ENDOF
        DBAO-S-REVIEW OF S" Review its last run first" ENDOF
        DBAO-S-APPROVAL OF S" It is not approved yet; Y asks Desk" ENDOF
        DBAO-S-NOT-FOUND OF S" That run is over" ENDOF
        DBSVC-S-UNAVAILABLE OF S" Desk's scheduler is unavailable" ENDOF
        DBSVC-S-PENDING OF S" An approval is already being asked for" ENDOF
        DBAV-S-NONE OF S" Nothing to do for that row" ENDOF
        DBAV-S-NOMEM OF S" Not enough memory" ENDOF
        DBAV-S-MODELS OF S" The Agent offers no models now" ENDOF
        DBAV-S-NUMBER OF S" Use a whole number above zero" ENDOF
        DBAV-S-PROMPT OF S" A prompt is text, and not empty" ENDOF
        S" The automation could not be changed" ROT
    ENDCASE ;
