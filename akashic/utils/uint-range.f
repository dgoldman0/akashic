\ =====================================================================
\  uint-range.f - Validated half-open integer-range algebra
\ =====================================================================
\  A range is a start cell plus a nonnegative signed-cell count.  Starts
\  are compared as unsigned cells, so high-bit starts are valid when the
\  exclusive end does not wrap.  These words never dereference a start.
\
\  URANGE-OVERLAP? returns validity separately from intersection.  This
\  prevents a fail-closed caller from mistaking malformed geometry for an
\  ordinary disjoint result.  Empty valid ranges never overlap.
\ =====================================================================

PROVIDED akashic-uint-range

: URANGE-VALID?  ( start count -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    OVER + U> 0= ;

\ At least one count is zero or negative, so neither range overlaps; only
\ validity remains to report.  An empty range with a nonnegative count is
\ always valid.
: _URANGE-EDGE-OVERLAP?  ( a-start a-count b-start b-count -- overlap? valid? )
    2OVER URANGE-VALID? 0= IF 2DROP 2DROP 0 0 EXIT THEN
    URANGE-VALID? NIP NIP 0 SWAP ;

: URANGE-OVERLAP?  ( a-start a-count b-start b-count -- overlap? valid? )
    2 PICK 0> OVER 0> AND IF
        \ Both counts are positive, so each range is valid exactly when
        \ its exclusive end does not wrap below its start.
        OVER + 2DUP U> IF 2DROP 2DROP 0 0 EXIT THEN
        2SWAP OVER + 2DUP U> IF 2DROP 2DROP 0 0 EXIT THEN
        \ ( b-start b-end a-start a-end )  Both nonempty ranges are
        \ nonwrapping.  Unsigned half-open comparisons are therefore exact
        \ and equality at either end remains disjoint.
        >R U> SWAP R> U< AND -1 EXIT
    THEN
    _URANGE-EDGE-OVERLAP? ;
