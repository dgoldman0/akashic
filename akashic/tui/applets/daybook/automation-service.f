\ =====================================================================
\  automation-service.f - Daybook's reminders inside Desk
\ =====================================================================
\  Desk opens one service over its Practice filesystem when it starts,
\  ticks it, lends it to Daybook, and shows its notices.  The service owns
\  Daybook's reminder owner, the runner that fires reminders, and the text
\  of the latest notice.  That text stays put until the next notice, so a
\  toast may keep pointing at it.
\
\  A tick reads uptime once and, until the runner's next look, does
\  nothing else.  A look reads the wall clock and fires what is due.
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

0x4356534F54554144 CONSTANT _DBSVC-MAGIC  \ "DAUTOSVC"

 0 CONSTANT _DBSVC-MAGIC-OFF
 8 CONSTANT _DBSVC-SELF
16 CONSTANT _DBSVC-STATUS      \ how the latest look went
24 CONSTANT _DBSVC-LEN         \ the notice's length
32 CONSTANT _DBSVC-TEXT
_DBSVC-TEXT DBSVC-NOTICE-MAX + 7 + -8 AND CONSTANT _DBSVC-OWNER
_DBSVC-OWNER DBAO-SIZE + 7 + -8 AND CONSTANT _DBSVC-RUNNER
_DBSVC-RUNNER DBRUN-SIZE + CONSTANT DBSVC-SIZE

: _DBSVC.MAGIC   ( service -- a ) _DBSVC-MAGIC-OFF + ;
: _DBSVC.SELF    ( service -- a ) _DBSVC-SELF + ;
: _DBSVC.STATUS  ( service -- a ) _DBSVC-STATUS + ;
: _DBSVC.LEN     ( service -- a ) _DBSVC-LEN + ;
: _DBSVC.TEXT    ( service -- a ) _DBSVC-TEXT + ;
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

\ The reminder and kind of the latest review item a look made or added to.
: _DBSVC-LAST  ( service -- schedule kind | 0 0 )
    DBSVC-OWNER DUP DBAO-LAST-FIRED@ OVER DBAO-STORE DBAS-FIND-OCCURRENCE
    0= IF 2DROP 0 0 EXIT THEN
    OVER DBAO-STORE DBAS-OCCURRENCE
    DUP DBAS-O.KIND @ >R DBAS-O.RID SWAP DBAO-FIND R>
    OVER 0= IF 2DROP 0 0 THEN ;

\ "Reminder: <title>" or "Missed: <title>" for one reminder, and
\ "Reminders: <title> and N more" when several fired.
: _DBSVC-NOTICE!  ( fired service -- )
    0 OVER _DBSVC.LEN !
    DUP _DBSVC-LAST                           ( fired service schedule kind )
    OVER 0= IF 2DROP 2DROP EXIT THEN
    3 PICK 1 > IF
        DROP S" Reminders: "
    ELSE
        DBAS-MISSED = IF S" Missed: " ELSE S" Reminder: " THEN
    THEN
    3 PICK _DBSVC-ADD
    DBAS-S.TITLE DBAS-FIELD$ 2 PICK _DBSVC-ADD
    OVER 1 > IF
        S"  and " 2 PICK _DBSVC-ADD
        OVER 1- NUM>STR 2 PICK _DBSVC-ADD
        S"  more" 2 PICK _DBSVC-ADD
    THEN
    2DROP ;

\ Runs the reminders.  Before the runner's next look a tick reads uptime
\ and returns.  A look reads the wall clock and fires what is due.
\ Returns true when a new notice is ready.
: DBSVC-TICK  ( service -- notice? )
    MS@ DUP 2 PICK _DBSVC.RUNNER DBRUN-NEXT@ < IF 2DROP 0 EXIT THEN
    DT-CLOCK-VALID? IF EPOCH@ -1 ELSE 0 0 THEN
    3 PICK _DBSVC.RUNNER DBRUN-LOOK           ( service fired status )
    DUP IF 2 PICK _DBSVC.STATUS ! 2DROP 0 EXIT THEN
    2 PICK _DBSVC.STATUS !
    DUP 0= IF 2DROP 0 EXIT THEN
    SWAP _DBSVC-NOTICE! -1 ;
