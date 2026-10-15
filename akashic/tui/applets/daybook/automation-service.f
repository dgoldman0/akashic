\ =====================================================================
\  automation-service.f - Daybook's schedules inside Desk
\ =====================================================================
\  Desk opens one service over its Practice filesystem when it starts,
\  ticks it, lends it to Daybook alone, and shows its notices.  The
\  service owns Daybook's schedule owner, the runner that says when
\  schedules come due, and the text of the latest notice.  That text stays
\  put until the next notice, so a toast may keep pointing at it.
\
\  Desk gives the service a dispatch client (interop/scheduled-
\  dispatch.f), through which it reaches Desk's broker; Daybook imports no
\  Desk or Agent code.  Without a client the Agent is unavailable.
\
\  A tick reads uptime once and, until the runner's next look, does
\  nothing else.  A look, once a second, reads the wall clock and accepts
\  what is due, a page of schedules at a time: a reminder makes its review
\  item, and an Agent run is accepted or blocked by its permission's
\  standing, which the broker answers.  An accepted run is handed to the
\  broker at once.  While runs are in flight, each look then asks the
\  broker how each stands and records when it starts and how it ends.  A
\  run the broker does not know never started, if it had not, or is
\  indeterminate, if it had: this also settles the runs left in flight
\  when Desk last stopped.  Nothing is retried.
\
\  Through the same client the service asks for an approval and records
\  the answer, starts a run by hand, cancels one, fetches the models a
\  schedule may name, and asks what a document a run may read is.
\
\  Public API:
\    DBSVC-SIZE        ( -- bytes )
\    DBSVC-OPEN        ( vfs service -- status )
\    DBSVC-CLOSE       ( service -- )
\    DBSVC-CLIENT!     ( client service -- )
\    DBSVC-TICK        ( service -- notice? )
\    DBSVC-NOTICE      ( service -- address length )
\    DBSVC-NOTICE-SEVERITY ( service -- severity )
\    DBSVC-OWNER       ( service -- owner )
\    DBSVC-CLOCK@      ( service -- clock )
\    DBSVC-STATUS@     ( service -- status )
\    DBSVC-NOW         ( -- now )
\    DBSVC-IN-FLIGHT?  ( service -- flag )
\    DBSVC-RUN-NOW     ( rid revision service -- id status )
\    DBSVC-CANCEL      ( id service -- status )
\    DBSVC-ASK         ( rid revision service -- status )
\    DBSVC-ASK-STATE@  ( service -- state )
\    DBSVC-ASK-RID     ( service -- rid )
\    DBSVC-MODELS      ( buffer capacity service -- bytes status )
\    DBSVC-DESCRIBE    ( locator facts service -- status )
\    DBSVC-LABEL       ( rid service -- address length )
\    DBSVC-WHEN$       ( schedule service -- address length )
\ =====================================================================

PROVIDED akashic-dbk-auto-svc

REQUIRE automation-runner.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../utils/buffer-writer.f

\ The longest notice: a prefix, a whole title, and how many more fired.
DBAS-TITLE-MAX 64 + CONSTANT DBSVC-NOTICE-MAX

\ The longest trigger: a rule's description and its zone in parentheses.
DBREC-DESCRIBE-MAX 3 + TZ-STRING-MAX + CONSTANT _DBSVC-TRIGGER-MAX

\ Due schedules read per page.
8 CONSTANT _DBSVC-PAGE

\ The summary room a response starts with; it grows to what a summary
\ needs.
128 CONSTANT _DBSVC-SUMMARY-START

\ Statuses beyond the owner's.
30 CONSTANT DBSVC-S-UNAVAILABLE   \ the broker cannot be reached
31 CONSTANT DBSVC-S-PENDING       \ an approval is already being asked for

\ Where the latest approval asked for stands.
0 CONSTANT DBSVC-ASK-NONE
1 CONSTANT DBSVC-ASK-PENDING
2 CONSTANT DBSVC-ASK-ALLOWED      \ and recorded
3 CONSTANT DBSVC-ASK-REFUSED
4 CONSTANT DBSVC-ASK-GONE         \ withdrawn unanswered
5 CONSTANT DBSVC-ASK-FAILED       \ allowed, but not recorded: the schedule
                                  \ changed meanwhile, or the store refused

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
 72 CONSTANT _DBSVC-ENDED       \ a run this look saw end, or 0
 80 CONSTANT _DBSVC-CLIENT      \ Desk's dispatch client, or 0
 88 CONSTANT _DBSVC-REQ         \ the request buffer, or 0
 96 CONSTANT _DBSVC-REQ-ROOM    \ its bytes
