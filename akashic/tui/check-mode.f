\ =====================================================================
\  check-mode.f -- where the checks that can find only a bug run
\ =====================================================================
\
\  Some checks on the rich path can find something only after a bug has
\  written where it should not: checks of data that nothing has written
\  since it was last checked, and proofs about memory layout that are
\  repeated between the moments memory is lent, allocated or grows.  With
\  every-frame checks on, each of them runs wherever it stands, on every
\  frame.  With them off, which is normal mode, the repeats are skipped
\  and the proofs run when memory is lent, allocated or grows.
\
\  Every-frame checks are off, so compositions and tests run in normal
\  mode, unless something turns them on: a test of the checks they hold,
\  safe mode, or a diagnostic boot.  Checks of new data, of state and of
\  fit run in every mode.
\
\  Safe mode goes further.  Every frame takes the full path, with none of
\  the shortcuts that reuse what an earlier frame built, and every check
\  runs whatever the every-frame switch says.  It is off unless Desk's
\  configuration, a boot option or an anomaly turns it on, and then it
\  stays on for the session, keeping the first reason it was given.
\
\  CHK-EVERY-FRAME   ( -- addr )  the switch: nonzero runs every check
\  CHK-EVERY-FRAME?  ( -- flag )  whether every check runs: the switch is
\                                 on, or safe mode is
\  CHK-SAFE-MODE     ( -- addr )  0, or why safe mode is on: CHK-WHY-CONFIG,
\                                 CHK-WHY-BOOT or CHK-WHY-ANOMALY
\  CHK-SAFE?         ( -- flag )  whether safe mode is on
\  CHK-SAFE-ON       ( why -- )   turn safe mode on, unless it is already
\
\  Prefix: CHK- (public)

PROVIDED akashic-tui-check-mode

1 CONSTANT CHK-WHY-CONFIG
2 CONSTANT CHK-WHY-BOOT
3 CONSTANT CHK-WHY-ANOMALY

VARIABLE CHK-EVERY-FRAME
0 CHK-EVERY-FRAME !
VARIABLE CHK-SAFE-MODE
0 CHK-SAFE-MODE !

: CHK-SAFE?  ( -- flag )  CHK-SAFE-MODE @ 0<> ;
: CHK-EVERY-FRAME?  ( -- flag )  CHK-EVERY-FRAME @ CHK-SAFE-MODE @ OR 0<> ;
: CHK-SAFE-ON  ( why -- )
    DUP 0= CHK-SAFE? OR IF DROP EXIT THEN  CHK-SAFE-MODE ! ;
