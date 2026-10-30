\ =====================================================================
\  frame-shadow.f -- the shadow check of a rich frame's shortcuts
\ =====================================================================
\
\  Where the inputs of a step of the rich frame build have not changed,
\  the step takes a shortcut: the snapshot adapter reuses an unchanged
\  document's slices, the screen producer copies the runs of rows no draw
\  touched and the controls of a menu that did not change, and the shell
\  producer copies the runs of rows no draw touched.  Each shortcut must
\  give, byte for byte, what the full path gives.
\
\  The facts of what each root's capture read must change whenever its
\  items do, so that a frame can follow change by them: the screen
\  producer judges each item the full path finds changed, and a root whose
\  facts did not move counts as a difference of the root-facts stage.
\
\  A DELTA of Desk's shell replaces the applications' controls the screen
\  producer's comparison found changed, without comparing them again, and
\  keeps their instruments and series, which that comparison found
\  unchanged.  The batch DELTA emitter compares every such item as well,
\  and an item whose comparison disagrees with the producer's counts as a
\  difference of the shell-delta stage.
\
\  The screen producer's comparison pairs the controls by place and checks
\  against their partners only the controls of roots whose facts moved,
\  where the bank on screen and the root facts allow it.  The full
\  comparison runs as well, on the same packed bank, and a result that
\  differs counts as a difference of the comparison stage.
\
\  Where it can, the screen producer makes the pending bank a copy of the
\  bank on screen with the moved roots' items written in.  The bank is
\  then packed and compared in full as well, and a copy that differs from
\  that result counts as a difference of the copy stage.
\
\  Where it can, the screen producer also takes the candidate from the
\  bank on screen and lowers into it only the roots that moved.  The frame
\  is then lowered in full as well, and a candidate that differs from the
\  full one counts as a difference of the unpack stage.
\
\  While the shadow check is on, a step that takes a shortcut also runs its
\  full path, into storage that does not feed the frame, and compares the
\  two results here.  Comparisons are counted in all and by stage, so a run
\  shows which shortcuts its frames took.  A difference is counted, and the
\  first one is kept: its stage, its item, the first byte that differs and
\  the draw, which the stage names in FSHD-DRAW before it compares.  The frame goes on with the
\  shortcut's result, as it does with the check off, so the run sends
\  exactly the frames it would send without it; the run that turned the
\  check on fails when it reads the count.
\
\  The check is off unless a test or a diagnostic run turns it on, and
\  then a shortcut costs one test of the switch.  Each stage keeps its
\  scratch blocks in variables of its own: they come from the heap when a
\  comparison first needs them, are kept for the next one, and are replaced
\  by larger ones when a result outgrows them.  A comparison whose scratch
\  the heap cannot give is counted as skipped, never as passed.
\
\  The module needs nothing but KDOS, and its words name the heap only
\  through the two execution tokens it takes when it loads, so that a test
\  which loads a single word of a stage, without KDOS, can load this
\  module's words with it.
\
\  Prefix: FSHD- (public), _FSHD- (private)

PROVIDED akashic-tui-rterm-frame-shadow

\ Stages: which step's shortcut a comparison checks.
1 CONSTANT FSHD-STAGE-SNAPSHOT
2 CONSTANT FSHD-STAGE-PRODUCER-GLYPHS
3 CONSTANT FSHD-STAGE-PRODUCER-MENUS
4 CONSTANT FSHD-STAGE-SHELL-GLYPHS
5 CONSTANT FSHD-STAGE-ROOT-FACTS
6 CONSTANT FSHD-STAGE-SHELL-DELTA
7 CONSTANT FSHD-STAGE-COMPARISON
8 CONSTANT FSHD-STAGE-COPY
9 CONSTANT FSHD-STAGE-UNPACK

VARIABLE FSHD-ON
VARIABLE FSHD-DRAW
VARIABLE FSHD-CHECKS
VARIABLE FSHD-MISMATCHES
VARIABLE FSHD-SKIPPED
VARIABLE FSHD-FIRST-STAGE
VARIABLE FSHD-FIRST-ITEM
VARIABLE FSHD-FIRST-OFFSET
VARIABLE FSHD-FIRST-DRAW