104 CONSTANT _DBSVC-RSP         \ the response buffer, or 0
112 CONSTANT _DBSVC-RSP-ROOM    \ the summary room it was made with
120 CONSTANT _DBSVC-SUMMARY     \ the summary room responses need
128 CONSTANT _DBSVC-FLIGHTS     \ runs in flight, counted at
136 CONSTANT _DBSVC-SEEN        \ this store generation, plus one
144 CONSTANT _DBSVC-ASK-STATE
152 CONSTANT _DBSVC-ASK-ID
160 CONSTANT _DBSVC-ASK-REVISION
168 CONSTANT _DBSVC-ASK-RID-OFF \ RID-SIZE bytes
\ Scratch while a request is built.
200 CONSTANT _DBSVC-S           \ the schedule
208 CONSTANT _DBSVC-I           \ the item, or 0
216 CONSTANT _DBSVC-A           \ the schedule's action
224 CONSTANT _DBSVC-SEVERITY    \ the notice's meaning
232 CONSTANT _DBSVC-WRITER      \ CBW-SIZE bytes
_DBSVC-WRITER CBW-SIZE + CONSTANT _DBSVC-TEXT
_DBSVC-TEXT DBSVC-NOTICE-MAX + 7 + -8 AND CONSTANT _DBSVC-TRIGGER
_DBSVC-TRIGGER _DBSVC-TRIGGER-MAX + 7 + -8 AND CONSTANT _DBSVC-ENTRIES
_DBSVC-ENTRIES _DBSVC-PAGE DBAO-DUE-SIZE * + CONSTANT _DBSVC-OWNER
_DBSVC-OWNER DBAO-SIZE + 7 + -8 AND CONSTANT _DBSVC-RUNNER
_DBSVC-RUNNER DBRUN-SIZE + CONSTANT DBSVC-SIZE

: _DBSVC.MAGIC        ( service -- a ) _DBSVC-MAGIC-OFF + ;
: _DBSVC.SELF         ( service -- a ) _DBSVC-SELF + ;
: _DBSVC.STATUS       ( service -- a ) _DBSVC-STATUS + ;
: _DBSVC.LEN          ( service -- a ) _DBSVC-LEN + ;
: _DBSVC.SEVERITY     ( service -- a ) _DBSVC-SEVERITY + ;
: _DBSVC.WALL         ( service -- a ) _DBSVC-WALL + ;
: _DBSVC.BASIS        ( service -- a ) _DBSVC-BASIS + ;
: _DBSVC.FIRED        ( service -- a ) _DBSVC-FIRED + ;
: _DBSVC.ITEM         ( service -- a ) _DBSVC-ITEM + ;
: _DBSVC.MIXED        ( service -- a ) _DBSVC-MIXED + ;
: _DBSVC.ENDED        ( service -- a ) _DBSVC-ENDED + ;
: _DBSVC.CLIENT       ( service -- a ) _DBSVC-CLIENT + ;
: _DBSVC.REQ          ( service -- a ) _DBSVC-REQ + ;
: _DBSVC.REQ-ROOM     ( service -- a ) _DBSVC-REQ-ROOM + ;
: _DBSVC.RSP          ( service -- a ) _DBSVC-RSP + ;
: _DBSVC.RSP-ROOM     ( service -- a ) _DBSVC-RSP-ROOM + ;
: _DBSVC.SUMMARY      ( service -- a ) _DBSVC-SUMMARY + ;
: _DBSVC.FLIGHTS      ( service -- a ) _DBSVC-FLIGHTS + ;
: _DBSVC.SEEN         ( service -- a ) _DBSVC-SEEN + ;
: _DBSVC.ASK-STATE    ( service -- a ) _DBSVC-ASK-STATE + ;
: _DBSVC.ASK-ID       ( service -- a ) _DBSVC-ASK-ID + ;
: _DBSVC.ASK-REVISION ( service -- a ) _DBSVC-ASK-REVISION + ;
: DBSVC-ASK-RID       ( service -- rid ) _DBSVC-ASK-RID-OFF + ;
: _DBSVC.S            ( service -- a ) _DBSVC-S + ;
: _DBSVC.I            ( service -- a ) _DBSVC-I + ;
: _DBSVC.A            ( service -- a ) _DBSVC-A + ;
: _DBSVC.WRITER       ( service -- writer ) _DBSVC-WRITER + ;
: _DBSVC.TEXT         ( service -- a ) _DBSVC-TEXT + ;
: _DBSVC.TRIGGER      ( service -- a ) _DBSVC-TRIGGER + ;
: _DBSVC.ENTRIES      ( service -- entries ) _DBSVC-ENTRIES + ;
: DBSVC-OWNER         ( service -- owner ) _DBSVC-OWNER + ;
: _DBSVC.RUNNER       ( service -- runner ) _DBSVC-RUNNER + ;

