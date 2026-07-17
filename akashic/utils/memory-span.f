\ =====================================================================
\  memory-span.f - Policy-neutral bounded memory-span predicates
\ =====================================================================
\  These words reason only about half-open address intervals.  They do
\  not decide whether address zero is a valid caller address, whether an
\  empty span is admitted by a particular API, or who owns either span.
\  Callers keep those policies at their public boundary.
\ =====================================================================

PROVIDED akashic-memory-span

: MSPAN-NONWRAPPING?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    >R DUP R@ + SWAP U< 0= R> DROP ;

: MSPAN-OVERLAP?  ( a1 u1 a2 u2 -- flag )
    2OVER MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    2 PICK 0= IF 2DROP 2DROP 0 EXIT THEN
    \ Both nonempty intervals are nonwrapping, so ordinary unsigned
    \ half-open comparisons are safe and exact adjacency stays disjoint.
    2OVER + >R OVER R> U< >R
    + >R DROP R> U< R> AND ;
