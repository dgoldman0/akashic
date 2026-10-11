\ =====================================================================
\  automation-service.f - Daybook's schedules inside Desk
\ =====================================================================
\  Desk opens one service over its Practice filesystem when it starts,
\  ticks it, lends it to Daybook, and shows its notices.  The service owns
\  Daybook's schedule owner, the runner that says when schedules come
\  due, and the text of the latest notice.  That text stays put until the
\  next notice, so a toast may keep pointing at it.
\
\  A tick reads uptime once and, until the runner's next look, does
\  nothing else.  A look reads the wall clock and accepts what is due,
\  a page of schedules at a time: a reminder makes its review item, and
\  an Agent run is accepted or blocked by its permission's standing.
\  Until Desk gives the service a broker, an Agent run's standing is
\  unavailable, so it is blocked for review.
\
\  Public API:
\    DBSVC-SIZE        ( -- bytes )
\    DBSVC-OPEN        ( vfs service -- status )
\    DBSVC-CLOSE       ( service -- )
\    DBSVC-TICK        ( service -- notice? )
\    DBSVC-NOTICE      ( service -- address length )
\    DBSVC-OWNER       ( service -- owner )
\    DBSVC-CLOCK@      ( service -- clock )
\    DBSVC-STATUS@     ( service -- status )
\    DBSVC-NOW         ( -- now )
\ =====================================================================

PROVIDED akashic-dbk-auto-svc

REQUIRE automation-runner.f
REQUIRE ../../../utils/string.f

\ The longest notice: a prefix, a whole title, and how many more fired.
DBAS-TITLE-MAX 64 + CONSTANT DBSVC-NOTICE-MAX

\ Due schedules read per page.
8 CONSTANT _DBSVC-PAGE

0x4356534F54554144 CONSTANT _DBSVC-MAGIC  \ "DAUTOSVC"

 0 CONSTANT _DBSVC-MAGIC-OFF
 8 CONSTANT _DBSVC-SELF
16 CONSTANT _DBSVC-STATUS      \ how the latest look went
24 CONSTANT _DBSVC-LEN         \ the notice's length
32 CONSTANT _DBSVC-WALL        \ the wall clock at this look
40 CONSTANT _DBSVC-BASIS       \ and its evidence
48 CONSTANT _DBSVC-FIRED       \ items this look made or added to
56 CONSTANT _DBSVC-ITEM        \ the latest of them
64 CONSTANT _DBSVC-MIXED       \ whether any was not a reminder's
72 CONSTANT _DBSVC-TEXT
_DBSVC-TEXT DBSVC-NOTICE-MAX + 7 + -8 AND CONSTANT _DBSVC-ENTRIES
_DBSVC-ENTRIES _DBSVC-PAGE DBAO-DUE-SIZE * + CONSTANT _DBSVC-OWNER
_DBSVC-OWNER DBAO-SIZE + 7 + -8 AND CONSTANT _DBSVC-RUNNER
_DBSVC-RUNNER DBRUN-SIZE + CONSTANT DBSVC-SIZE

: _DBSVC.MAGIC   ( service -- a ) _DBSVC-MAGIC-OFF + ;
: _DBSVC.SELF    ( service -- a ) _DBSVC-SELF + ;
: _DBSVC.STATUS  ( service -- a ) _DBSVC-STATUS + ;
: _DBSVC.LEN     ( service -- a ) _DBSVC-LEN + ;
: _DBSVC.WALL    ( service -- a ) _DBSVC-WALL + ;
: _DBSVC.BASIS   ( service -- a ) _DBSVC-BASIS + ;
: _DBSVC.FIRED   ( service -- a ) _DBSVC-FIRED + ;
: _DBSVC.ITEM    ( service -- a ) _DBSVC-ITEM + ;
: _DBSVC.MIXED   ( service -- a ) _DBSVC-MIXED + ;
: _DBSVC.TEXT    ( service -- a ) _DBSVC-TEXT + ;
: _DBSVC.ENTRIES ( service -- entries ) _DBSVC-ENTRIES + ;
: DBSVC-OWNER    ( service -- owner ) _DBSVC-OWNER + ;
: _DBSVC.RUNNER  ( service -- runner ) _DBSVC-RUNNER + ;

