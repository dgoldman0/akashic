\ =====================================================================
\  automation-runner.f - When Daybook's reminders fire
\ =====================================================================
\  The runner decides when to look for due reminders and what the clock
\  says about them.  The caller gives it each reading of the clock:
\  uptime, the wall clock, and whether the wall clock is set.  It looks
\  once a second of uptime; until the next look a caller's tick is one
\  compare.
\
\  A look while the wall clock is not set fires nothing and writes
\  nothing.  Otherwise the runner compares how far the wall clock and
\  uptime moved since its last look.  When they differ by more than
\  DBRUN-JUMP-MS the wall clock jumped.  The first look after the runner
\  starts, or after the clock is set, has nothing to compare against.  A
\  reminder that comes due across a jump or a start fires as missed.  The
\  owner moves each reminder's next occurrence only forward, so a jump
\  back fires nothing twice.
\
\  The earliest due instant is kept until the store's generation moves,
\  so a look with nothing due reads no reminder records.
\
\  Public API:
\    DBRUN-INIT     ( owner runner -- )
\    DBRUN-LOOK     ( uptime wall valid? runner -- fired status )
\    DBRUN-NEXT@    ( runner -- uptime )
\    DBRUN-CLOCK@   ( runner -- clock )
\ =====================================================================

PROVIDED akashic-dbk-auto-runner

REQUIRE automation-owner.f

\ How often the runner looks, in uptime milliseconds.
1000 CONSTANT DBRUN-PERIOD-MS
\ How far the wall clock may drift from uptime between looks before it
\ counts as a jump.  Both clocks count the same millisecond tick, so they
\ only disagree when the wall clock is set.
2000 CONSTANT DBRUN-JUMP-MS

\ What the last look saw of the wall clock.
0 CONSTANT DBRUN-CLOCK-UNKNOWN     \ no look yet
1 CONSTANT DBRUN-CLOCK-SET
2 CONSTANT DBRUN-CLOCK-UNSET

0x52484E5552424442 CONSTANT _DBRUN-MAGIC  \ "BDBRUNHR"

 0 CONSTANT _DBRUN-MAGIC-OFF
 8 CONSTANT _DBRUN-SELF
16 CONSTANT _DBRUN-OWNER
24 CONSTANT _DBRUN-NEXT        \ uptime of the next look
32 CONSTANT _DBRUN-WALL        \ the wall clock at the last look
40 CONSTANT _DBRUN-UPTIME      \ uptime at the last look
48 CONSTANT _DBRUN-HISTORY     \ a look with the clock set since the start
56 CONSTANT _DBRUN-CLOCK
64 CONSTANT _DBRUN-AT          \ the earliest due instant, UTC seconds
72 CONSTANT _DBRUN-FOUND       \ whether any reminder is due
80 CONSTANT _DBRUN-SEEN        \ the store generation they were read at, plus one
88 CONSTANT DBRUN-SIZE

: _DBRUN.MAGIC    ( runner -- a ) _DBRUN-MAGIC-OFF + ;
: _DBRUN.SELF     ( runner -- a ) _DBRUN-SELF + ;
: _DBRUN.OWNER    ( runner -- a ) _DBRUN-OWNER + ;
: _DBRUN.NEXT     ( runner -- a ) _DBRUN-NEXT + ;
: _DBRUN.WALL     ( runner -- a ) _DBRUN-WALL + ;
: _DBRUN.UPTIME   ( runner -- a ) _DBRUN-UPTIME + ;
: _DBRUN.HISTORY  ( runner -- a ) _DBRUN-HISTORY + ;
: _DBRUN.CLOCK    ( runner -- a ) _DBRUN-CLOCK + ;
: _DBRUN.AT       ( runner -- a ) _DBRUN-AT + ;
: _DBRUN.FOUND    ( runner -- a ) _DBRUN-FOUND + ;
: _DBRUN.SEEN     ( runner -- a ) _DBRUN-SEEN + ;

\ Starts a runner over OWNER.  Its first look is due at once.
: DBRUN-INIT  ( owner runner -- )
    DUP DBRUN-SIZE 0 FILL
    TUCK _DBRUN.OWNER !
    DUP DUP _DBRUN.SELF !
    _DBRUN-MAGIC SWAP _DBRUN.MAGIC ! ;

\ The uptime at which the next look is due.
: DBRUN-NEXT@  ( runner -- uptime ) _DBRUN.NEXT @ ;

: DBRUN-CLOCK@  ( runner -- clock ) _DBRUN.CLOCK @ ;

\ What the clock did since the last look; this look is remembered.
: _DBRUN-BASIS  ( uptime wall runner -- basis )
    >R
    R@ _DBRUN.HISTORY @ IF
        OVER R@ _DBRUN.UPTIME @ -
        OVER R@ _DBRUN.WALL @ - - ABS
        DBRUN-JUMP-MS > IF DBAS-JUMP ELSE DBAS-CONTINUOUS THEN
    ELSE
        DBAS-ACTIVATION
    THEN
    SWAP R@ _DBRUN.WALL ! SWAP R@ _DBRUN.UPTIME !
    -1 R> _DBRUN.HISTORY ! ;

: _DBRUN-GENERATION  ( runner -- n )
    _DBRUN.OWNER @ DBAO-STORE DBAS-GENERATION@ 1+ ;

\ The earliest due instant, read again only when the store has changed.
: _DBRUN-DUE  ( runner -- utc-s found? )
    DUP _DBRUN-GENERATION OVER _DBRUN.SEEN @ <> IF
        DUP _DBRUN.OWNER @ DBAO-DUE 2 PICK _DBRUN.FOUND ! OVER _DBRUN.AT !
        DUP _DBRUN-GENERATION OVER _DBRUN.SEEN !
    THEN
    DUP _DBRUN.AT @ SWAP _DBRUN.FOUND @ ;

\ Looks for due reminders with the clock as read: UPTIME and WALL in
\ milliseconds, and VALID? whether the wall clock is set.  Fires what is
\ due and returns how many reminders fired, with the owner's status.
: DBRUN-LOOK  ( uptime wall valid? runner -- fired status )
    >R
    2 PICK DBRUN-PERIOD-MS + R@ _DBRUN.NEXT !
    0= IF
        2DROP DBRUN-CLOCK-UNSET R@ _DBRUN.CLOCK !
        0 R> _DBRUN.HISTORY !
        0 DBAO-S-OK EXIT
    THEN
    DBRUN-CLOCK-SET R@ _DBRUN.CLOCK !
    TUCK R@ _DBRUN-BASIS                      ( wall basis )
    R@ _DBRUN-DUE IF                          ( wall basis utc )
        2 PICK 1000 / > IF 2DROP R> DROP 0 DBAO-S-OK EXIT THEN
        R> _DBRUN.OWNER @ DBAO-ACCEPT EXIT
    THEN
    DROP 2DROP R> DROP 0 DBAO-S-OK ;
