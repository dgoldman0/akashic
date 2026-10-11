\ =====================================================================
\  scheduled-runs.f - The Agent's view of its scheduled runs
\ =====================================================================
\  The view lists the scheduled runs the Agent's dispatcher recorded
\  (dispatch.f), newest first.  Each row has a title and a detail.  The
\  title is the schedule's, while the run keeps its request; past the
\  store's keep setting a run has only its row, and its title says so.
\  The detail tells when the run was accepted, how it ended or that it is
\  running, and the model it ran on, when the run kept its request.
\
\  Opening a row decodes that run's transcript into a conversation the
\  view owns, for the Agent to show in place of the chat until it is
\  closed.  A run past the keep setting has no transcript to open.
\
\  The view borrows the dispatcher Desk lends the Agent, 0 when the Agent
\  runs outside Desk.  Rows are counted when the view is rebuilt and are
\  stale once the run store writes again; row words take an index below
\  ASRV-COUNT@, and what they return stays put until the next call into
\  the view or the store.  The view is caller-owned and caller-serialized.
\
\  Public API:
\    ASRV-SIZE     ( -- bytes )
\    ASRV-INIT     ( dispatch view -- )
\    ASRV-FREE     ( view -- )
\    ASRV-STALE?   ( view -- flag )
\    ASRV-REBUILD  ( view -- )
\    ASRV-COUNT@   ( view -- n )
\    ASRV-KEY      ( index view -- key )
\    ASRV-SERIAL   ( index view -- serial )
\    ASRV-TITLE    ( index view -- address length )
\    ASRV-DETAIL   ( index view -- address length )
\    ASRV-NOTE     ( view -- address length )
\    ASRV-OPEN     ( index view -- status )
\    ASRV-SHOWN    ( view -- conversation|0 )
\    ASRV-CLOSE    ( view -- )
\ =====================================================================

PROVIDED akashic-agent-scheduled-runs

REQUIRE dispatch.f
REQUIRE storage/thread-codec.f
REQUIRE ../../../utils/datetime.f
REQUIRE ../../../utils/string.f

0 CONSTANT ASRV-S-OK
1 CONSTANT ASRV-S-NONE      \ no such row, or the run kept no transcript
2 CONSTANT ASRV-S-INVALID   \ its transcript could not be read
3 CONSTANT ASRV-S-NOMEM

\ The view:
\    +0 the dispatcher   +8 the store generation the rows were counted at
\   +16 the row count    +24 the conversation shown, or 0
\   +32 a text buffer the row words write into   +40 its capacity
\   +48 its length
56 CONSTANT ASRV-SIZE
: _ASRV.DISPATCH    ( view -- a ) ;
: _ASRV.GENERATION  ( view -- a ) 8 + ;
: _ASRV.COUNT       ( view -- a ) 16 + ;
: _ASRV.SHOWN       ( view -- a ) 24 + ;
: _ASRV.BUF         ( view -- a ) 32 + ;
: _ASRV.CAP         ( view -- a ) 40 + ;
: _ASRV.LEN         ( view -- a ) 48 + ;

: ASRV-INIT  ( dispatch view -- )
    DUP ASRV-SIZE 0 FILL
    _ASRV.DISPATCH ! ;

\ The run store, or 0 outside Desk.
: _ASRV-STORE  ( view -- store|0 )
    _ASRV.DISPATCH @ DUP ADISP-VALID? IF ADISP-STORE ELSE DROP 0 THEN ;

\ The run store, when it can be read.
: _ASRV-READY  ( view -- store|0 )
    _ASRV-STORE DUP IF DUP ADST-STATE@ ADST-READY <> IF DROP 0 THEN THEN ;

: ASRV-CLOSE  ( view -- )
    DUP _ASRV.SHOWN @ ?DUP IF ACONV-FREE THEN
    0 SWAP _ASRV.SHOWN ! ;

: ASRV-FREE  ( view -- )
    DUP ASRV-CLOSE
    DUP _ASRV.BUF @ ?DUP IF FREE THEN
    ASRV-SIZE 0 FILL ;