\ The comparisons each stage made, so that a run shows which shortcuts its
\ frames took.
VARIABLE FSHD-CHECKS-SNAPSHOT
VARIABLE FSHD-CHECKS-PRODUCER-GLYPHS
VARIABLE FSHD-CHECKS-PRODUCER-MENUS
VARIABLE FSHD-CHECKS-SHELL-GLYPHS
VARIABLE FSHD-CHECKS-ROOT-FACTS
VARIABLE FSHD-CHECKS-SHELL-DELTA
VARIABLE FSHD-CHECKS-COMPARISON
VARIABLE FSHD-CHECKS-COPY
VARIABLE FSHD-CHECKS-UNPACK

\ FSHD? ( -- flag )  Whether the shadow check is on.
: FSHD?  ( -- flag )  FSHD-ON @ 0<> ;

\ FSHD-RESET ( -- )  Clear the counts and the first difference.
: FSHD-RESET  ( -- )
    0 FSHD-CHECKS ! 0 FSHD-MISMATCHES ! 0 FSHD-SKIPPED !
    0 FSHD-FIRST-STAGE ! 0 FSHD-FIRST-ITEM !
    0 FSHD-FIRST-OFFSET ! 0 FSHD-FIRST-DRAW !
    0 FSHD-CHECKS-SNAPSHOT ! 0 FSHD-CHECKS-PRODUCER-GLYPHS !
    0 FSHD-CHECKS-PRODUCER-MENUS ! 0 FSHD-CHECKS-SHELL-GLYPHS !
    0 FSHD-CHECKS-ROOT-FACTS ! 0 FSHD-CHECKS-SHELL-DELTA !
    0 FSHD-CHECKS-COMPARISON ! 0 FSHD-CHECKS-COPY !
    0 FSHD-CHECKS-UNPACK ! ;

0 FSHD-ON ! 0 FSHD-DRAW ! FSHD-RESET

\ ---------------------------------------------------------------------
\ Scratch blocks
\ ---------------------------------------------------------------------

VARIABLE _FSHD-BLOCK-A
VARIABLE _FSHD-BLOCK-U
VARIABLE _FSHD-WANT
VARIABLE _FSHD-ALLOCATE-XT   \ ( bytes -- addr ior )
VARIABLE _FSHD-FREE-XT       \ ( addr -- )

' ALLOCATE _FSHD-ALLOCATE-XT !
' FREE _FSHD-FREE-XT !

\ FSHD-GROW ( bytes a-var u-var -- addr|0 )
\   The block whose address A-VAR and size U-VAR hold, of at least BYTES.
\   A larger block replaces a smaller one, so the contents are undefined
\   after the call.  Zero when the heap has no room.
: FSHD-GROW  ( bytes a-var u-var -- addr|0 )
    _FSHD-BLOCK-U ! _FSHD-BLOCK-A ! 8 MAX _FSHD-WANT !
    _FSHD-BLOCK-U @ @ _FSHD-WANT @ U< 0= IF _FSHD-BLOCK-A @ @ EXIT THEN
    _FSHD-BLOCK-A @ @ ?DUP IF _FSHD-FREE-XT @ EXECUTE THEN
    0 _FSHD-BLOCK-A @ ! 0 _FSHD-BLOCK-U @ !
    _FSHD-WANT @ _FSHD-ALLOCATE-XT @ EXECUTE IF DROP 0 EXIT THEN
    DUP _FSHD-BLOCK-A @ !
    _FSHD-WANT @ _FSHD-BLOCK-U @ ! ;

\ FSHD-FREE ( a-var u-var -- )  Give the block back to the heap.
: FSHD-FREE  ( a-var u-var -- )
    0 SWAP ! DUP @ ?DUP IF _FSHD-FREE-XT @ EXECUTE THEN 0 SWAP ! ;

\ ---------------------------------------------------------------------
\ Comparison
\ ---------------------------------------------------------------------