: DBSVC-VALID?  ( service -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _DBSVC.MAGIC @ _DBSVC-MAGIC <> IF DROP 0 EXIT THEN
    DUP _DBSVC.SELF @ = ;

\ The latest notice.
: DBSVC-NOTICE  ( service -- address length )
    DUP _DBSVC.TEXT SWAP _DBSVC.LEN @ ;

\ What the latest notice means, as a status field's severity: a warning
\ (3) for a missed reminder and a run that needs review, else neutral (0).
: DBSVC-NOTICE-SEVERITY  ( service -- severity ) _DBSVC.SEVERITY @ ;

\ What the runner last saw of the wall clock: DBRUN-CLOCK-*.
: DBSVC-CLOCK@  ( service -- clock ) _DBSVC.RUNNER DBRUN-CLOCK@ ;

\ How the latest look went: the owner's status.
: DBSVC-STATUS@  ( service -- status ) _DBSVC.STATUS @ ;

\ Where the latest approval asked for stands: DBSVC-ASK-*.
: DBSVC-ASK-STATE@  ( service -- state ) _DBSVC.ASK-STATE @ ;

\ The wall clock as owner operations take it.
: DBSVC-NOW  ( -- now )
    DT-CLOCK-VALID? IF EPOCH@ ELSE DBAO-CLOCK-UNSET THEN ;

: _DBSVC-PATH$  ( -- address length ) S" /daybook-automations.bin" ;

\ Opens the schedules in VFS.  The service works whatever the store's
\ state, so a blocked store can say why; the status is the store's.
: DBSVC-OPEN  ( vfs service -- status )
    DUP 0= OVER 7 AND OR IF 2DROP DBAO-S-INVALID EXIT THEN
    DUP DBSVC-VALID? IF 2DROP DBAO-S-STATE EXIT THEN
    DUP DBSVC-SIZE 0 FILL
    >R _DBSVC-PATH$ R@ DBSVC-OWNER DBAO-INIT ?DUP IF
        R> DBSVC-SIZE 0 FILL EXIT
    THEN
    R@ DBSVC-OWNER R@ _DBSVC.RUNNER DBRUN-INIT
    _DBSVC-SUMMARY-START R@ _DBSVC.SUMMARY !
    R@ DUP _DBSVC.SELF !
    _DBSVC-MAGIC R@ _DBSVC.MAGIC !
    R> DBSVC-OWNER DBAO-OPEN ;

\ Frees what a cell at A holds, and zeroes it.
: _DBSVC-FREE  ( a -- ) DUP @ ?DUP IF FREE THEN 0 SWAP ! ;

\ Frees what the service holds.
: DBSVC-CLOSE  ( service -- )
    DUP DBSVC-VALID? 0= IF DROP EXIT THEN
    DUP _DBSVC.REQ _DBSVC-FREE
    DUP _DBSVC.RSP _DBSVC-FREE
    DUP DBSVC-OWNER DBAO-CLOSE DROP
    DBSVC-SIZE 0 FILL ;

\ The broker's client Desk gives the service, or 0 for none.
: DBSVC-CLIENT!  ( client service -- ) _DBSVC.CLIENT ! ;

\ =====================================================================
\  Notices
\ =====================================================================

\ Appends text to the notice, as much as fits.
: _DBSVC-ADD  ( address length service -- )
    >R
    DBSVC-NOTICE-MAX R@ _DBSVC.LEN @ - MIN 0 MAX
    TUCK R@ _DBSVC.TEXT R@ _DBSVC.LEN @ + SWAP MOVE
    R> _DBSVC.LEN +! ;

\ How a look's item begins a notice.
: _DBSVC-PREFIX  ( item -- address length )
    DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT = IF
        DUP DBAS-O.PHASE @ DBAS-ENDED <> IF DROP S" Agent run: " EXIT THEN
        DBAS-O.STATE @ DBAS-CLEAR = IF S" Agent run done: " ELSE S" Needs review: " THEN
        EXIT
    THEN
    DBAS-O.KIND @ DBAS-MISSED = IF S" Missed: " ELSE S" Reminder: " THEN ;

\ What one item's notice means, as its prefix says it.
: _DBSVC-ITEM-SEVERITY  ( item -- severity )
    DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT = IF
        DUP DBAS-O.PHASE @ DBAS-ENDED <> IF DROP 0 EXIT THEN
        DBAS-O.STATE @ DBAS-CLEAR = IF 0 ELSE 3 THEN EXIT
    THEN
    DBAS-O.KIND @ DBAS-MISSED = IF 3 ELSE 0 THEN ;

\ "Reminder: <title>" or "Missed: <title>" for one reminder; "Agent run:
\ <title>" for a run handed over, "Agent run done: <title>" for one that
\ completed, and "Needs review: <title>" for one that ended otherwise;
\ "Reminders: <title> and N more" (or "Automations:" when not all were
\ reminders) when several came due.
: _DBSVC-NOTICE!  ( service -- )
    0 OVER _DBSVC.LEN ! 0 OVER _DBSVC.SEVERITY !
    DUP _DBSVC.ITEM @ OVER DBSVC-OWNER DBAO-STORE DBAS-FIND-OCCURRENCE 0= IF
        2DROP EXIT
    THEN                                               ( service index )
    OVER DBSVC-OWNER DBAO-STORE DBAS-OCCURRENCE        ( service item )
    DUP DBAS-O.RID 2 PICK DBSVC-OWNER DBAO-FIND        ( service item schedule|0 )
    ?DUP 0= IF 2DROP EXIT THEN
    2 PICK _DBSVC.FIRED @ 1 > IF
        NIP OVER _DBSVC.MIXED @ IF S" Automations: " ELSE S" Reminders: " THEN
    ELSE
        SWAP DUP _DBSVC-ITEM-SEVERITY 3 PICK _DBSVC.SEVERITY ! _DBSVC-PREFIX
    THEN                                               ( service schedule a u )
    3 PICK _DBSVC-ADD
    DBAS-S.TITLE DBAS-FIELD$ 2 PICK _DBSVC-ADD         ( service )
    DUP _DBSVC.FIRED @ 1 > IF
        S"  and " 2 PICK _DBSVC-ADD
        DUP _DBSVC.FIRED @ 1- NUM>STR 2 PICK _DBSVC-ADD
        S"  more" 2 PICK _DBSVC-ADD
    THEN
    DROP ;

\ The notice for this look: what it accepted, or else a run that ended.
\ True when there is one.
: _DBSVC-NOTICE?  ( service -- notice? )
    DUP _DBSVC.FIRED @ 0= IF
        DUP _DBSVC.ENDED @ ?DUP 0= IF DROP 0 EXIT THEN
        OVER _DBSVC.ITEM ! 1 OVER _DBSVC.FIRED !
    THEN
    _DBSVC-NOTICE! -1 ;

\ =====================================================================
\  Requests and responses
\ =====================================================================

\ The request buffer with room for BYTES, or 0 when memory ran out.
: _DBSVC-REQ-ROOM  ( bytes service -- request|0 )
    2DUP _DBSVC.REQ-ROOM @ > OVER _DBSVC.REQ @ 0= OR IF
        DUP _DBSVC.REQ _DBSVC-FREE 0 OVER _DBSVC.REQ-ROOM !
        OVER ALLOCATE IF 2DROP DROP 0 EXIT THEN        ( bytes service new )
        OVER _DBSVC.REQ ! TUCK _DBSVC.REQ-ROOM !
    ELSE
        NIP
    THEN
    _DBSVC.REQ @ ;

\ A cleared response with the summary room the broker last needed, or 0
\ when memory ran out.
: _DBSVC-RESPONSE  ( service -- response|0 )
    DUP _DBSVC.SUMMARY @ OVER _DBSVC.RSP-ROOM @ <>
    OVER _DBSVC.RSP @ 0= OR IF
        DUP _DBSVC.RSP _DBSVC-FREE
        DUP _DBSVC.SUMMARY @ SDSP-RESPONSE-SIZE ALLOCATE IF 2DROP 0 EXIT THEN
        OVER _DBSVC.RSP !
        DUP _DBSVC.SUMMARY @ OVER _DBSVC.RSP-ROOM !
    THEN
    DUP _DBSVC.RSP-ROOM @ SWAP _DBSVC.RSP @ TUCK SDSP-RESPONSE-INIT ;

\ After a response too small for its summary, the next has room for it.
: _DBSVC-GROW  ( response service -- )
    SWAP SDSP-P.SUMMARY-U @ OVER _DBSVC.SUMMARY @ MAX SWAP _DBSVC.SUMMARY ! ;

\ When SCHEDULE runs, in words, with its zone, as Desk's approval shows
\ it.  The text stays put until the next call.
: DBSVC-WHEN$  ( schedule service -- address length )
    DUP _DBSVC.TRIGGER _DBSVC-TRIGGER-MAX 2 PICK _DBSVC.WRITER CBW-INIT DROP
    _DBSVC.WRITER                                      ( schedule writer )
    OVER DBAS-S.RULE OVER DBREC-DESCRIBE
    S"  (" 2 PICK CBW-APPEND DROP
    SWAP DBAS-S.ZONE DBAS-FIELD$ 2 PICK CBW-APPEND DROP
    [CHAR] ) OVER CBW-CHAR DROP
    CBW-RESULT DROP ;