\ Whether the store wrote since the rows were counted.
: ASRV-STALE?  ( view -- flag )
    DUP _ASRV-READY ?DUP 0= IF _ASRV.COUNT @ 0<> EXIT THEN
    DUP ADST-GENERATION@ 2 PICK _ASRV.GENERATION @ <>
    SWAP ADST-COUNT@ ROT _ASRV.COUNT @ <> OR ;

: ASRV-REBUILD  ( view -- )
    DUP _ASRV-READY ?DUP 0= IF 0 SWAP _ASRV.COUNT ! EXIT THEN
    DUP ADST-GENERATION@ 2 PICK _ASRV.GENERATION !
    ADST-COUNT@ SWAP _ASRV.COUNT ! ;

: ASRV-COUNT@  ( view -- n ) _ASRV.COUNT @ ;

\ The run row INDEX shows: the newest first.
: _ASRV-RUN  ( index view -- run )
    TUCK ASRV-COUNT@ SWAP - 1- SWAP _ASRV-STORE ADST-NTH ;

\ The run's dispatch key, which names a row across rebuilds.
: ASRV-KEY  ( index view -- key ) _ASRV-RUN ADST-R.KEY ;

\ The run's serial in the store, which names a row in a list.
: ASRV-SERIAL  ( index view -- serial ) _ASRV-RUN ADST-R.SERIAL @ ;

\ ---------------------------------------------------------------------
\  Text
\ ---------------------------------------------------------------------

\ Empties the buffer and gives it room for U bytes.
: _ASRV-ROOM  ( u view -- status )
    0 OVER _ASRV.LEN !
    2DUP _ASRV.CAP @ > 0= IF 2DROP ASRV-S-OK EXIT THEN
    OVER ALLOCATE IF 2DROP DROP ASRV-S-NOMEM EXIT THEN   ( u view new )
    OVER _ASRV.BUF @ ?DUP IF FREE THEN
    OVER _ASRV.BUF !
    _ASRV.CAP ! ASRV-S-OK ;

\ Adds text to the buffer, which has room for it.
: _ASRV+  ( address length view -- )
    >R R@ _ASRV.BUF @ R@ _ASRV.LEN @ + SWAP DUP R> _ASRV.LEN +! MOVE ;

: _ASRV$  ( view -- address length ) DUP _ASRV.BUF @ SWAP _ASRV.LEN @ ;

\ The request a run kept, or 0: past the keep setting its slot is empty.
: _ASRV-REQUEST  ( run -- request|0 ) ADST-REQUEST$ DROP ;

\ Row INDEX's title: its schedule's, or, for a run that kept only its
\ row, "Run" and its serial.
: ASRV-TITLE  ( index view -- address length )
    TUCK _ASRV-RUN DUP _ASRV-REQUEST ?DUP IF NIP NIP SDSP-TITLE$ EXIT THEN
    ADST-R.SERIAL @ NUM>STR ROT >R                   ( a u ; R: view )
    \ The serial, and 4 bytes before it and 22 after.
    DUP 26 + R@ _ASRV-ROOM IF 2DROP R> DROP 0 0 EXIT THEN
    S" Run " R@ _ASRV+ R@ _ASRV+
    S"  (transcript not kept)" R@ _ASRV+ R> _ASRV$ ;

\ When a run was accepted, "YYYY-MM-DD HH:MM UTC", or that it is not
\ known.  The RFC 3339 form is written in place and reshaped: its T
\ becomes a space, and its seconds and Z the zone's name.
: _ASRV-WHEN+  ( run view -- )
    >R ADST-R.ACCEPTED @ DUP 0> IF
        1000 / R@ _ASRV.BUF @ R@ _ASRV.LEN @ +       ( seconds at )
        DUP >R DT-RFC3339-UTC-S-LENGTH DT-RFC3339-UTC-S NIP 0= IF
            BL R@ 10 + C!  S"  UTC" R> 16 + SWAP MOVE
            DT-RFC3339-UTC-S-LENGTH R> _ASRV.LEN +! EXIT
        THEN
        R> DROP
    ELSE
        DROP
    THEN
    S" time unknown" R> _ASRV+ ;