VARIABLE _FSHD-A1
VARIABLE _FSHD-U1
VARIABLE _FSHD-A2
VARIABLE _FSHD-U2
VARIABLE _FSHD-ITEM
VARIABLE _FSHD-STAGE

\ The first offset at which the U bytes at A1 and A2 differ, or U.
: _FSHD-OFFSET  ( a1 a2 u -- offset )
    DUP >R 0 ?DO
        OVER I + C@ OVER I + C@ <> IF 2DROP I UNLOOP R> DROP EXIT THEN
    LOOP 2DROP R> ;

: _FSHD-MISMATCH  ( offset -- )
    FSHD-MISMATCHES @ 0= IF
        FSHD-FIRST-OFFSET !
        _FSHD-STAGE @ FSHD-FIRST-STAGE !
        _FSHD-ITEM @ FSHD-FIRST-ITEM !
        FSHD-DRAW @ FSHD-FIRST-DRAW !
    ELSE
        DROP
    THEN
    1 FSHD-MISMATCHES +! ;

\ The count of STAGE's comparisons, STAGE being one of the stages above.
: _FSHD-STAGE-CHECKS  ( stage -- a )
    DUP FSHD-STAGE-SNAPSHOT = IF DROP FSHD-CHECKS-SNAPSHOT EXIT THEN
    DUP FSHD-STAGE-PRODUCER-GLYPHS = IF DROP FSHD-CHECKS-PRODUCER-GLYPHS EXIT THEN
    DUP FSHD-STAGE-PRODUCER-MENUS = IF DROP FSHD-CHECKS-PRODUCER-MENUS EXIT THEN
    DUP FSHD-STAGE-SHELL-GLYPHS = IF DROP FSHD-CHECKS-SHELL-GLYPHS EXIT THEN
    DUP FSHD-STAGE-ROOT-FACTS = IF DROP FSHD-CHECKS-ROOT-FACTS EXIT THEN
    DUP FSHD-STAGE-SHELL-DELTA = IF DROP FSHD-CHECKS-SHELL-DELTA EXIT THEN
    DUP FSHD-STAGE-COMPARISON = IF DROP FSHD-CHECKS-COMPARISON EXIT THEN
    FSHD-STAGE-COPY = IF FSHD-CHECKS-COPY EXIT THEN
    FSHD-CHECKS-UNPACK ;

\ FSHD-SAME? ( a1 u1 a2 u2 item stage -- flag )
\   Count one comparison of STAGE's ITEM: the shortcut's U1 bytes at A1
\   against the full path's U2 bytes at A2.  A difference in length or in
\   any byte is counted, and kept when it is the first.
: FSHD-SAME?  ( a1 u1 a2 u2 item stage -- flag )
    _FSHD-STAGE ! _FSHD-ITEM ! _FSHD-U2 ! _FSHD-A2 ! _FSHD-U1 ! _FSHD-A1 !
    1 FSHD-CHECKS +! 1 _FSHD-STAGE @ _FSHD-STAGE-CHECKS +!
    _FSHD-U1 @ _FSHD-U2 @ = IF
        _FSHD-U1 @ 0= IF -1 EXIT THEN
        _FSHD-A1 @ _FSHD-U1 @ _FSHD-A2 @ _FSHD-U2 @ COMPARE 0= IF -1 EXIT THEN
    THEN
    _FSHD-A1 @ _FSHD-A2 @ _FSHD-U1 @ _FSHD-U2 @ MIN _FSHD-OFFSET
    _FSHD-MISMATCH 0 ;

\ FSHD-SKIP ( -- )  A comparison that could not run, for want of scratch.
: FSHD-SKIP  ( -- )  1 FSHD-SKIPPED +! ;

\ FSHD-HELD ( held? item stage -- )
\   Count one comparison of STAGE's ITEM that the stage judged itself:
\   HELD? false is a difference, kept when it is the first.
: FSHD-HELD  ( held? item stage -- )
    _FSHD-STAGE ! _FSHD-ITEM !
    1 FSHD-CHECKS +! 1 _FSHD-STAGE @ _FSHD-STAGE-CHECKS +!
    IF EXIT THEN 0 _FSHD-MISMATCH ;