\ The request for SCHEDULE, which runs the Agent: an approval or a
\ standing check when ITEM is 0, the hand-over of ITEM otherwise.  It
\ stays put until the next request; 0 when memory ran out.
: _DBSVC-REQUEST  ( schedule item service -- request|0 )
    >R R@ _DBSVC.I ! DUP R@ _DBSVC.S !
    DBAS-S.RID R@ DBSVC-OWNER DBAO-ACTION R@ _DBSVC.A !
    R@ _DBSVC.S @ DBAS-S.TITLE @
    R@ _DBSVC.S @ R@ DBSVC-WHEN$ NIP
    R@ _DBSVC.A @ DBAS-A.OPERANDS 8 + @
    SDSP-REQUEST-SIZE DUP R@ _DBSVC-REQ-ROOM           ( bytes request|0 )
    ?DUP 0= IF DROP R> DROP 0 EXIT THEN
    TUCK SDSP-REQUEST-INIT                             ( request )
    DBAS-ACTION-AGENT OVER SDSP-R.ACTION !
    R@ _DBSVC.A @ DBAS-A.SCHEMA @ OVER SDSP-R.SCHEMA !
    R@ _DBSVC.A @ DBAS-A.PRACTICE OVER SDSP-R.PRACTICE RID-SIZE MOVE
    R@ DBSVC-OWNER DBAO-STORE DBAS-HEADER DBAS-H.STORE-ID
        OVER SDSP-R.STORE RID-SIZE MOVE
    R@ _DBSVC.S @ DBAS-S.RID OVER SDSP-R.SCHEDULE RID-SIZE MOVE
    R@ _DBSVC.S @ DBAS-S.REVISION @ OVER SDSP-R.REVISION !
    R@ _DBSVC.A @ DBAS-A.PERMISSION OVER SDSP-R.PERMISSION RID-SIZE MOVE
    R@ _DBSVC.A @ DBAS-A.PERMISSION-REVISION @ OVER SDSP-R.PERMISSION-REVISION !
    R@ _DBSVC.I @ ?DUP IF
        DUP DBAS-O.ID @ 2 PICK SDSP-R.OCCURRENCE !
        DUP DBAS-O.KIND @ 2 PICK SDSP-R.KIND !
        DBAS-O.KEY OVER SDSP-R.KEY 32 MOVE
    THEN
    DBAS-ACTION-AGENT R@ _DBSVC.A @ DBAS-A.SCHEMA @
        R@ _DBSVC.A @ DBAS-A.OPERANDS BSLOT$ 4 PICK SDSP-R.OPERANDS-DIGEST
        SACT-DIGEST
    R@ _DBSVC.S @ OVER SDSP-R.TRIGGER-DIGEST DBAO-TRIGGER-DIGEST
    R@ _DBSVC.S @ DBAS-S.TITLE DBAS-FIELD$ 2 PICK SDSP-TAIL+
    R@ _DBSVC.WRITER CBW-RESULT DROP 2 PICK SDSP-TAIL+
    R> _DBSVC.A @ DBAS-A.OPERANDS BSLOT$ 2 PICK SDSP-TAIL+ ;

