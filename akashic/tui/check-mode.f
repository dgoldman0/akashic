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
\  fit run in both modes.
\
\  CHK-EVERY-FRAME   ( -- addr )  the switch: nonzero runs every check
\  CHK-EVERY-FRAME?  ( -- flag )  whether every-frame checks are on
\
\  Prefix: CHK- (public)

PROVIDED akashic-tui-check-mode

VARIABLE CHK-EVERY-FRAME
0 CHK-EVERY-FRAME !

: CHK-EVERY-FRAME?  ( -- flag )  CHK-EVERY-FRAME @ 0<> ;