\ How a run ended, or that it is running.
: _ASRV-OUTCOME$  ( run -- address length )
    DUP ADST-R.PHASE @ ADST-ENDED = IF ADST-R.OUTCOME @ SACT-OUTCOME$ EXIT THEN
    DROP S" running" ;

\ Why it ended so, or 0 0: a run in flight has no reason yet.
: _ASRV-REASON$  ( run -- address length ) ADST-R.REASON @ SACT-REASON$ ;

\ The model, when the run kept its request, or 0 0.
: _ASRV-MODEL$  ( run -- address length )
    _ASRV-REQUEST ?DUP IF SDSP-OPERANDS$ DROP SACT-MODEL$ ELSE 0 0 THEN ;

\ A part's length with the two bytes before it, when it has any.
: _ASRV-PART  ( u -- u' ) DUP IF 2 + THEN ;

\ Adds a part after SEPARATOR, when it has any.
: _ASRV-PART+  ( address length separator-a separator-u view -- )
    >R 2 PICK IF R@ _ASRV+ R> _ASRV+ EXIT THEN 2DROP 2DROP R> DROP ;

\ Row INDEX's detail: when, how it ended or that it is running, and the
\ model when the run kept its request.
: ASRV-DETAIL  ( index view -- address length )
    TUCK _ASRV-RUN SWAP >R                           ( run ; R: view )
    \ The time, at most an RFC 3339 instant's length, and the parts.  A
    \ time that formats fills its room exactly.
    DT-RFC3339-UTC-S-LENGTH
    OVER _ASRV-OUTCOME$ NIP _ASRV-PART +
    OVER _ASRV-REASON$ NIP _ASRV-PART +
    OVER _ASRV-MODEL$ NIP _ASRV-PART +
    R@ _ASRV-ROOM IF DROP R> DROP 0 0 EXIT THEN
    DUP R@ _ASRV-WHEN+
    DUP _ASRV-OUTCOME$ S"   " R@ _ASRV-PART+
    DUP _ASRV-REASON$ S" : " R@ _ASRV-PART+
    _ASRV-MODEL$ S"   " R@ _ASRV-PART+
    R> _ASRV$ ;

\ What the view says when it has no rows, or how many it has.
: ASRV-NOTE  ( view -- address length )
    DUP _ASRV-STORE 0= IF DROP S" Scheduled runs come through Desk" EXIT THEN
    DUP _ASRV-READY 0= IF
        DROP S" The record of scheduled runs cannot be read" EXIT
    THEN
    ASRV-COUNT@ 0= IF S" No scheduled runs yet" EXIT THEN
    S" Enter opens a run's transcript; Escape returns" ;

\ ---------------------------------------------------------------------
\  Transcripts
\ ---------------------------------------------------------------------

\ Opens row INDEX's transcript, in place of any shown before.
: ASRV-OPEN  ( index view -- status )
    OVER 0< OVER ASRV-COUNT@ 3 PICK > 0= OR IF 2DROP ASRV-S-NONE EXIT THEN
    DUP ASRV-STALE? IF 2DROP ASRV-S-NONE EXIT THEN
    TUCK _ASRV-RUN ADST-TRANSCRIPT$                  ( view address length )
    DUP 0= IF 2DROP DROP ASRV-S-NONE EXIT THEN
    ATHREAD-DECODE NIP                               ( view conversation status )
    ?DUP IF
        NIP NIP ATHREAD-S-NOMEM = IF ASRV-S-NOMEM ELSE ASRV-S-INVALID THEN EXIT
    THEN
    OVER ASRV-CLOSE SWAP _ASRV.SHOWN ! ASRV-S-OK ;

\ The transcript opened, or 0.
: ASRV-SHOWN  ( view -- conversation|0 ) _ASRV.SHOWN @ ;