\ =====================================================================
\  Runs
\ =====================================================================

\ The item with ID, or 0.
: _DBSVC-ITEM  ( id service -- item|0 )
    DBSVC-OWNER DBAO-STORE TUCK DBAS-FIND-OCCURRENCE IF
        SWAP DBAS-OCCURRENCE
    ELSE
        2DROP 0
    THEN ;

\ An Agent run's permission standing, as the broker answers it.  Without
\ a broker the Agent is unavailable, whatever else holds; a schedule
\ Daybook does not hold approved has none, without asking.
: _DBSVC-STANDING  ( schedule service -- standing )
    OVER DBAS-S.ACTION @ DBAS-ACTION-AGENT <> IF 2DROP 0 EXIT THEN
    DUP _DBSVC.CLIENT @ 0= IF 2DROP SDSP-A-UNAVAILABLE EXIT THEN
    OVER DBAS-S.RID OVER DBSVC-OWNER DBAO-ACTION DBAS-A.AUTHORIZED @ 0= IF
        2DROP SDSP-A-NONE EXIT
    THEN
    TUCK 0 SWAP _DBSVC-REQUEST ?DUP 0= IF DROP SDSP-A-UNAVAILABLE EXIT THEN
    SWAP _DBSVC.CLIENT @ SDSP-CHECK
    IF DROP SDSP-A-UNAVAILABLE THEN ;

\ Ends the run with dispatch KEY from Daybook's side: OUTCOME for REASON,
\ with no run and no summary.
: _DBSVC-END  ( key outcome reason service -- )
    >R R@ _DBSVC-RESPONSE ?DUP 0= IF 2DROP DROP R> DROP EXIT THEN
    TUCK SDSP-P.REASON ! TUCK SDSP-P.OUTCOME !          ( key response )
    DBSVC-NOW R> DBSVC-OWNER DBAO-OCC-FINISH DROP ;