: DBSVC-VALID?  ( service -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _DBSVC.MAGIC @ _DBSVC-MAGIC <> IF DROP 0 EXIT THEN
    DUP _DBSVC.SELF @ = ;

\ The latest notice.
: DBSVC-NOTICE  ( service -- address length )
    DUP _DBSVC.TEXT SWAP _DBSVC.LEN @ ;

\ What the runner last saw of the wall clock: DBRUN-CLOCK-*.
: DBSVC-CLOCK@  ( service -- clock ) _DBSVC.RUNNER DBRUN-CLOCK@ ;

\ How the latest look went: the owner's status.
: DBSVC-STATUS@  ( service -- status ) _DBSVC.STATUS @ ;

\ The wall clock as owner operations take it.
: DBSVC-NOW  ( -- now )
    DT-CLOCK-VALID? IF EPOCH@ ELSE DBAO-CLOCK-UNSET THEN ;

: _DBSVC-PATH$  ( -- address length ) S" /daybook-automations.bin" ;

\ Opens the reminders in VFS.  The service works whatever the store's
\ state, so a blocked store can say why; the status is the store's.
: DBSVC-OPEN  ( vfs service -- status )
    DUP 0= OVER 7 AND OR IF 2DROP DBAO-S-INVALID EXIT THEN
    DUP DBSVC-VALID? IF 2DROP DBAO-S-STATE EXIT THEN
    DUP DBSVC-SIZE 0 FILL
    >R _DBSVC-PATH$ R@ DBSVC-OWNER DBAO-INIT ?DUP IF
        R> DBSVC-SIZE 0 FILL EXIT
    THEN
    R@ DBSVC-OWNER R@ _DBSVC.RUNNER DBRUN-INIT
    R@ DUP _DBSVC.SELF !
    _DBSVC-MAGIC R@ _DBSVC.MAGIC !
    R> DBSVC-OWNER DBAO-OPEN ;

\ Frees what the service holds.
: DBSVC-CLOSE  ( service -- )
    DUP DBSVC-VALID? 0= IF DROP EXIT THEN
    DUP DBSVC-OWNER DBAO-CLOSE DROP
    DBSVC-SIZE 0 FILL ;

\ Appends text to the notice, as much as fits.
: _DBSVC-ADD  ( address length service -- )
    >R
    DBSVC-NOTICE-MAX R@ _DBSVC.LEN @ - MIN 0 MAX
    TUCK R@ _DBSVC.TEXT R@ _DBSVC.LEN @ + SWAP MOVE
    R> _DBSVC.LEN +! ;

\ How a look's item begins a notice.
: _DBSVC-PREFIX  ( item -- address length )
    DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT = IF
        DBAS-O.PHASE @ DBAS-ENDED = IF S" Needs review: " ELSE S" Agent run: " THEN
        EXIT
    THEN
    DBAS-O.KIND @ DBAS-MISSED = IF S" Missed: " ELSE S" Reminder: " THEN ;

\ "Reminder: <title>" or "Missed: <title>" for one reminder, "Needs
\ review: <title>" for an Agent run that ended at once, and "Reminders:
\ <title> and N more" (or "Automations:" when not all were reminders)
\ when several came due.
: _DBSVC-NOTICE!  ( service -- )
    0 OVER _DBSVC.LEN !
    DUP _DBSVC.ITEM @ OVER DBSVC-OWNER DBAO-STORE DBAS-FIND-OCCURRENCE 0= IF
        2DROP EXIT
    THEN                                               ( service index )
    OVER DBSVC-OWNER DBAO-STORE DBAS-OCCURRENCE        ( service item )
    DUP DBAS-O.RID 2 PICK DBSVC-OWNER DBAO-FIND        ( service item schedule|0 )
    ?DUP 0= IF 2DROP EXIT THEN
    2 PICK _DBSVC.FIRED @ 1 > IF
        NIP OVER _DBSVC.MIXED @ IF S" Automations: " ELSE S" Reminders: " THEN
    ELSE
        SWAP _DBSVC-PREFIX
    THEN                                               ( service schedule a u )
    3 PICK _DBSVC-ADD
    DBAS-S.TITLE DBAS-FIELD$ 2 PICK _DBSVC-ADD         ( service )
    DUP _DBSVC.FIRED @ 1 > IF
        S"  and " 2 PICK _DBSVC-ADD
        DUP _DBSVC.FIRED @ 1- NUM>STR 2 PICK _DBSVC-ADD
        S"  more" 2 PICK _DBSVC-ADD
    THEN
    DROP ;

\ An Agent run's permission standing.  Without a broker it is unavailable.
: _DBSVC-STANDING  ( schedule service -- standing )
    DROP DBAS-S.ACTION @ DBAS-ACTION-AGENT = IF SDSP-A-UNAVAILABLE ELSE 0 THEN ;

\ Accepts one due entry and counts the item it made or added to.
: _DBSVC-ACCEPT-ONE  ( entry service -- status )
    >R
    DUP DBAO-E.RID R@ DBSVC-OWNER DBAO-FIND ?DUP 0= IF
        DROP R> DROP DBAO-S-OK EXIT
    THEN                                               ( entry schedule )
    DUP DBAS-S.ACTION @ DBAS-ACTION-AGENT = IF -1 R@ _DBSVC.MIXED ! THEN
    R@ _DBSVC-STANDING                                 ( entry standing )
    R@ _DBSVC.BASIS @ SWAP R@ _DBSVC.WALL @
    R@ DBSVC-OWNER DBAO-OCC-ACCEPT                     ( id status )
    DUP DBAO-S-OK = IF
        DROP R@ _DBSVC.ITEM ! 1 R> _DBSVC.FIRED +! DBAO-S-OK EXIT
    THEN
    NIP R> DROP
    DUP DBAO-S-ACCEPTED = IF DROP DBAO-S-OK THEN ;

\ Accepts a page of N entries; the status of the first that failed.
: _DBSVC-PAGE!  ( n service -- status )
    SWAP 0 ?DO
        I DBAO-DUE-SIZE * OVER _DBSVC.ENTRIES + OVER _DBSVC-ACCEPT-ONE
        ?DUP IF NIP UNLOOP EXIT THEN
    LOOP
    DROP DBAO-S-OK ;

\ Accepts every schedule due at this look's wall clock.  Returns true
\ when a new notice is ready.
: _DBSVC-ACCEPT-DUE  ( service -- notice? )
    0 OVER _DBSVC.FIRED !  0 OVER _DBSVC.ITEM !  0 OVER _DBSVC.MIXED !
    0                                                  ( service cursor )
    BEGIN
        OVER _DBSVC.WALL @ 1000 / SWAP 2 PICK _DBSVC.ENTRIES _DBSVC-PAGE
        4 PICK DBSVC-OWNER DBAO-DUE-QUERY              ( service n cursor' status )
        ?DUP IF >R 2DROP R> SWAP _DBSVC.STATUS ! 0 EXIT THEN
        OVER 3 PICK _DBSVC-PAGE!                       ( service n cursor' status )
        ?DUP IF >R 2DROP R> SWAP _DBSVC.STATUS ! 0 EXIT THEN
        SWAP _DBSVC-PAGE <
    UNTIL
    DROP
    DBAO-S-OK OVER _DBSVC.STATUS !
    DUP _DBSVC.FIRED @ 0= IF DROP 0 EXIT THEN
    _DBSVC-NOTICE! -1 ;

\ Runs the schedules.  Before the runner's next look a tick reads uptime
\ and returns.  A look reads the wall clock and accepts what is due.
\ Returns true when a new notice is ready.
: DBSVC-TICK  ( service -- notice? )
    MS@ DUP 2 PICK _DBSVC.RUNNER DBRUN-NEXT@ < IF 2DROP 0 EXIT THEN
    DT-CLOCK-VALID? IF EPOCH@ -1 ELSE 0 0 THEN       ( service uptime wall valid? )
    OVER 4 PICK _DBSVC.WALL !
    3 PICK _DBSVC.RUNNER DBRUN-LOOK                   ( service basis due? )
    0= IF DROP DBAO-S-OK SWAP _DBSVC.STATUS ! 0 EXIT THEN
    OVER _DBSVC.BASIS !
    _DBSVC-ACCEPT-DUE ;