\ Records what the broker answered, as STATUS and RESPONSE, about ITEM's
\ run, which is in flight.  A run it does not know never started, or is
\ indeterminate if it had; a run waiting, or no answer now, is asked
\ about again at the next look.
: _DBSVC-ANSWERED  ( item response status service -- )
    >R
    DUP SDSP-S-STARTED = OVER SDSP-S-RUNNING = OR IF
        DROP SDSP-P.RUN OVER DBAS-O.KEY SWAP           ( item key run )
        ROT DBAS-O.PHASE @ DBAS-ACCEPTED = IF
            DBSVC-NOW R> DBSVC-OWNER DBAO-OCC-STARTED DROP EXIT
        THEN
        2DROP R> DROP EXIT
    THEN
    DUP SDSP-S-ENDED = IF
        DROP DUP SDSP-P.SUMMARY-U @ OVER SDSP-P.CAPACITY @ > IF
            R> _DBSVC-GROW DROP EXIT
        THEN
        SWAP DBAS-O.KEY SWAP DBSVC-NOW R> DBSVC-OWNER DBAO-OCC-FINISH DROP EXIT
    THEN
    DUP SDSP-S-SMALL = IF DROP R> _DBSVC-GROW DROP EXIT THEN
    DUP SDSP-S-UNKNOWN = IF
        2DROP DUP DBAS-O.KEY SWAP DBAS-O.PHASE @ DBAS-ACCEPTED = IF
            SACT-O-NOT-STARTED SACT-R-RESTART
        ELSE
            SACT-O-INDETERMINATE SACT-R-AGENT-LOST
        THEN
        R> _DBSVC-END EXIT
    THEN
    DUP SDSP-S-INVALID = IF
        2DROP DBAS-O.KEY SACT-O-BLOCKED SACT-R-INVALID R> _DBSVC-END EXIT
    THEN
    2DROP DROP R> DROP ;

\ Hands ITEM, an accepted run, to the broker.  A run Daybook cannot build
\ a request for is out of room; one the broker cannot take now ends at
\ once, as the Agent being unavailable.
: _DBSVC-SUBMIT  ( item service -- )
    >R
    DUP DBAS-O.RID R@ DBSVC-OWNER DBAO-FIND            ( item schedule|0 )
    ?DUP 0= IF DROP R> DROP EXIT THEN
    OVER R@ _DBSVC-REQUEST                             ( item request|0 )
    ?DUP 0= IF
        DBAS-O.KEY SACT-O-BLOCKED SACT-R-CAPACITY R> _DBSVC-END EXIT
    THEN
    R@ _DBSVC-RESPONSE ?DUP 0= IF
        DROP DBAS-O.KEY SACT-O-BLOCKED SACT-R-CAPACITY R> _DBSVC-END EXIT
    THEN                                               ( item request response )
    TUCK R@ _DBSVC.CLIENT @ SDSP-SUBMIT                ( item response status )
    DUP SDSP-S-UNAVAILABLE = IF
        2DROP DBAS-O.KEY SACT-O-BLOCKED SACT-R-AGENT-UNAVAILABLE R> _DBSVC-END
        EXIT
    THEN
    R> _DBSVC-ANSWERED ;

\ Asks the broker how ITEM's run stands, and records it.
: _DBSVC-POLL  ( item service -- )
    >R R@ _DBSVC-RESPONSE ?DUP 0= IF DROP R> DROP EXIT THEN
    OVER DBAS-O.KEY OVER R@ _DBSVC.CLIENT @ SDSP-STATUS
    R> _DBSVC-ANSWERED ;

\ How many runs are in flight, counted again only when the store changed.
: _DBSVC-FLIGHTS  ( service -- n )
    DUP DBSVC-OWNER DBAO-STORE DBAS-GENERATION@ 1+ OVER _DBSVC.SEEN @ <> IF
        0 OVER DBSVC-OWNER DBAO-STORE                  ( service n store )
        DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
            I OVER DBAS-OCCURRENCE DBAS-O.STATE @ DBAS-IN-FLIGHT = IF
                SWAP 1+ SWAP
            THEN
        LOOP
        DROP OVER _DBSVC.FLIGHTS !
        DUP DBSVC-OWNER DBAO-STORE DBAS-GENERATION@ 1+ OVER _DBSVC.SEEN !
    THEN
    _DBSVC.FLIGHTS @ ;

\ Whether a scheduled run is in flight: handed over, waiting or running.
: DBSVC-IN-FLIGHT?  ( service -- flag ) _DBSVC-FLIGHTS 0<> ;

\ The first run in flight with an id above AFTER, or 0.
: _DBSVC-NEXT-FLIGHT  ( after service -- item|0 )
    DBSVC-OWNER DBAO-STORE
    DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
        I OVER DBAS-OCCURRENCE
        DUP DBAS-O.STATE @ DBAS-IN-FLIGHT =
        OVER DBAS-O.ID @ 4 PICK > AND IF NIP NIP UNLOOP EXIT THEN
        DROP
    LOOP
    2DROP 0 ;

\ Notes item ID for this look's notice when its run has ended.
: _DBSVC-ENDED?  ( id service -- )
    TUCK _DBSVC-ITEM ?DUP IF
        DUP DBAS-O.PHASE @ DBAS-ENDED = IF
            DBAS-O.ID @ SWAP _DBSVC.ENDED ! EXIT
        THEN
        DROP
    THEN
    DROP ;

\ =====================================================================
\  Approvals
\ =====================================================================

\ Asks the broker for the answer to the approval asked for, and records
\ it: an approval Daybook takes for the schedule at the revision asked
\ about.
: _DBSVC-ASKED  ( service -- )
    >R R@ _DBSVC-RESPONSE ?DUP 0= IF R> DROP EXIT THEN    ( response )
    R@ _DBSVC.ASK-ID @ OVER R@ _DBSVC.CLIENT @ SDSP-ASKED  ( response status )
    DUP SDSP-S-ALLOWED = IF
        DROP R@ DBSVC-ASK-RID R@ _DBSVC.ASK-REVISION @ ROT
        DBSVC-NOW R@ DBSVC-OWNER DBAO-AUTHORIZE
        IF DBSVC-ASK-FAILED ELSE DBSVC-ASK-ALLOWED THEN R> _DBSVC.ASK-STATE !
        EXIT
    THEN
    DUP SDSP-S-REFUSED = IF 2DROP DBSVC-ASK-REFUSED R> _DBSVC.ASK-STATE ! EXIT THEN
    DUP SDSP-S-GONE = IF 2DROP DBSVC-ASK-GONE R> _DBSVC.ASK-STATE ! EXIT THEN
    DUP SDSP-S-SMALL = IF DROP R> _DBSVC-GROW EXIT THEN
    2DROP R> DROP ;

\ Asks Desk's broker to have the user approve the schedule RID names, at
\ REVISION, which runs the Agent.  One approval is asked for at a time;
\ looks poll for the answer, and DBSVC-ASK-STATE@ says how it stands.
: DBSVC-ASK  ( rid revision service -- status )
    >R
    R@ _DBSVC.ASK-STATE @ DBSVC-ASK-PENDING = IF
        2DROP R> DROP DBSVC-S-PENDING EXIT
    THEN
    R@ _DBSVC.CLIENT @ 0= IF 2DROP R> DROP DBSVC-S-UNAVAILABLE EXIT THEN
    OVER R@ DBSVC-OWNER DBAO-FIND ?DUP 0= IF
        2DROP R> DROP DBAO-S-NOT-FOUND EXIT
    THEN                                               ( rid revision schedule )
    DUP DBAS-S.STATE @ DBAS-TOMBSTONE = IF DROP 2DROP R> DROP DBAO-S-DELETED EXIT THEN
    DUP DBAS-S.REVISION @ 2 PICK <> IF DROP 2DROP R> DROP DBAO-S-CONFLICT EXIT THEN
    DUP DBAS-S.ACTION @ DBAS-ACTION-AGENT <> IF
        DROP 2DROP R> DROP DBAO-S-MANUAL EXIT
    THEN
    0 R@ _DBSVC-REQUEST ?DUP 0= IF 2DROP R> DROP DBAO-S-NOMEM EXIT THEN
    R@ _DBSVC.CLIENT @ SDSP-ASK                        ( rid revision ask-id status )
    DUP SDSP-S-PENDING = OVER SDSP-S-ALLOWED = OR IF
        DROP R@ _DBSVC.ASK-ID ! R@ _DBSVC.ASK-REVISION !
        R@ DBSVC-ASK-RID RID-SIZE MOVE
        DBSVC-ASK-PENDING R> _DBSVC.ASK-STATE ! DBAO-S-OK EXIT
    THEN
    NIP NIP NIP R> DROP
    SDSP-S-INVALID = IF DBAO-S-INVALID ELSE DBSVC-S-UNAVAILABLE THEN ;

\ =====================================================================
\  Looking
\ =====================================================================

\ Accepts one due entry and counts the item it made or added to; an
\ accepted run is handed over at once.
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
        DROP DUP R@ _DBSVC.ITEM ! 1 R@ _DBSVC.FIRED +!
        R@ _DBSVC-ITEM ?DUP IF
            DUP DBAS-O.PHASE @ DBAS-ACCEPTED = IF R@ _DBSVC-SUBMIT ELSE DROP THEN
        THEN
        R> DROP DBAO-S-OK EXIT
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

\ Accepts every schedule due at this look's wall clock.  A failed accept
\ stops the look; the next one tries again.
: _DBSVC-ACCEPT-DUE  ( service -- )
    0                                                  ( service cursor )
    BEGIN
        OVER _DBSVC.WALL @ 1000 / SWAP 2 PICK _DBSVC.ENTRIES _DBSVC-PAGE
        4 PICK DBSVC-OWNER DBAO-DUE-QUERY              ( service n cursor' status )
        ?DUP IF >R 2DROP R> SWAP _DBSVC.STATUS ! EXIT THEN
        OVER 3 PICK _DBSVC-PAGE!                       ( service n cursor' status )
        ?DUP IF >R 2DROP R> SWAP _DBSVC.STATUS ! EXIT THEN
        SWAP _DBSVC-PAGE <
    UNTIL
    DROP DBAO-S-OK SWAP _DBSVC.STATUS ! ;

\ Asks after each run in flight, and after an approval asked for.
: _DBSVC-DISPATCH  ( service -- )
    DUP _DBSVC-FLIGHTS IF
        0 BEGIN                                        ( service after )
            DUP 2 PICK _DBSVC-NEXT-FLIGHT ?DUP
        WHILE                                          ( service after item )
            NIP DUP DBAS-O.ID @ SWAP                   ( service id item )
            2 PICK _DBSVC-POLL
            DUP 2 PICK _DBSVC-ENDED?
        REPEAT
        DROP
    THEN
    DUP _DBSVC.ASK-STATE @ DBSVC-ASK-PENDING = IF DUP _DBSVC-ASKED THEN
    DROP ;

\ Runs the schedules.  Before the runner's next look a tick reads uptime
\ and returns.  A look reads the wall clock, accepts what is due, and asks
\ after runs in flight and an approval asked for.  Returns true when a
\ new notice is ready.
: DBSVC-TICK  ( service -- notice? )
    MS@ DUP 2 PICK _DBSVC.RUNNER DBRUN-NEXT@ < IF 2DROP 0 EXIT THEN
    DT-CLOCK-VALID? IF EPOCH@ -1 ELSE 0 0 THEN       ( service uptime wall valid? )
    OVER 4 PICK _DBSVC.WALL !
    3 PICK _DBSVC.RUNNER DBRUN-LOOK                   ( service basis due? )
    0 3 PICK _DBSVC.FIRED ! 0 3 PICK _DBSVC.ITEM !
    0 3 PICK _DBSVC.MIXED ! 0 3 PICK _DBSVC.ENDED !
    IF
        OVER _DBSVC.BASIS ! DUP _DBSVC-ACCEPT-DUE
    ELSE
        DROP DBAO-S-OK OVER _DBSVC.STATUS !
    THEN
    DUP _DBSVC-DISPATCH
    _DBSVC-NOTICE? ;

\ =====================================================================
\  Asking by hand
\ =====================================================================

\ Starts a run of the schedule RID names, at REVISION, by hand, and hands
\ it to the broker.  The status is the owner's: whether the run was
\ asked for.
: DBSVC-RUN-NOW  ( rid revision service -- id status )
    >R DBSVC-NOW R@ DBSVC-OWNER DBAO-RUN-NOW            ( id status )
    ?DUP IF R> DROP EXIT THEN
    DUP R@ _DBSVC-ITEM ?DUP IF R@ _DBSVC-SUBMIT THEN
    R> DROP DBAO-S-OK ;

\ Cancels run ID, which is in flight.  The broker reports how it ended at
\ a later look; a run the broker does not know ends here, cancelled.
: DBSVC-CANCEL  ( id service -- status )
    >R R@ _DBSVC-ITEM ?DUP 0= IF R> DROP DBAO-S-NOT-FOUND EXIT THEN
    DUP DBAS-O.STATE @ DBAS-IN-FLIGHT <> IF DROP R> DROP DBAO-S-STATE EXIT THEN
    DBAS-O.KEY DUP R@ _DBSVC.CLIENT @ SDSP-CANCEL     ( key status )
    DUP SDSP-S-UNKNOWN = IF
        DROP SACT-O-CANCELLED SACT-R-USER R> _DBSVC-END DBAO-S-OK EXIT
    THEN
    NIP R> DROP
    DUP SDSP-S-UNAVAILABLE = IF DROP DBSVC-S-UNAVAILABLE EXIT THEN
    DUP SDSP-S-INVALID = IF DROP DBAO-S-INVALID EXIT THEN
    DROP DBAO-S-OK ;

\ The models a schedule may name, as the broker lists them
\ (SDSP-LIST-OK?), into BUFFER: their bytes, or SDSP-S-SMALL with the
\ bytes needed.
: DBSVC-MODELS  ( buffer capacity service -- bytes status )
    _DBSVC.CLIENT @ SDSP-MODELS ;

\ What the owner of the document LOCATOR names says of it now, into
\ FACTS, as the broker asks it (SDSP-DESCRIBE).
: DBSVC-DESCRIBE  ( locator facts service -- status )
    _DBSVC.CLIENT @ SDSP-DESCRIBE ;

\ The title of schedule RID, for Desk to name a permission granted for
\ it, or 0 0 when Daybook has no such schedule.  It stays put until the
\ store is next used.
: DBSVC-LABEL  ( rid service -- address length )
    DUP DBSVC-VALID? 0= IF 2DROP 0 0 EXIT THEN
    DBSVC-OWNER DBAO-FIND ?DUP IF DBAS-S.TITLE DBAS-FIELD$ ELSE 0 0 THEN ;
